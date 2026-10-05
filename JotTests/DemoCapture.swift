import SwiftUI
import WebKit
import XCTest
@testable import Jot

/// Captures the real editor and tab bar for the README demo GIF.
/// Skipped unless `JOT_DEMO_OUT` names a folder to write the snapshots to.
///
/// Drives the shipped editor (Jot/Editor) in a real WKWebView through a short
/// script — open a note, type a dated to-do, search with ⌘P — and writes a
/// PNG per step plus `manifest.json` (file, caret position) for the composer.
@MainActor
final class DemoCapture: XCTestCase {
    private let size = CGSize(width: 608, height: 398) // editor area inside the island
    private var webView: WKWebView!
    private var out: URL!
    private var shots: [[String: Any]] = []

    func testCaptureDemo() async throws {
        guard let path = ProcessInfo.processInfo.environment["JOT_DEMO_OUT"] else {
            throw XCTSkip("Set JOT_DEMO_OUT to capture the README demo.")
        }
        out = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        try renderTabBar()
        try await loadEditor()
        try await script()

        let manifest = try JSONSerialization.data(withJSONObject: ["shots": shots], options: [.prettyPrinted])
        try manifest.write(to: out.appendingPathComponent("manifest.json"))
    }

    // MARK: The scene

    private func script() async throws {
        let day = { (offset: Int) -> String in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: date)
        }
        let dump = """
        ## Today

        - [ ] Ship Jot 2.0 📅 \(day(0)) 18:00
        - [ ] Review [[Launch plan]] with the #team 📅 \(day(1))
        - [x] Book flights to Lisbon
        - [ ] Renew passport 📅 \(day(-2))

        > [!tip] Capture from anywhere
        > Press ⌃⌥N, type, press Esc. It lands here.
        """
        let index: [[String: String]] = [
            ["id": "A", "title": "Dump", "markdown": dump],
            ["id": "B", "title": "Launch plan", "markdown": "## Launch\n\n- [ ] Launch on Product Hunt 📅 \(day(9))\n- [ ] Write the launch thread\n- [ ] Record a 30s demo"],
            ["id": "C", "title": "Ideas", "markdown": "Voice capture from the notch #ideas\n\nLaunch a widget for the lock screen"],
            ["id": "D", "title": "Reading", "markdown": "- [ ] The Shape of Design"],
        ]
        try await js("JotEditor.setPrefs({ fontSize: 15 }); JotEditor.setIndex(index); JotEditor.open('A', markdown, 'Dump', { folded: [] }, 0)", ["index": index, "markdown": dump])
        try await settle(0.6)
        try await js("const e = document.querySelector('.tiptap').editor; e.commands.blur(); document.getElementById('scroller').scrollTop = 0")
        try await shot("base")

        // A fresh to-do at the end of the list, typed a key at a time.
        try await js("""
        const e = document.querySelector('.tiptap').editor
        let end = null
        e.state.doc.descendants((node, pos) => { if (node.type.name === 'taskItem') end = pos + node.nodeSize })
        e.chain().insertContentAt(end, { type: 'taskItem', attrs: { checked: false }, content: [{ type: 'paragraph' }] }).setTextSelection(end + 2).run()
        e.view.focus()
        """)
        try await shot("todo")
        for (index, char) in "Send the deck to Sam ".enumerated() {
            try await type(String(char))
            if index % 2 == 1 { try await shot("type") }
        }
        for char in "@fri 3pm" {
            try await type(String(char))
            try await shot("date")
        }
        try await settle(0.3)
        try await shot("date-menu")
        try await js("document.querySelector('.tiptap').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true, cancelable: true }))")
        try await settle(0.35)
        try await shot("chip")

        // ⌘P: search every note.
        try await js("JotEditor.openPalette('')")
        try await settle(0.35)
        try await shot("palette")
        for char in "launch" {
            try await js("const i = document.querySelector('.jot-palette input'); i.value += c; i.dispatchEvent(new Event('input'))", ["c": String(char)])
            try await settle(0.05)
            try await shot("search")
        }
        try await settle(0.25)
        try await shot("search-done")
    }

    // MARK: Helpers

    private func loadEditor() async throws {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = webView
        window.orderBack(nil)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Editor") ?? Bundle.main.url(forResource: "index", withExtension: "html"))
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        for _ in 0..<50 {
            try await settle(0.1)
            if (try? await webView.evaluateJavaScript("typeof JotEditor === 'object' && !!document.querySelector('.tiptap')")) as? Bool == true { return }
        }
        XCTFail("editor did not load")
    }

    private func type(_ text: String) async throws {
        // The same path as a key press: input rules and suggestions see it.
        try await js("""
        const v = document.querySelector('.tiptap').editor.view
        const { from, to } = v.state.selection
        if (!v.someProp('handleTextInput', (f) => f(v, from, to, t))) v.dispatch(v.state.tr.insertText(t, from, to))
        """, ["t": text])
        try await settle(0.03)
    }

    @discardableResult
    private func js(_ body: String, _ args: [String: Any] = [:]) async throws -> Any? {
        try await webView.callAsyncJavaScript(body, arguments: args, contentWorld: .page)
    }

    private func settle(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    /// Saves the editor at 2× and where the caret is (the snapshot has none).
    private func shot(_ name: String) async throws {
        try await settle(0.04)
        let caret = try await js("""
        const e = document.querySelector('.tiptap').editor
        if (!e.view.hasFocus() || document.querySelector('.jot-palette:not([hidden])')) return null
        const c = e.view.coordsAtPos(e.state.selection.head)
        return [c.left, c.top, c.bottom - c.top]
        """) as? [Double]
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Double(size.width * 2))
        config.afterScreenUpdates = true
        let image = try await webView.takeSnapshot(configuration: config)
        let file = String(format: "%03d-%@.png", shots.count, name)
        try png(image).write(to: out.appendingPathComponent(file))
        var entry: [String: Any] = ["file": file, "name": name]
        if let caret { entry["caret"] = caret }
        shots.append(entry)
    }

    private func png(_ image: NSImage) throws -> Data {
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    private func renderTabBar() throws {
        let titles = ["Dump", "Launch plan", "Ideas", "Reading"]
        let notes = titles.enumerated().map { NoteRecord(id: UUID(), title: $0.element, isDump: $0.offset == 0) }
        let actions = NotchActions(select: { _ in }, create: {}, rename: { _, _ in }, delete: { _ in }, move: { _, _ in }, settings: {})
        let view = TabBar(notes: notes, activeID: notes[0].id, due: [notes[0].id], actions: actions)
            .frame(width: 596)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 596, height: 36)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: out.appendingPathComponent("tabbar.png"))
    }
}
