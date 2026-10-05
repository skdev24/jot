import XCTest
@testable import Jot

@MainActor
final class NoteStoreTests: XCTestCase {
    private var vault: URL!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("jot-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
    }

    func testFreshVaultHasDump() throws {
        let store = NoteStore(vaultURL: vault)
        try store.start()
        XCTAssertEqual(store.notes.map(\.title), ["Dump"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Dump.md").path))
    }

    func testSaveWritesMarkdownFile() throws {
        let store = NoteStore(vaultURL: vault)
        try store.start()
        let dump = try XCTUnwrap(store.dumpID)
        store.save(dump, markdown: "- [ ] milk\n", folded: ["Later"])
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Dump.md"), encoding: .utf8), "- [ ] milk\n")
        XCTAssertEqual(store.folded(for: dump), ["Later"])
    }

    func testCreateRenameDelete() throws {
        let store = NoteStore(vaultURL: vault)
        try store.start()
        let note = store.create(title: "Ideas")
        XCTAssertEqual(store.create(title: "ideas").title, "ideas 2", "titles are unique ignoring case")
        XCTAssertEqual(store.rename(note.id, to: "Big: ideas/2026"), "Big- ideas-2026")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Big- ideas-2026.md").path))
        store.delete(note.id)
        XCTAssertFalse(store.notes.contains { $0.id == note.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Big- ideas-2026.md").path))
    }

    func testFilesMadeElsewhereBecomeTabs() throws {
        try "# From Obsidian\n".write(to: vault.appendingPathComponent("Reading.md"), atomically: true, encoding: .utf8)
        let store = NoteStore(vaultURL: vault)
        try store.start()
        XCTAssertTrue(store.notes.contains { $0.title == "Reading" })
        XCTAssertTrue(store.notes.contains { $0.title == "Dump" && $0.isDump })
    }

    func testAssetPathsCannotEscapeVault() throws {
        let store = NoteStore(vaultURL: vault)
        try store.start()
        XCTAssertNotNil(store.assetFile("assets/a.png"))
        XCTAssertNil(store.assetFile("../../etc/passwd"))
        XCTAssertNil(store.assetFile("assets/../../secret"))
    }

    func testCleanTitle() {
        XCTAssertEqual(NoteStore.cleanTitle("  .hidden  "), "hidden")
        XCTAssertEqual(NoteStore.cleanTitle("a/b:c"), "a-b-c")
        XCTAssertEqual(NoteStore.cleanTitle("what? [draft]"), "what draft")
        XCTAssertNil(NoteStore.cleanTitle("   "))
    }

    func testLegacyNotesAreFound() throws {
        let state = vault.appendingPathComponent(".jot", isDirectory: true)
        try FileManager.default.createDirectory(at: state.appendingPathComponent("notes"), withIntermediateDirectories: true)
        let id = UUID()
        let index = #"{"active":"\#(id.uuidString)","notes":[{"id":"\#(id.uuidString)","title":"Dump","isDump":true}]}"#
        try index.write(to: state.appendingPathComponent("notes.json"), atomically: true, encoding: .utf8)
        try "<p>hello</p>".write(to: state.appendingPathComponent("notes/\(id.uuidString.lowercased()).html"), atomically: true, encoding: .utf8)

        let store = NoteStore(vaultURL: vault)
        try store.start()
        XCTAssertEqual(store.pendingMigration.map(\.html), ["<p>hello</p>"])

        store.completeMigration(store.pendingMigration[0], markdown: "hello\n")
        XCTAssertTrue(store.pendingMigration.isEmpty)
        XCTAssertEqual(store.markdown(for: id), "hello\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: state.appendingPathComponent("legacy/notes.json").path), "old files are kept, not deleted")
    }
}

final class ReminderScannerTests: XCTestCase {
    func testFindsOpenDatedTodosOnly() {
        let note = UUID()
        let text = """
        - [ ] call Sam 📅 2026-10-07 15:30
        - [x] done already 📅 2026-10-06
        - [ ] no date here
        - plain bullet 📅 2026-10-08
        - [ ] all day **thing** [[Ordecto]] 📅 2026-10-09
        ```
        - [ ] inside code 📅 2026-10-10
        ```
        """
        let found = ReminderScanner.scan(text, noteID: note, noteTitle: "Dump")
        XCTAssertEqual(found.map(\.text), ["call Sam", "all day thing Ordecto"])
        XCTAssertEqual(found.map(\.hasTime), [true, false])
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: found[0].date)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2026, 10, 7, 15, 30])
    }

    func testIdentifierIsStable() {
        let reminder = Reminder(noteID: UUID(), noteTitle: "Dump", text: "call Sam", date: Date(timeIntervalSince1970: 1_800_000_000), hasTime: true)
        XCTAssertEqual(reminder.identifier, reminder.identifier)
        XCTAssertTrue(reminder.identifier.hasPrefix("jot."))
    }
}
