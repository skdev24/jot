import Foundation
import KeyboardShortcuts

/// UserDefaults keys. Settings binds to these with @AppStorage; the rest of
/// the app reads them when it needs them.
enum Prefs {
    static let vaultPath = "vaultPath"
    static let fontSize = "fontSize"
    static let openOnHover = "openOnHover"
    static let hoverDelay = "hoverDelay"
    static let display = "display"
    static let showDueBadge = "showDueBadge"
    static let reminders = "reminders"
    static let reminderHour = "reminderHour"
    static let appIcon = "appIcon"

    static func register() {
        UserDefaults.standard.register(defaults: [
            fontSize: 15.0,
            openOnHover: true,
            hoverDelay: 0.08,
            display: DisplayMode.followMouse.rawValue,
            showDueBadge: true,
            reminders: true,
            reminderHour: 9,
            appIcon: AppIconStyle.note.rawValue,
        ])
    }

    static var defaults: UserDefaults { .standard }
}

/// Which display the island opens on.
enum DisplayMode: String, CaseIterable, Identifiable {
    case followMouse
    case builtIn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followMouse: "The display with the pointer"
        case .builtIn: "Only the built-in display"
        }
    }
}

extension KeyboardShortcuts.Name {
    static let toggleJot = Self("toggleJot", default: .init(.space, modifiers: [.control, .option]))
    static let captureJot = Self("captureJot", default: .init(.n, modifiers: [.control, .option]))
}
