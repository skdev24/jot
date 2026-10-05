import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Owns the editor web view for the life of the app and talks to it directly.
///
/// The editor keeps every opened note's live state (text, undo, caret, scroll)
/// in JavaScript, so Swift only hands over Markdown the first time a note
/// opens. Every save names its note, so switching tabs can't write one note's
/// text into another.
@MainActor
final class EditorBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: EditorWebView

    // Events from the editor.
    var onReady: () -> Void = {}
    var onSave: (UUID, String, [String]) -> Void = { _, _, _ in }
    var onEscape: () -> Void = {}
    var onNavigate: (_ id: UUID?, _ title: String?, _ query: String?) -> Void = { _, _, _ in }
    var onCreateNote: (String) -> Void = { _ in }
    var onRename: (UUID, String) -> Void = { _, _ in }
    var onSettings: () -> Void = {}
    /// ⌘1…9 (`index`, -1 = last) or ⌃Tab (`delta`).
    var onSwitchTab: (_ index: Int?, _ delta: Int?) -> Void = { _, _ in }
    /// Saves image bytes into the vault, returning the path for the note.
    var saveAsset: (Data, String) -> String? = { _, _ in nil }
    /// Copies a file into the vault's assets, returning its path.
    var importAsset: (URL) -> String? = { _ in nil }
    /// Resolves jot-asset:// requests to files inside the vault.
    var assetFile: (String) -> URL? = { _ in nil }

    private var ready = false
    private var queue: [() -> Void] = []
    private(set) var opened = Set<UUID>()

    override init() {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        let assets = AssetSchemeHandler()
        config.setURLSchemeHandler(assets, forURLScheme: AssetSchemeHandler.scheme)
        webView = EditorWebView(frame: .zero, configuration: config)
        super.init()
        assets.resolve = { [weak self] path in self?.assetFile(path) }
        webView.bridge = self
        config.userContentController.add(WeakHandler(self), name: "jot")
        webView.navigationDelegate = self
        webView.setValue(true, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .black
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        #if DEBUG
        webView.isInspectable = true
        #endif
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Editor")
            ?? Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    // MARK: Commands

    /// `direction` slides the new note in from the right (+1) or left (-1).
    func open(_ id: UUID, markdown: String, title: String, folded: [String], direction: Int = 0) {
        opened.insert(id)
        call("JotEditor.open(id, markdown, title, { folded }, direction)", [
            "id": id.uuidString, "markdown": markdown, "title": title, "folded": folded, "direction": direction,
        ])
    }

    /// The file changed on disk; the editor takes it unless it has unsaved edits.
    func reload(_ id: UUID, markdown: String, folded: [String]) {
        guard opened.contains(id) else { return }
        call("JotEditor.reload(id, markdown, { folded })", ["id": id.uuidString, "markdown": markdown, "folded": folded])
    }

    func setTitle(_ title: String) {
        call("JotEditor.setTitle(title)", ["title": title])
    }

    func forget(_ id: UUID) {
        opened.remove(id)
        call("JotEditor.forget(id)", ["id": id.uuidString])
    }

    func forgetAll() {
        for id in opened { forget(id) }
    }

    /// Puts the caret back where it was, ready to type.
    func focus() {
        webView.window?.makeFirstResponder(webView)
        call("JotEditor.focus()")
    }

    /// Caret on a fresh line at the end of the open note.
    func capture() {
        webView.window?.makeFirstResponder(webView)
        call("JotEditor.capture()")
    }

    /// Adds Markdown at the end of a note. Calls back false when the note
    /// isn't loaded in the editor, so the caller writes the file instead.
    func append(_ markdown: String, to id: UUID, done: @escaping (Bool) -> Void) {
        guard opened.contains(id) else { return done(false) }
        call("return JotEditor.append(id, markdown)", ["id": id.uuidString, "markdown": markdown]) { value in
            done((value as? Bool) ?? (value as? NSNumber)?.boolValue ?? false)
        }
    }

    func flush() {
        call("JotEditor.flush()")
    }

    func setIndex(_ notes: [[String: String]]) {
        call("JotEditor.setIndex(notes)", ["notes": notes])
    }

    func find(_ query: String) {
        call("JotEditor.find(query)", ["query": query])
    }

    func openPalette(_ query: String = "") {
        webView.window?.makeFirstResponder(webView)
        call("JotEditor.openPalette(query)", ["query": query])
    }

    func reveal() {
        call("JotEditor.reveal()")
    }

    func setPrefs(fontSize: Double) {
        call("JotEditor.setPrefs({ fontSize })", ["fontSize": fontSize])
    }

    /// Converts a Jot 1.x HTML note to Markdown using the editor's schema.
    func convert(_ html: String, done: @escaping (String) -> Void) {
        call("return JotEditor.convert(html)", ["html": html]) { value in
            done(value as? String ?? "")
        }
    }

    private func call(_ body: String, _ arguments: [String: Any] = [:], done: ((Any?) -> Void)? = nil) {
        let run = { [weak self] in
            guard let self else { return }
            self.webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { result in
                switch result {
                case let .success(value): done?(value)
                case .failure: done?(nil)
                }
            }
        }
        if ready { run() } else { queue.append(run) }
    }

    private func resolve(_ requestId: Any?, _ value: [String: String]?) {
        guard let requestId else { return }
        call("JotEditor.resolve(requestId, value)", ["requestId": requestId, "value": value ?? NSNull()])
    }

    // MARK: Files dropped from Finder

    /// Images are copied into the vault's assets; other files become links.
    func dropFiles(_ urls: [URL], at point: CGPoint) {
        let items: [[String: String]] = urls.compactMap { url in
            let type = UTType(filenameExtension: url.pathExtension)
            if type?.conforms(to: .image) == true, let path = importAsset(url) {
                return ["kind": "image", "path": path, "name": url.deletingPathExtension().lastPathComponent]
            }
            return ["kind": "file", "url": url.absoluteString, "name": url.lastPathComponent]
        }
        guard items.isEmpty == false else { return }
        call("JotEditor.insertFiles(x, y, items)", ["x": point.x, "y": point.y, "items": items])
    }

    /// A pasted screenshot (image data, no text): save it and insert it at
    /// the caret. Covers clipboards WebKit doesn't expose as files.
    func pasteImage(_ data: Data) {
        guard let path = saveAsset(data, "png") else { return }
        call("JotEditor.insertImage(path)", ["path": path])
    }

    /// ⌘⇧V: paste the clipboard's text without its formatting.
    func pastePlain() {
        guard let text = NSPasteboard.general.string(forType: .string), text.isEmpty == false else { return }
        call("JotEditor.pastePlain(text)", ["text": text])
    }

    private func pickImage(_ requestId: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.level = .statusBar + 1
        NSApp.activate()
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url, let path = self.importAsset(url) else {
                return self.resolve(requestId, nil)
            }
            self.resolve(requestId, ["path": path, "name": url.deletingPathExtension().lastPathComponent])
        }
    }

    // MARK: Messages

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        let noteID = (body["noteId"] as? String).flatMap(UUID.init(uuidString:))
        switch type {
        case "ready":
            ready = true
            opened.removeAll()
            onReady()
            let pending = queue
            queue.removeAll()
            pending.forEach { $0() }
        case "save":
            guard let noteID else { return }
            let meta = body["meta"] as? [String: Any]
            onSave(noteID, body["markdown"] as? String ?? "", meta?["folded"] as? [String] ?? [])
        case "escape":
            onEscape()
        case "copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body["text"] as? String ?? "", forType: .string)
        case "openURL":
            guard let raw = body["url"] as? String, let url = URL(string: raw) else { return }
            if url.isFileURL, FileManager.default.fileExists(atPath: url.path) == false { return }
            NSWorkspace.shared.open(url)
        case "navigate":
            onNavigate(noteID, body["title"] as? String, body["query"] as? String)
        case "createNote":
            onCreateNote(body["title"] as? String ?? "")
        case "rename":
            guard let noteID else { return }
            onRename(noteID, body["title"] as? String ?? "")
        case "settings":
            onSettings()
        case "switchTab":
            onSwitchTab((body["index"] as? NSNumber)?.intValue, (body["delta"] as? NSNumber)?.intValue)
        case "saveImage":
            let data = (body["data"] as? String).flatMap { Data(base64Encoded: $0) }
            let ext = (body["ext"] as? String ?? "png").replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
            let path = data.flatMap { saveAsset($0, ext.isEmpty ? "png" : ext) }
            resolve(body["requestId"], path.map { ["path": $0] })
        case "pickImage":
            pickImage(body["requestId"])
        default:
            break
        }
    }

    // The page is the editor and nothing else: links open in the browser.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .other, navigationAction.request.url?.isFileURL == true {
            decisionHandler(.allow)
            return
        }
        if let url = navigationAction.request.url, url.isFileURL == false, url.scheme != AssetSchemeHandler.scheme {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        opened.removeAll()
        webView.reload()
    }
}

