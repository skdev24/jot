import AppKit
import SwiftUI

final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
}

enum NotchGeo {
    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0 && screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
    }

    static func compact(on screen: NSScreen) -> NSRect {
        let frame = screen.frame
        if hasNotch(screen),
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            let height = screen.safeAreaInsets.top
            return NSRect(x: left.maxX, y: frame.maxY - height, width: right.minX - left.maxX, height: height)
        }
        let height = max(frame.maxY - screen.visibleFrame.maxY, 32)
        return NSRect(x: frame.midX - 98, y: frame.maxY - height, width: 196, height: height)
    }

    static func strip(on screen: NSScreen) -> NSRect {
        let compact = compact(on: screen)
        let width: CGFloat = 640
        let height = compact.height + 460
        return NSRect(x: compact.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }
}

@Observable
final class NotchState {
    var expanded = false
    var notchHeight: CGFloat = 32
    var notchWidth: CGFloat = 184
    /// Open to-dos due today or earlier, shown beside the closed notch.
    var due = 0
}

/// Runs the island: when it opens and closes, which display it uses, and
/// how notes move between the vault and the editor.
@MainActor
final class NotchController: NSObject {
    let panel = NotchPanel()
    private let store: NoteStore
    private let bridge = EditorBridge()
    private let state = NotchState()
    private var pinned = false
    /// The display the island is open on (or opening on).
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private var poll: Timer?
    /// When a drag held over the notch opens it.
    private var openAfter: Date?
    private var intent = HoverIntent()
    /// Displays the island may use; refreshed when displays or settings
    /// change, since hover checks run on every pointer move.
    private var allowedIDs = Displays.allowedIDs
    private var hideAfter: Date?
    private var ignoreResignUntil: Date?
    private var opening = false
    private var dragChangeCount = 0
    private var dueTimer: Timer?
    var onOpenSettings: () -> Void = {}
    /// Reminders rescanned (for notifications).
    var onReminders: ([Reminder]) -> Void = { _ in }

