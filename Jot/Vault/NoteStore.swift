import AppKit
import Foundation
import Observation

/// One tab. The note's text lives in `<vault>/<title>.md`; this record only
/// carries what Markdown can't: a stable id, the tab order, and which
/// headings are folded.
struct NoteRecord: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var title: String
    var isDump: Bool
    var folded: [String] = []
}

/// The vault: a plain folder of Markdown files that Obsidian, git and iCloud
/// can share. App state sits in `.jot/` beside the notes.
///
///     ~/Documents/Jot/
///       Dump.md
///       Ideas.md
///       assets/            pasted and dropped images
///       .jot/index.json    tab order, ids, folds
///       .jot/backups/      rolling snapshots of the .md files
@MainActor
@Observable
final class NoteStore {
    private(set) var notes: [NoteRecord] = []
    private(set) var activeNoteID = UUID()
    private(set) var vaultURL: URL
    private(set) var reminders: [Reminder] = []

    /// Called when a note's file changed on disk, not by us.
    @ObservationIgnored var onExternalChange: (UUID, String) -> Void = { _, _ in }
    /// Called when files appear, vanish or get renamed outside Jot.
    @ObservationIgnored var onNotesChanged: () -> Void = {}
    /// Called whenever the scanned reminders change.
    @ObservationIgnored var onRemindersChanged: ([Reminder]) -> Void = { _ in }

    /// Old HTML notes waiting to be converted by the editor (see Migration).
    private(set) var pendingMigration: [LegacyNote] = []

    @ObservationIgnored private var lastWritten: [UUID: String] = [:]
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var backupTimer: Timer?
    @ObservationIgnored private var lastBackupSignature = 0

    init(vaultURL: URL = NoteStore.defaultVaultURL) {
        self.vaultURL = vaultURL
    }

