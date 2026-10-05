import AppKit

/// Jot's icon styles. Note is compiled into the app (Jot/AppIcon.icon); the
/// others are set as a custom icon on Jot.app, which is what Finder, the Dock
/// and Launchpad show. The images are macOS's own renders of each style.
enum AppIconStyle: String, CaseIterable, Identifiable {
    case note, check, scribble

    var id: String { rawValue }

    var title: String {
        switch self {
        case .note: "Note"
        case .check: "Check"
        case .scribble: "Scribble"
        }
    }

    var image: NSImage {
        NSImage(named: "AppIcon\(rawValue.capitalized)") ?? NSApp.applicationIconImage
    }

    static var current: AppIconStyle {
        AppIconStyle(rawValue: Prefs.defaults.string(forKey: Prefs.appIcon) ?? "") ?? .note
    }

    /// Puts this style on Jot.app. False when the app can't be written to,
    /// e.g. an admin-owned copy in /Applications.
    @discardableResult
    func apply() -> Bool {
        let path = Bundle.main.bundlePath
        let custom = self == .note ? nil : image
        let ok = NSWorkspace.shared.setIcon(custom, forFile: path, options: [])
        NSApp.applicationIconImage = custom
        NSWorkspace.shared.noteFileSystemChanged(path)
        return ok
    }

    /// An update replaces the app and drops a custom icon; put it back.
    static func restore() {
        let style = current
        guard style != .note else { return }
        let marker = (Bundle.main.bundlePath as NSString).appendingPathComponent("Icon\r")
        if FileManager.default.fileExists(atPath: marker) == false { style.apply() }
    }
}
