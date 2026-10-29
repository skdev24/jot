import AppKit

/// Connected displays, and which of them the island is allowed on.
///
/// Displays are remembered by their UUID, which survives unplugging and
/// restarts; the numeric display ID doesn't.
enum Displays {
    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func key(_ screen: NSScreen) -> String? {
        guard let id = displayID(screen),
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func isBuiltIn(_ screen: NSScreen) -> Bool {
        displayID(screen).map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }

    static var switchedOff: Set<String> {
        Set(Prefs.defaults.stringArray(forKey: Prefs.disabledDisplays) ?? [])
    }

    /// The displays the island may use. Never empty while a display is
    /// attached: if every one is switched off, they all count as on.
    static var allowed: [NSScreen] {
        let off = switchedOff
        let on = NSScreen.screens.filter { key($0).map { off.contains($0) == false } ?? true }
        return on.isEmpty ? NSScreen.screens : on
    }

    static var allowedIDs: Set<CGDirectDisplayID> {
        Set(allowed.compactMap(displayID))
    }

    static func set(_ key: String, on: Bool) {
        var off = switchedOff
        if on { off.remove(key) } else { off.insert(key) }
        Prefs.defaults.set(off.sorted(), forKey: Prefs.disabledDisplays)
    }

    /// Jot 2.0's "Built-in display only" becomes each external display
    /// switched off.
    static func migrate() {
        let legacy = "display"
        guard let mode = Prefs.defaults.string(forKey: legacy) else { return }
        if mode == "builtIn", NSScreen.screens.contains(where: isBuiltIn) {
            for screen in NSScreen.screens where isBuiltIn(screen) == false {
                if let key = key(screen) { set(key, on: false) }
            }
        }
        Prefs.defaults.removeObject(forKey: legacy)
    }
}
