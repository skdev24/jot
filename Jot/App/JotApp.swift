import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = NoteStore()
    private var notch: NotchController!
    private let notifier = Notifier()
    private let services = ServiceProvider()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        NSApp.setActivationPolicy(.accessory)
        Prefs.register()
        Displays.migrate()
        AppIconStyle.restore()
        _ = Updater.shared
        try? store.start()

        notch = NotchController(store: store)
        notch.onOpenSettings = { [weak self] in self?.openSettings() }
        notch.onReminders = { [weak self] reminders in self?.notifier.sync(reminders) }
        notifier.onOpen = { [weak self] id, text in self?.notch.openNote(id, at: text) }
        notifier.sync(store.reminders)

        KeyboardShortcuts.onKeyDown(for: .toggleJot) { [weak self] in self?.notch.toggle() }
        KeyboardShortcuts.onKeyDown(for: .captureJot) { [weak self] in self?.notch.capture() }

        // "Send to Jot" in every app's Services menu.
        services.onText = { [weak self] text in self?.notch.sendToDump(text) }
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()

        NotificationCenter.default.addObserver(forName: .jotVaultChange, object: nil, queue: .main) { [weak self] note in
            guard let url = note.object as? URL else { return }
            Task { @MainActor in self?.notch.switchVault(to: url) }
        }

        if ProcessInfo.processInfo.arguments.contains("--open-notch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.notch.toggle() }
        }
    }

    func openSettings() {
        let window = settingsWindow ?? {
            let host = NSHostingController(rootView: SettingsView().environment(store))
            // The view runs under the transparent title bar. With the title
            // bar's safe area, the window grew by its height and left a blank
            // band along the bottom.
            host.safeAreaRegions = []
            let window = NSWindow(contentViewController: host)
            window.title = "Jot Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
            return window
        }()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// Services menu: selected text (or a link) goes to the end of Dump.
final class ServiceProvider: NSObject {
    var onText: (String) -> Void = { _ in }

    @objc func sendToJot(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        if let url = pasteboard.string(forType: .URL) ?? (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first?.absoluteString,
           pasteboard.string(forType: .string) == nil || pasteboard.string(forType: .string) == url {
            onText("<\(url)>")
            return
        }
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), text.isEmpty == false else {
            error.pointee = "Nothing to send to Jot." as NSString
            return
        }
        onText(text)
    }
}

@main
struct JotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.store)
        }
    }
}