    init(store: NoteStore) {
        self.store = store
        super.init()
        wireBridge()
        wireStore()
        let view = NotchView(state: state, bridge: bridge, actions: NotchActions(
            select: { [weak self] in self?.switchTo($0) },
            create: { [weak self] in self?.createNote(title: "") },
            rename: { [weak self] in self?.rename($0, to: $1) },
            delete: { [weak self] in self?.delete($0) },
            move: { [weak self] id, index in self?.store.move(id, to: index) },
            settings: { [weak self] in self?.onOpenSettings() }
        ))
        let host = ClickableHostingView(rootView: view.environment(store))
        host.safeAreaRegions = []
        host.additionalSafeAreaInsets = NSEdgeInsets()
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.chrome.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: panel.chrome.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: panel.chrome.trailingAnchor),
            host.topAnchor.constraint(equalTo: panel.chrome.topAnchor),
            host.bottomAnchor.constraint(equalTo: panel.chrome.bottomAnchor),
        ])
        panel.contentView = panel.chrome
        listen()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Screen objects are rebuilt when displays change; keep ours only if it's still attached.
                let id = self.screen.flatMap(Displays.displayID)
                self.screen = NSScreen.screens.first { Displays.displayID($0) == id }
                self.allowedIDs = Displays.allowedIDs
                self.place()
                self.showRestingBadge()
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resigned() }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.preferencesChanged() }
        }
        // The due count changes with the clock, not just with edits.
        dueTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateDue() }
        }
    }

    // MARK: Wiring

    private func wireBridge() {
        bridge.onReady = { [weak self] in self?.editorReady() }
        bridge.onSave = { [weak self] id, markdown, folded in
            self?.store.save(id, markdown: markdown, folded: folded)
        }
        bridge.onEscape = { [weak self] in
            self?.pinned = false
            self?.collapse()
        }
        bridge.onNavigate = { [weak self] id, title, query in self?.navigate(id: id, title: title, query: query) }
        bridge.onCreateNote = { [weak self] title in self?.createNote(title: title) }
        bridge.onRename = { [weak self] id, title in self?.rename(id, to: title) }
        bridge.onSettings = { [weak self] in self?.onOpenSettings() }
        bridge.onSwitchTab = { [weak self] index, delta in self?.switchTab(index: index, delta: delta) }
        bridge.saveAsset = { [weak self] data, ext in try? self?.store.saveAsset(data, ext: ext) }
        bridge.importAsset = { [weak self] url in try? self?.store.importAsset(url) }
        bridge.assetFile = { [weak self] path in self?.store.assetFile(path) }
    }

    private func wireStore() {
        store.onExternalChange = { [weak self] id, markdown in
            guard let self else { return }
            self.bridge.reload(id, markdown: markdown, folded: self.store.folded(for: id))
        }
        store.onNotesChanged = { [weak self] in
            guard let self else { return }
            self.bridge.setIndex(self.store.index())
            if self.bridge.opened.contains(self.store.activeNoteID) == false { self.openActive() }
        }
        store.onRemindersChanged = { [weak self] reminders in
            self?.updateDue()
            self?.onReminders(reminders)
        }
    }

    private func editorReady() {
        bridge.setPrefs(fontSize: Prefs.defaults.double(forKey: Prefs.fontSize))
        migrate { [weak self] in
            guard let self else { return }
            self.bridge.setIndex(self.store.index())
            self.openActive()
        }
    }

    /// First launch after 1.x: the editor converts each HTML note to Markdown.
    private func migrate(_ done: @escaping () -> Void) {
        guard let next = store.pendingMigration.first else { return done() }
        bridge.convert(next.html) { [weak self] markdown in
            guard let self else { return }
            self.store.completeMigration(next, markdown: markdown)
            self.migrate(done)
        }
    }

    private func openActive(direction: Int = 0) {
        guard let note = store.activeNote else { return }
        bridge.open(note.id, markdown: store.markdown(for: note.id), title: note.title, folded: note.folded, direction: direction)
    }

    // MARK: Notes

    func switchTo(_ id: UUID, query: String? = nil) {
        let order = store.notes.map(\.id)
        let from = order.firstIndex(of: store.activeNoteID) ?? 0
        let to = order.firstIndex(of: id) ?? 0
        if id != store.activeNoteID {
            bridge.flush()
            store.select(id)
            openActive(direction: to == from ? 0 : (to > from ? 1 : -1))
        }
        if let query, query.isEmpty == false { bridge.find(query) }
    }

    private func switchTab(index: Int?, delta: Int?) {
        let ids = store.notes.map(\.id)
        guard ids.isEmpty == false else { return }
        var target: Int
        if let index {
            target = index < 0 ? ids.count - 1 : index
        } else {
            let current = ids.firstIndex(of: store.activeNoteID) ?? 0
            target = (current + (delta ?? 1) + ids.count) % ids.count
        }
        guard target < ids.count else { return }
        switchTo(ids[target])
    }

    private func navigate(id: UUID?, title: String?, query: String?) {
        if let id, store.notes.contains(where: { $0.id == id }) {
            return switchTo(id, query: query)
        }
        guard let title, title.isEmpty == false else { return }
        if let note = store.note(titled: title) {
            switchTo(note.id, query: query)
        } else {
            // [[Links]] to notes that don't exist yet create them.
            createNote(title: title)
        }
    }

    private func createNote(title: String) {
        bridge.flush()
        let note = store.create(title: title.isEmpty ? nil : title)
        bridge.open(note.id, markdown: "", title: note.title, folded: [], direction: 1)
        bridge.setIndex(store.index())
        bridge.focus()
    }

    private func rename(_ id: UUID, to title: String) {
        guard let used = store.rename(id, to: title) else {
            if let note = store.activeNote { bridge.setTitle(note.title) }
            return
        }
        if id == store.activeNoteID { bridge.setTitle(used) }
        bridge.setIndex(store.index())
    }

    private func delete(_ id: UUID) {
        bridge.flush()
        bridge.forget(id)
        let wasActive = id == store.activeNoteID
        store.delete(id)
        if wasActive { openActive(direction: -1) }
        bridge.setIndex(store.index())
    }

    /// Settings picked another folder: drop everything the editor holds and
    /// start over from the new vault.
    func switchVault(to url: URL) {
        bridge.flush()
        bridge.forgetAll()
        try? store.switchVault(to: url)
        migrate { [weak self] in
            guard let self else { return }
            self.bridge.setIndex(self.store.index())
            self.openActive()
            self.updateDue()
        }
    }

    // MARK: Entry points (shortcut, capture, Services, notifications)

    func toggle() {
        if state.expanded {
            pinned = false
            collapse()
        } else {
            pinned = true
            expand(on: preferredScreen(forPointer: true))
        }
    }

    /// The capture shortcut: island open on Dump, caret on a fresh line.
    func capture() {
        if let dump = store.dumpID { switchTo(dump) }
        pinned = true
        if state.expanded == false { expand(on: preferredScreen(forPointer: true)) }
        panel.makeKey()
        bridge.capture()
    }

    /// Text from the Services menu (or anywhere else) lands at the end of Dump.
    func sendToDump(_ markdown: String) {
        guard let dump = store.dumpID else { return }
        bridge.append(markdown, to: dump) { [weak self] handled in
            guard let self else { return }
            if handled == false { self.store.append(markdown, to: dump) }
            self.peek(on: dump)
        }
    }

    /// From a notification: open the note at the to-do.
    func openNote(_ id: UUID, at text: String) {
        pinned = true
        if state.expanded == false { expand(on: preferredScreen(forPointer: true)) }
        panel.makeKey()
        switchTo(id, query: text)
    }

    /// Show the island briefly (after a Services capture) without taking focus.
    private func peek(on id: UUID) {
        switchTo(id)
        if state.expanded { return }
        expand(on: preferredScreen(forPointer: false))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, self.pinned == false, self.panel.isKeyWindow == false, self.overPanelOrNotch == false else { return }
            self.collapse()
        }
    }

    // MARK: Hover

    private func listen() {
        let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        // deltaY grows downward, and keeps reporting motion at the top edge
        // where the pointer itself can't move any more.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: moved, handler: { [weak self] event in
            let upward = -event.deltaY
            Task { @MainActor in self?.tick(upward: upward) }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: moved, handler: { [weak self] event in
            self?.tick(upward: -event.deltaY)
            return event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            let left = event.type == .leftMouseDown
            Task { @MainActor in
                self?.dragChangeCount = NSPasteboard(name: .drag).changeCount
                self?.closeIfMouseOutside()
                if left { self?.openIfNotchClicked() }
            }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.window !== self.panel, self.state.expanded { self.collapse() }
            // The closed island's due badge can take a click on the notch.
            if event.window === self.panel, event.type == .leftMouseDown { self.openIfNotchClicked() }
            return event
        }) { monitors.append(monitor) }
        poll = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Something (text, a link, a file) is being dragged right now.
    private var isDragging: Bool {
        NSEvent.pressedMouseButtons & 1 == 1 && NSPasteboard(name: .drag).changeCount != dragChangeCount
    }

    private func tick(upward: CGFloat = 0) {
        let mouse = NSEvent.mouseLocation
        let now = Date()
        guard state.expanded || opening, let screen else {
            return considerOpening(mouse: mouse, upward: upward, now: now)
        }
        let notch = NotchGeo.compact(on: screen).insetBy(dx: -20, dy: -10)
        if panel.frame.insetBy(dx: -12, dy: -12).union(notch).contains(mouse) {
            hideAfter = nil
            return
        }
        // Peeking closes when the pointer leaves. Once you're typing (the panel
        // is key) or opened it with the shortcut, it stays until you click away.
        if pinned || panel.isKeyWindow || isDragging {
            hideAfter = nil
            return
        }
        if hideAfter == nil { hideAfter = now.addingTimeInterval(0.28) }
        if now >= (hideAfter ?? .distantFuture) { collapse() }
    }

    /// The island is closed: is the pointer asking for it?
    private func considerOpening(mouse: NSPoint, upward: CGFloat, now: Date) {
        guard let screen = activeScreen, allows(screen) else {
            openAfter = nil
            return intent.leave()
        }
        let compact = NotchGeo.compact(on: screen)
        // Dragging something onto the notch always opens it, so it can be dropped.
        if isDragging {
            guard compact.insetBy(dx: -20, dy: -10).contains(mouse) else {
                openAfter = nil
                return
            }
            if openAfter == nil { openAfter = now.addingTimeInterval(0.12) }
            if now >= (openAfter ?? .distantFuture) { expand(on: screen) }
            return
        }
        openAfter = nil
        let open = intent.sample(
            at: mouse,
            inZone: Self.openZone(compact).contains(mouse),
            atTopEdge: mouse.y >= screen.frame.maxY - 1,
            upward: upward,
            buttonsDown: NSEvent.pressedMouseButtons != 0,
            trigger: OpenTrigger.current,
            wait: Prefs.defaults.double(forKey: Prefs.hoverWait),
            now: now
        )
        if open { expand(on: screen) }
    }

    /// Where the pointer has to be to open the island: the notch itself
    /// (or the same spot in the menu bar), not the space below it, where
    /// tabs and toolbars are. One point taller so the top row counts.
    private static func openZone(_ compact: NSRect) -> NSRect {
        NSRect(x: compact.minX - 8, y: compact.minY, width: compact.width + 16, height: compact.height + 1)
    }

    private func openIfNotchClicked() {
        guard OpenTrigger.current == .click, state.expanded == false, opening == false,
              let screen = activeScreen, allows(screen),
              Self.openZone(NotchGeo.compact(on: screen)).contains(NSEvent.mouseLocation) else { return }
        expand(on: screen)
    }

    private func closeIfMouseOutside() {
        guard state.expanded else { return }
        if panel.frame.contains(NSEvent.mouseLocation) { return }
        collapse()
    }

    private func resigned() {
        guard state.expanded || opening else { return }
        if Date() < (ignoreResignUntil ?? .distantPast) { return }
        if overPanelOrNotch { return }
        collapse()
    }

    private var overPanelOrNotch: Bool {
        let mouse = NSEvent.mouseLocation
        guard let screen = screen ?? activeScreen else { return panel.frame.contains(mouse) }
        let notch = NotchGeo.compact(on: screen).insetBy(dx: -20, dy: -10)
        return panel.frame.insetBy(dx: -12, dy: -12).union(notch).contains(mouse)
    }

    // MARK: Open / close

    private func place() {
        guard let screen = screen ?? preferredScreen(forPointer: false) else { return }
        let compact = NotchGeo.compact(on: screen)
        state.notchHeight = compact.height
        state.notchWidth = compact.width
        panel.chrome.notchHeight = compact.height
        panel.chrome.notchWidth = compact.width
        let frame = NotchGeo.strip(on: screen)
        panel.setFrame(frame, display: true)
        panel.setFrameOrigin(NSPoint(x: frame.minX, y: screen.frame.maxY - frame.height))
    }

    private func expand(on target: NSScreen?) {
        if opening || state.expanded { return }
        screen = target ?? activeScreen
        opening = true
        openAfter = nil
        hideAfter = nil
        ignoreResignUntil = Date().addingTimeInterval(0.55)
        place()
        panel.chrome.expanded = true
        panel.orderFrontRegardless()
        place()
        bridge.setIndex(store.index())
        bridge.reveal()
        if pinned {
            panel.makeKey()
            bridge.focus()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                self.state.expanded = true
            }
            self.opening = false
        }
    }

    private func collapse() {
        hideAfter = nil
        opening = false
        pinned = false
        intent.disarm()
        bridge.flush()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.94)) {
            state.expanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
            guard let self, self.state.expanded == false else { return }
            self.panel.chrome.expanded = false
            self.showRestingBadge()
        }
    }

    // MARK: Due badge

    private func updateDue() {
        let due = Prefs.defaults.bool(forKey: Prefs.showDueBadge) ? store.dueCount : 0
        if state.due != due {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { state.due = due }
        }
        if state.expanded == false, opening == false { showRestingBadge() }
    }

    /// Closed island: invisible, unless there's something due — then the
    /// notch grows a little to show the count. Clicks pass through either way.
    private func showRestingBadge() {
        guard state.expanded == false, opening == false else { return }
        if state.due > 0 {
            screen = preferredScreen(forPointer: false)
            place()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func preferencesChanged() {
        bridge.setPrefs(fontSize: Prefs.defaults.double(forKey: Prefs.fontSize))
        allowedIDs = Displays.allowedIDs
        if state.expanded, let screen, allows(screen) == false { collapse() }
        updateDue()
    }

    // MARK: Screens

    /// Where the island goes: the display under the pointer if the island
    /// is on there, otherwise the notched one, the main one, or any that's on.
    private func preferredScreen(forPointer: Bool) -> NSScreen? {
        let allowed = NSScreen.screens.filter(allows)
        if forPointer, let under = activeScreen, allows(under) { return under }
        return allowed.first(where: NotchGeo.hasNotch)
            ?? allowed.first { Displays.displayID($0) == NSScreen.main.flatMap(Displays.displayID) }
            ?? allowed.first
    }

    private func allows(_ screen: NSScreen) -> Bool {
        Displays.displayID(screen).map(allowedIDs.contains) ?? false
    }

    /// The display under the pointer. Includes the top edge row (y == maxY),
    /// which `NSRect.contains` leaves out — exactly where the notch is hovered.
    private var activeScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first {
            mouse.x >= $0.frame.minX && mouse.x < $0.frame.maxX && mouse.y > $0.frame.minY && mouse.y <= $0.frame.maxY
        } ?? NSScreen.main
    }
}

final class NotchPanel: NSPanel {
    let chrome = NotchChrome()
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// A hover-opened island isn't key yet, and AppKit spends the first click
    /// on making it key unless the view under the pointer accepts first mouse.
    /// The tabs sit in a SwiftUI ScrollView (an NSScrollView inside) that
    /// doesn't, so becoming key here first lets that click land.
    override func sendEvent(_ event: NSEvent) {
        if isKeyWindow == false, chrome.expanded,
           [.leftMouseDown, .rightMouseDown].contains(event.type),
           chrome.hitTest(chrome.convert(event.locationInWindow, from: nil)) != nil {
            makeKey()
        }
        super.sendEvent(event)
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovable = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class NotchChrome: NSView {
    var expanded = false
    var notchHeight: CGFloat = 32
    var notchWidth: CGFloat = 184

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Closed (with or without the due badge): every click passes through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if expanded == false { return nil }
        let top = bounds.maxY - notchHeight
        if point.y > top {
            let pad = notchWidth / 2 + 6
            if point.x < bounds.midX - pad || point.x > bounds.midX + pad {
                return nil
            }
        }
        return super.hitTest(point)
    }
}