/// Serves `jot-asset:///assets/shot.png` from the vault so notes can show
/// local images without giving the page access to the disk.
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "jot-asset"
    var resolve: (String) -> URL? = { _ in nil }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        let relative = url.path.removingPercentEncoding?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        guard let file = resolve(relative), let data = try? Data(contentsOf: file) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

/// WKUserContentController retains its handlers; this breaks the cycle.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(_ target: any WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

struct EditorHost: NSViewRepresentable {
    let bridge: EditorBridge

    func makeNSView(context: Context) -> EditorWebView { bridge.webView }
    func updateNSView(_ nsView: EditorWebView, context: Context) {}
}

final class EditorWebView: WKWebView {
    weak var bridge: EditorBridge?

    override var isOpaque: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // The island is a non-activating panel: make it key on the first click so
    // the caret lands and typing works without a second click.
    override func mouseDown(with event: NSEvent) {
        if window?.isKeyWindow == false { window?.makeKey() }
        super.mouseDown(with: event)
    }

    // ⌘V with only image data on the clipboard (a screenshot) is handled
    // here; everything else is the editor's own paste.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Paste and Match Style (⌘⇧V, and ⌥⌘⇧V as some apps have it). Jot has
        // no menu bar, so nothing else would route it to the page.
        if event.charactersIgnoringModifiers?.lowercased() == "v",
           flags == [.command, .shift] || flags == [.command, .shift, .option],
           let bridge, window?.firstResponder === self {
            bridge.pastePlain()
            return true
        }
        if flags == .command, event.charactersIgnoringModifiers == "v", let bridge {
            let board = NSPasteboard.general
            let types = board.types ?? []
            let hasText = types.contains(.string) || types.contains(.html) || types.contains(.rtf) || types.contains(.fileURL)
            if hasText == false,
               let image = NSImage(pasteboard: board),
               let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                bridge.pasteImage(png)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    // Finder files are handled natively (copied into assets / linked);
    // text and links fall through to the editor's own drop handling.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard urls.isEmpty == false, let bridge else { return super.performDragOperation(sender) }
        super.draggingExited(sender)
        let point = convert(sender.draggingLocation, from: nil)
        bridge.dropFiles(urls, at: CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y))
        return true
    }
}
