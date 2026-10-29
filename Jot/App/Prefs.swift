import Foundation
import KeyboardShortcuts

/// UserDefaults keys. Settings binds to these with @AppStorage; the rest of
/// the app reads them when it needs them.
enum Prefs {
    static let vaultPath = "vaultPath"
    static let fontSize = "fontSize"
    /// An `OpenTrigger`.
    static let openTrigger = "openTrigger"
    /// Seconds the pointer rests on the notch before it opens.
    static let hoverWait = "hoverWait"
    /// UUIDs of displays the island stays off.
    static let disabledDisplays = "disabledDisplays"
    static let showDueBadge = "showDueBadge"
    static let reminders = "reminders"
    static let reminderHour = "reminderHour"
    static let appIcon = "appIcon"

    static func register() {
        migrate()
        UserDefaults.standard.register(defaults: [
            fontSize: 15.0,
            openTrigger: OpenTrigger.rest.rawValue,
            hoverWait: 0.5,
            showDueBadge: true,
            reminders: true,
            reminderHour: 9,
            appIcon: AppIconStyle.note.rawValue,
        ])
    }

    static var defaults: UserDefaults { .standard }

    /// Jot 2.0 had an on/off switch and an instant-to-long delay for hover.
    /// Hover switched off carries over; the old delays don't map onto
    /// resting, so they start from the new default.
    private static func migrate() {
        let d = UserDefaults.standard
        if d.object(forKey: "openOnHover") != nil, d.object(forKey: openTrigger) == nil, d.bool(forKey: "openOnHover") == false {
            d.set(OpenTrigger.off.rawValue, forKey: openTrigger)
        }
        d.removeObject(forKey: "openOnHover")
        d.removeObject(forKey: "hoverDelay")
    }
}

extension KeyboardShortcuts.Name {
    static let toggleJot = Self("toggleJot", default: .init(.space, modifiers: [.control, .option]))
    static let captureJot = Self("captureJot", default: .init(.n, modifiers: [.control, .option]))
}
