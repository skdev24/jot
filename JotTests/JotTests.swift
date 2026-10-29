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

final class HoverIntentTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let notch = CGPoint(x: 100, y: 900)

    private func sample(
        _ intent: inout HoverIntent,
        at point: CGPoint? = nil,
        after seconds: TimeInterval,
        inZone: Bool = true,
        atTopEdge: Bool = false,
        upward: CGFloat = 0,
        buttonsDown: Bool = false,
        trigger: OpenTrigger = .rest
    ) -> Bool {
        intent.sample(
            at: point ?? notch, inZone: inZone, atTopEdge: atTopEdge, upward: upward,
            buttonsDown: buttonsDown, trigger: trigger, wait: 0.5, now: start.addingTimeInterval(seconds)
        )
    }

    func testOpensOnceThePointerRests() {
        var intent = HoverIntent()
        XCTAssertFalse(sample(&intent, after: 0))
        XCTAssertFalse(sample(&intent, at: CGPoint(x: 103, y: 901), after: 0.3), "small jitter still counts as resting")
        XCTAssertTrue(sample(&intent, after: 0.5))
    }

    func testPassingAcrossNeverOpens() {
        var intent = HoverIntent()
        for step in 0..<20 {
            let point = CGPoint(x: 20 + CGFloat(step) * 12, y: 900)
            XCTAssertFalse(sample(&intent, at: point, after: Double(step) * 0.05))
        }
    }

    func testPushingIntoTheEdgeOpensRightAway() {
        var intent = HoverIntent()
        XCTAssertFalse(sample(&intent, after: 0, atTopEdge: true, upward: 30, trigger: .push), "the move that reaches the edge doesn't count")
        XCTAssertFalse(sample(&intent, at: CGPoint(x: 112, y: 900), after: 0.05, atTopEdge: true, upward: 25, trigger: .push))
        XCTAssertTrue(sample(&intent, at: CGPoint(x: 124, y: 900), after: 0.1, atTopEdge: true, upward: 25, trigger: .push), "drifting sideways keeps the push")
    }

    func testPushModeIgnoresResting() {
        var intent = HoverIntent()
        XCTAssertFalse(sample(&intent, after: 0, trigger: .push))
        XCTAssertFalse(sample(&intent, after: 3, trigger: .push))
    }

    func testSlowNudgesDontAddUp() {
        var intent = HoverIntent()
        _ = sample(&intent, after: 0, atTopEdge: true, trigger: .push)
        for step in 1...6 {
            XCTAssertFalse(sample(&intent, after: Double(step) * 0.5, atTopEdge: true, upward: 20, trigger: .push))
        }
    }

    func testHeldButtonIsNotAReach() {
        var intent = HoverIntent()
        XCTAssertFalse(sample(&intent, after: 0, buttonsDown: true))
        XCTAssertFalse(sample(&intent, after: 1, buttonsDown: true))
        XCTAssertFalse(sample(&intent, after: 1.2), "resting starts once the button is up")
        XCTAssertTrue(sample(&intent, after: 1.7))
    }

    func testClosingWaitsForThePointerToLeave() {
        var intent = HoverIntent()
        intent.disarm()
        XCTAssertFalse(sample(&intent, after: 0))
        XCTAssertFalse(sample(&intent, after: 2), "still over the notch after it closed")
        XCTAssertFalse(sample(&intent, after: 2.1, inZone: false))
        XCTAssertFalse(sample(&intent, after: 2.2))
        XCTAssertTrue(sample(&intent, after: 2.7))
    }

    func testClickAndOffNeverOpenOnHover() {
        for trigger in [OpenTrigger.click, .off] {
            var intent = HoverIntent()
            XCTAssertFalse(sample(&intent, after: 0, trigger: trigger))
            XCTAssertFalse(sample(&intent, after: 5, atTopEdge: true, upward: 200, trigger: trigger))
        }
    }
}
