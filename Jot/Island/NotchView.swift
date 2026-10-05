import AppKit
import SwiftUI

/// What the tab bar can ask for. The controller does the work, so the
/// editor and the vault stay in step.
struct NotchActions {
    var select: (UUID) -> Void
    var create: () -> Void
    var rename: (UUID, String) -> Void
    var delete: (UUID) -> Void
    var move: (UUID, Int) -> Void
    var settings: () -> Void
}

struct NotchView: View {
    @Environment(NoteStore.self) private var store
    var state: NotchState
    var bridge: EditorBridge
    var actions: NotchActions

    /// Notes with something due today or earlier get a dot on their tab.
    private var dueByNote: Set<UUID> {
        let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        return Set(store.reminders.filter { $0.date < endOfToday }.map(\.noteID))
    }

    /// Closed with something due: the notch grows an ear on each side.
    private var badgeWidth: CGFloat { state.due > 0 ? 34 : 0 }

    var body: some View {
        GeometryReader { geo in
            let islandW = state.expanded ? geo.size.width : state.notchWidth + badgeWidth * 2
            let islandH = state.expanded ? geo.size.height : state.notchHeight
            let shape = IslandShape(
                topRadius: state.expanded ? 16 : 6,
                bottomRadius: state.expanded ? 22 : 14
            )
            ZStack(alignment: .top) {
                ZStack(alignment: .top) {
                    shape
                        .fill(Color.black)
                        .frame(width: islandW, height: islandH)

                    EditorHost(bridge: bridge)
                    .padding(.top, state.notchHeight + 6)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 56)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .allowsHitTesting(state.expanded)
                    .transaction { $0.animation = nil }
                    .overlay(alignment: .bottom) {
                        if state.expanded {
                            TabBar(
                                notes: store.notes,
                                activeID: store.activeNoteID,
                                due: dueByNote,
                                actions: actions
                            )
                            .padding(.horizontal, 22)
                            .padding(.bottom, 6)
                            .transition(.opacity.combined(with: .offset(y: 6)).animation(.easeOut(duration: 0.22).delay(0.06)))
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .mask(alignment: .top) {
                    shape.frame(width: islandW, height: islandH)
                }

                if state.expanded == false, state.due > 0 {
                    DueBadge(count: state.due, notchWidth: state.notchWidth, height: state.notchHeight, ear: badgeWidth)
                        .transition(.opacity)
                }

                if state.expanded {
                    shape
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        .frame(width: islandW, height: islandH)
                        .mask(alignment: .top) {
                            Rectangle()
                                .frame(width: islandW, height: max(islandH - state.notchHeight, 0))
                                .offset(y: state.notchHeight)
                        }
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .ignoresSafeArea()
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: state.expanded)
    }
}

/// "Something's due" beside the closed notch: a calendar mark on the left
/// ear, the count on the right.
struct DueBadge: View {
    var count: Int
    var notchWidth: CGFloat
    var height: CGFloat
    var ear: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.4))
                .frame(width: ear)
            Spacer().frame(width: notchWidth)
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.4))
                .frame(width: ear)
                .contentTransition(.numericText())
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) due")
    }
}

struct IslandShape: Shape {
    var topRadius: CGFloat = 16
    var bottomRadius: CGFloat = 22

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 2, rect.height / 2)
        let bottom = min(bottomRadius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
