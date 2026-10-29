import Foundation

/// How the pointer opens the island. The shortcut works whatever this is,
/// and something dragged onto the notch always opens it.
enum OpenTrigger: String, CaseIterable, Identifiable {
    /// The pointer comes to rest on the notch (or pushes up into it).
    case rest
    /// The pointer pushes up into the notch, like revealing the Dock.
    case push
    case click
    /// Only the shortcut.
    case off

    var id: String { rawValue }

    static var current: OpenTrigger {
        OpenTrigger(rawValue: Prefs.defaults.string(forKey: Prefs.openTrigger) ?? "") ?? .rest
    }
}

/// Tells reaching for the notch apart from passing over it.
///
/// Passing over: the pointer keeps moving, so it never rests. Reaching for
/// it: the pointer stops there, or keeps pushing up against the top edge
/// after it can't go any further. Once the island closes, nothing reopens it
/// until the pointer has left the notch.
struct HoverIntent {
    /// How far the pointer can wander and still count as resting.
    var restRadius: CGFloat = 6
    /// Upward travel pressed into the top edge that counts as a push.
    var pushDistance: CGFloat = 50
    /// A pause this long between nudges starts the push over.
    var pushGap: TimeInterval = 0.35

    private var anchor: CGPoint?
    private var restingSince: Date?
    private var pushed: CGFloat = 0
    private var lastPush: Date?
    private var wasAtEdge = false
    private(set) var armed = true

    /// One pointer sample. `upward` is how far the hardware moved the pointer
    /// up since the last sample, which keeps counting at the top edge where
    /// the position itself stops. Returns true when the island should open.
    mutating func sample(
        at point: CGPoint,
        inZone: Bool,
        atTopEdge: Bool,
        upward: CGFloat,
        buttonsDown: Bool,
        trigger: OpenTrigger,
        wait: TimeInterval,
        now: Date
    ) -> Bool {
        guard inZone else {
            leave()
            return false
        }
        // A button held down is a window drag or a selection, not a reach.
        guard armed, buttonsDown == false else {
            leave(rearm: armed)
            return false
        }

        // Moving resets resting, not pushing: the pointer often drifts
        // sideways while it's pressed up against the edge.
        if anchor.map({ hypot(point.x - $0.x, point.y - $0.y) > restRadius }) ?? true {
            anchor = point
            restingSince = now
        }

        // Only count pushing that happens once the pointer is already
        // pinned to the edge, so a fast move that ends there doesn't.
        if atTopEdge, wasAtEdge, upward > 0 {
            if let lastPush, now.timeIntervalSince(lastPush) > pushGap { pushed = 0 }
            pushed += upward
            lastPush = now
        }
        wasAtEdge = atTopEdge

        let pushedIn = pushed >= pushDistance
        let rested = now.timeIntervalSince(restingSince ?? now) >= wait
        switch trigger {
        case .rest: return rested || pushedIn
        case .push: return pushedIn
        case .click, .off: return false
        }
    }

    /// Start over. Off the notch, that also re-arms.
    mutating func leave(rearm: Bool = true) {
        anchor = nil
        restingSince = nil
        pushed = 0
        lastPush = nil
        wasAtEdge = false
        armed = rearm
    }

    /// The island just closed. Wait for the pointer to leave before opening again.
    mutating func disarm() {
        leave(rearm: false)
    }
}
