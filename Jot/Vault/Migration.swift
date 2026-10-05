import Foundation

/// A note from Jot 1.x, stored as editor HTML in `.jot/notes/<id>.html`.
struct LegacyNote: Equatable, Sendable {
    var id: UUID
    var title: String
    var isDump: Bool
    var html: String
    var activeID: UUID
}

/// Jot 1.x kept notes as HTML inside `.jot/` and mirrored Dump to-dos into
/// `items/*.md`. Jot 2 keeps each note as `<title>.md` in the vault. The
/// editor converts the HTML (it owns the schema); this finds the old notes
/// and, once converted, tucks the old files into `.jot/legacy/` — nothing
/// is deleted.
enum Migration {
    private struct OldIndex: Decodable {
        struct Note: Decodable {
            var id: UUID
            var title: String
            var isDump: Bool
        }
        var active: UUID
        var notes: [Note]
    }

    static func legacyNotes(in vault: URL, index: URL) -> [LegacyNote] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: index.path) == false else { return [] }
        let state = vault.appendingPathComponent(".jot", isDirectory: true)
        let read = { (url: URL) in (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

        if let data = try? Data(contentsOf: state.appendingPathComponent("notes.json")),
           let old = try? JSONDecoder().decode(OldIndex.self, from: data), old.notes.isEmpty == false {
            return old.notes.map { note in
                let html = read(state.appendingPathComponent("notes/\(note.id.uuidString.lowercased()).html"))
                return LegacyNote(id: note.id, title: note.title, isDump: note.isDump, html: html, activeID: old.active)
            }
        }
        let dump = state.appendingPathComponent("dump.html")
        if fm.fileExists(atPath: dump.path) {
            let id = UUID()
            return [LegacyNote(id: id, title: "Dump", isDump: true, html: read(dump), activeID: id)]
        }
        return []
    }

    /// Moves 1.x files out of the way so the vault is just notes.
    static func archiveLegacy(in vault: URL) {
        let fm = FileManager.default
        let state = vault.appendingPathComponent(".jot", isDirectory: true)
        let archive = state.appendingPathComponent("legacy", isDirectory: true)
        try? fm.createDirectory(at: archive, withIntermediateDirectories: true)
        let leftovers = [
            vault.appendingPathComponent("items"),
            vault.appendingPathComponent("captures"),
            vault.appendingPathComponent("Backups"),
            vault.appendingPathComponent("needs-review"),
            vault.appendingPathComponent("readable.md"),
            state.appendingPathComponent("notes"),
            state.appendingPathComponent("notes.json"),
            state.appendingPathComponent("dump.html"),
            state.appendingPathComponent("draft.txt"),
        ]
        for url in leftovers where fm.fileExists(atPath: url.path) {
            let target = archive.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: target.path) { continue }
            try? fm.moveItem(at: url, to: target)
        }
    }
}