    nonisolated static var defaultVaultURL: URL {
        if let path = UserDefaults.standard.string(forKey: Prefs.vaultPath), path.isEmpty == false {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return documents.appendingPathComponent("Jot", isDirectory: true)
    }

    var activeNote: NoteRecord? { notes.first { $0.id == activeNoteID } }
    var dumpID: UUID? { notes.first(where: \.isDump)?.id }

    /// Open to-dos due today or earlier.
    var dueCount: Int {
        let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        return reminders.filter { $0.date < endOfToday }.count
    }

    // MARK: Lifecycle

    func start() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: stateURL, withIntermediateDirectories: true)
        pendingMigration = Migration.legacyNotes(in: vaultURL, index: indexURL)
        loadIndex()
        reconcileWithDisk()
        // Quick capture always needs somewhere to land, even in a folder of
        // notes made elsewhere (an Obsidian vault, say).
        if notes.contains(where: \.isDump) == false, pendingMigration.isEmpty {
            let dump = NoteRecord(id: UUID(), title: uniqueTitle("Dump"), isDump: true)
            notes.insert(dump, at: 0)
            activeNoteID = dump.id
            try? write("", for: dump)
        }
        persistIndex()
        rescanReminders()
        watch()
        startBackups()
    }

    /// Point Jot at another folder. Notes already open in the editor must be
    /// forgotten by the caller.
    func switchVault(to url: URL) throws {
        watcher = nil
        vaultURL = url
        notes = []
        lastWritten = [:]
        UserDefaults.standard.set(url.path, forKey: Prefs.vaultPath)
        try start()
    }

    // MARK: Reading and writing notes

    func fileURL(for note: NoteRecord) -> URL {
        vaultURL.appendingPathComponent(Self.fileName(for: note.title))
    }

    func markdown(for id: UUID) -> String {
        guard let note = notes.first(where: { $0.id == id }) else { return "" }
        return (try? String(contentsOf: fileURL(for: note), encoding: .utf8)) ?? ""
    }

    func folded(for id: UUID) -> [String] {
        notes.first { $0.id == id }?.folded ?? []
    }

    /// Saves one note. The editor names the note it is saving, so a late save
    /// can never land in whichever tab happens to be active.
    func save(_ id: UUID, markdown: String, folded: [String]) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if notes[index].folded != folded {
            notes[index].folded = folded
            persistIndex()
        }
        guard lastWritten[id] != markdown else { return }
        try? write(markdown, for: notes[index])
        rescanReminders()
    }

    /// Appends to a note that isn't loaded in the editor.
    func append(_ text: String, to id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        var current = markdown(for: id)
        if current.isEmpty == false, current.hasSuffix("\n") == false { current += "\n" }
        if current.isEmpty == false { current += "\n" }
        try? write(current + text + "\n", for: note)
        rescanReminders()
    }

    private func write(_ markdown: String, for note: NoteRecord) throws {
        lastWritten[note.id] = markdown
        try AtomicFile.write(markdown, to: fileURL(for: note))
    }

    // MARK: Tabs

    func select(_ id: UUID) {
        guard id != activeNoteID, notes.contains(where: { $0.id == id }) else { return }
        activeNoteID = id
        persistIndex()
    }

    @discardableResult
    func create(title wanted: String? = nil) -> NoteRecord {
        let base = Self.cleanTitle(wanted ?? "") ?? "Note"
        let title = uniqueTitle(base)
        let note = NoteRecord(id: UUID(), title: title, isDump: false)
        notes.append(note)
        activeNoteID = note.id
        try? write("", for: note)
        persistIndex()
        return note
    }

    /// Renames the note and its file. Returns the title actually used.
    @discardableResult
    func rename(_ id: UUID, to wanted: String) -> String? {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              let clean = Self.cleanTitle(wanted) else { return nil }
        let old = notes[index]
        if clean == old.title { return clean }
        let title = uniqueTitle(clean, ignoring: id)
        let from = fileURL(for: old)
        notes[index].title = title
        let to = fileURL(for: notes[index])
        do {
            if FileManager.default.fileExists(atPath: from.path) {
                try FileManager.default.moveItem(at: from, to: to)
            }
        } catch {
            notes[index].title = old.title
            return nil
        }
        persistIndex()
        rescanReminders()
        return title
    }

    /// Moves the note's file to the Trash (recoverable) and drops the tab.
    func delete(_ id: UUID) {
        guard notes.count > 1, let index = notes.firstIndex(where: { $0.id == id }), notes[index].isDump == false else { return }
        let url = fileURL(for: notes[index])
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        notes.remove(at: index)
        lastWritten[id] = nil
        if activeNoteID == id { activeNoteID = notes[0].id }
        persistIndex()
        rescanReminders()
    }

    func move(_ id: UUID, to destination: Int) {
        guard let from = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes.remove(at: from)
        notes.insert(note, at: min(max(destination, 0), notes.count))
        persistIndex()
    }

    func note(titled title: String) -> NoteRecord? {
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return notes.first { $0.title.lowercased() == wanted }
    }

    // MARK: Assets

    /// Saves pasted image data into `assets/` and returns the path the note
    /// should use (relative to the vault).
    func saveAsset(_ data: Data, ext: String) throws -> String {
        let name = "\(Self.stamp()).\(ext.lowercased())"
        let url = assetsURL.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return "assets/\(name)"
    }

    /// Copies a dropped/picked file into `assets/`.
    func importAsset(_ source: URL) throws -> String {
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let base = source.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        var name = "\(base.isEmpty ? Self.stamp() : base).\(ext)"
        var counter = 2
        while FileManager.default.fileExists(atPath: assetsURL.appendingPathComponent(name).path) {
            name = "\(base)-\(counter).\(ext)"
            counter += 1
        }
        try FileManager.default.copyItem(at: source, to: assetsURL.appendingPathComponent(name))
        return "assets/\(name)"
    }

    /// Resolves `assets/…` for the editor's jot-asset:// scheme, refusing
    /// anything that escapes the vault.
    func assetFile(_ relative: String) -> URL? {
        let url = vaultURL.appendingPathComponent(relative).standardizedFileURL
        guard url.path.hasPrefix(vaultURL.standardizedFileURL.path + "/") else { return nil }
        return url
    }

    // MARK: Search index

    func index() -> [[String: String]] {
        notes.map { ["id": $0.id.uuidString, "title": $0.title, "markdown": markdown(for: $0.id)] }
    }

    // MARK: Migration

    /// Finishes converting an old HTML note once the editor produced Markdown.
    func completeMigration(_ legacy: LegacyNote, markdown: String) {
        var note = NoteRecord(id: legacy.id, title: uniqueTitle(Self.cleanTitle(legacy.title) ?? "Note", ignoring: legacy.id), isDump: legacy.isDump)
        if let existing = notes.firstIndex(where: { $0.id == legacy.id }) {
            note.folded = notes[existing].folded
            notes[existing] = note
        } else {
            notes.append(note)
        }
        try? write(markdown, for: note)
        pendingMigration.removeAll { $0.id == legacy.id }
        if pendingMigration.isEmpty {
            if notes.contains(where: { $0.id == legacy.activeID }) { activeNoteID = legacy.activeID }
            else if let first = notes.first { activeNoteID = first.id }
            Migration.archiveLegacy(in: vaultURL)
        }
        persistIndex()
        rescanReminders()
    }

    // MARK: Reminders

    func rescanReminders() {
        var found: [Reminder] = []
        for note in notes {
            found += ReminderScanner.scan(markdown(for: note.id), noteID: note.id, noteTitle: note.title)
        }
        found.sort { $0.date < $1.date }
        guard found != reminders else { return }
        reminders = found
        onRemindersChanged(found)
    }

    // MARK: Index file

    private var stateURL: URL { vaultURL.appendingPathComponent(".jot", isDirectory: true) }
    private var indexURL: URL { stateURL.appendingPathComponent("index.json") }
    private var assetsURL: URL { vaultURL.appendingPathComponent("assets", isDirectory: true) }
    private var backupsURL: URL { stateURL.appendingPathComponent("backups", isDirectory: true) }

    private struct IndexFile: Codable {
        var version = 2
        var active: UUID
        var notes: [NoteRecord]
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let file = try? JSONDecoder().decode(IndexFile.self, from: data) else { return }
        notes = file.notes
        activeNoteID = file.active
    }

    private func persistIndex() {
        guard notes.isEmpty == false else { return }
        if notes.contains(where: { $0.id == activeNoteID }) == false { activeNoteID = notes[0].id }
        let file = IndexFile(active: activeNoteID, notes: notes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        try? AtomicFile.write(data, to: indexURL)
    }

    /// The folder is the truth: notes whose file vanished are dropped, and
    /// .md files made elsewhere (Obsidian, Finder) become tabs.
    private func reconcileWithDisk() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: vaultURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let migrating = Set(pendingMigration.map(\.id))
        // 1.x generated readable.md; it's archived with the rest, never a tab.
        let generated: Set<String> = migrating.isEmpty ? [] : ["readable"]
        let titles = Set(files.filter { $0.pathExtension.lowercased() == "md" }.map { $0.deletingPathExtension().lastPathComponent })
            .subtracting(generated)
        notes.removeAll { titles.contains($0.title) == false && migrating.contains($0.id) == false && $0.isDump == false }
        for (index, note) in notes.enumerated() where note.isDump && titles.contains(note.title) == false && migrating.contains(note.id) == false {
            try? write("", for: notes[index])
        }
        let known = Set(notes.map(\.title))
        for title in titles.sorted() where known.contains(title) == false {
            notes.append(NoteRecord(id: UUID(), title: title, isDump: false))
        }
        if notes.contains(where: \.isDump) == false, let dump = notes.firstIndex(where: { $0.title == "Dump" }) {
            notes[dump].isDump = true
        }
        for note in notes where lastWritten[note.id] == nil {
            lastWritten[note.id] = try? String(contentsOf: fileURL(for: note), encoding: .utf8)
        }
    }

    // MARK: Watching the folder

    private func watch() {
        watcher = FolderWatcher(url: vaultURL) { [weak self] in
            Task { @MainActor in self?.folderChanged() }
        }
    }

    private func folderChanged() {
        let before = notes.map(\.title)
        reconcileWithDisk()
        if notes.map(\.title) != before {
            persistIndex()
            onNotesChanged()
        }
        for note in notes {
            guard let text = try? String(contentsOf: fileURL(for: note), encoding: .utf8) else { continue }
            if text != lastWritten[note.id] {
                lastWritten[note.id] = text
                onExternalChange(note.id, text)
            }
        }
        rescanReminders()
    }

    // MARK: Backups

    /// Every 30 minutes, if anything changed, the .md files are copied to
    /// `.jot/backups/<time>/`. The newest 30 snapshots are kept.
    private func startBackups() {
        backupTimer?.invalidate()
        backupTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in try? self?.backup(force: false) }
        }
        try? backup(force: false)
    }

    func backup(force: Bool) throws {
        let fm = FileManager.default
        let files = notes.map { fileURL(for: $0) }.filter { fm.fileExists(atPath: $0.path) }
        var hasher = Hasher()
        for url in files {
            hasher.combine(url.lastPathComponent)
            hasher.combine((try? Data(contentsOf: url)) ?? Data())
        }
        let signature = hasher.finalize()
        if force == false, signature == lastBackupSignature { return }
        lastBackupSignature = signature
        let folder = backupsURL.appendingPathComponent(Self.stamp(), isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for url in files {
            try? fm.copyItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
        }
        let snapshots = ((try? fm.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: nil)) ?? [])
            .filter(\.hasDirectoryPath)
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in snapshots.dropFirst(30) { try? fm.removeItem(at: old) }
    }

    func revealVault() {
        NSWorkspace.shared.activateFileViewerSelecting([vaultURL])
    }

    // MARK: Names

    /// A title that is safe as a file name on macOS (and in Obsidian).
    static func cleanTitle(_ raw: String) -> String? {
        var title = raw.replacingOccurrences(of: "[/:\\\\\\n\\r\\t]+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "[*\"<>|?#^\\[\\]]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while title.hasPrefix(".") { title.removeFirst() }
        if title.count > 100 { title = String(title.prefix(100)).trimmingCharacters(in: .whitespaces) }
        return title.isEmpty ? nil : title
    }

    static func fileName(for title: String) -> String { "\(title).md" }

    private func uniqueTitle(_ base: String, ignoring id: UUID? = nil) -> String {
        let taken = Set(notes.filter { $0.id != id }.map { $0.title.lowercased() })
        let onDisk = { (title: String) in
            FileManager.default.fileExists(atPath: self.vaultURL.appendingPathComponent(Self.fileName(for: title)).path)
                && self.notes.contains(where: { $0.id == id && $0.title == title }) == false
        }
        if taken.contains(base.lowercased()) == false, onDisk(base) == false { return base }
        var counter = 2
        while taken.contains("\(base) \(counter)".lowercased()) || onDisk("\(base) \(counter)") { counter += 1 }
        return "\(base) \(counter)"
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
