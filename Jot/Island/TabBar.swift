import SwiftUI

/// The tabs under the editor.
///
/// - The whole pill is the target, not just the text.
/// - One highlight slides between tabs instead of jumping.
/// - Drag a tab to reorder: it follows the pointer and the others make room.
/// - Double-click renames in place; right-click for the rest.
struct TabBar: View {
    var notes: [NoteRecord]
    var activeID: UUID
    var due: Set<UUID>
    var actions: NotchActions

    @Namespace private var highlight
    @State private var order: [UUID] = []
    @State private var frames: [UUID: CGRect] = [:]
    @State private var dragging: UUID?
    @State private var translation: CGFloat = 0
    /// How far the dragged tab's slot has moved while dragging, so it stays
    /// under the pointer as neighbours swap past it.
    @State private var slotShift: CGFloat = 0
    /// Where the dragged tab's centre started; frames lag a layout pass
    /// behind swaps, so the pointer is measured from here instead.
    @State private var startMidX: CGFloat = 0
    @State private var hovered: UUID?
    @State private var renaming: UUID?
    @State private var draft = ""
    @FocusState private var renameFocused: Bool

    private let spacing: CGFloat = 2
    private let spring = Animation.spring(response: 0.3, dampingFraction: 0.82)

    private var ordered: [NoteRecord] {
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let live = order.compactMap { byID[$0] }
        return live.count == notes.count ? live : notes
    }

    var body: some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        ForEach(ordered) { note in
                            tab(note)
                                .id(note.id)
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 2)
                    .coordinateSpace(name: "tabs")
                    .onPreferenceChange(TabFrames.self) { frames = $0 }
                }
                .mask(edgeFade)
                .onChange(of: activeID) { _, id in
                    withAnimation(spring) { proxy.scrollTo(id, anchor: .center) }
                }
            }

            BarButton(symbol: "plus", help: "New note  ⌘N", action: actions.create)
        }
        .padding(.leading, 4)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
        .onAppear { order = notes.map(\.id) }
        .onChange(of: notes.map(\.id)) { _, ids in
            guard dragging == nil else { return }
            withAnimation(spring) { order = ids }
        }
        .animation(spring, value: activeID)
    }

    // MARK: One tab

    @ViewBuilder
    private func tab(_ note: NoteRecord) -> some View {
        let selected = note.id == activeID
        let isDragging = dragging == note.id
        let isHovered = hovered == note.id && dragging == nil

        HStack(spacing: 5) {
            if renaming == note.id {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: max(60, min(140, CGFloat(draft.count) * 7.2 + 12)))
                    .focused($renameFocused)
                    .onSubmit { finishRename(note.id, commit: true) }
                    .onExitCommand { finishRename(note.id, commit: false) }
                    .onChange(of: renameFocused) { _, focused in
                        if focused == false, renaming == note.id { finishRename(note.id, commit: true) }
                    }
            } else {
                Text(note.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(selected ? 1 : (isHovered ? 0.75 : 0.45)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 140, alignment: .leading)
            }
            if due.contains(note.id) {
                Circle()
                    .fill(Color(red: 1, green: 0.62, blue: 0.4))
                    .frame(width: 5, height: 5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background {
            if selected {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .matchedGeometryEffect(id: "selected", in: highlight)
            } else if isHovered {
                Capsule(style: .continuous).fill(Color.white.opacity(0.06))
            }
        }
        .contentShape(Capsule(style: .continuous))
        .scaleEffect(isDragging ? 1.06 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.45 : 0), radius: 8, y: 2)
        .offset(x: isDragging ? translation - slotShift : 0)
        .zIndex(isDragging ? 1 : 0)
        // The dragged tab's slot changes under it while the offset makes up
        // the difference; animating the slot would make it lurch.
        .transaction { if isDragging { $0.animation = nil } }
        .background(GeometryReader { geo in
            Color.clear.preference(key: TabFrames.self, value: [note.id: geo.frame(in: .named("tabs"))])
        })
        .onHover { inside in
            if inside { hovered = note.id } else if hovered == note.id { hovered = nil }
        }
        .onTapGesture { if renaming != note.id { actions.select(note.id) } }
        .simultaneousGesture(TapGesture(count: 2).onEnded { startRename(note) })
        .gesture(reorder(note), including: renaming == note.id ? .subviews : .all)
        .help(note.title)
        .contextMenu { menu(note) }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func menu(_ note: NoteRecord) -> some View {
        Button("Rename") { startRename(note) }
        if let index = order.firstIndex(of: note.id) {
            Button("Move Left") { actions.move(note.id, index - 1) }.disabled(index == 0)
            Button("Move Right") { actions.move(note.id, index + 1) }.disabled(index == order.count - 1)
        }
        if note.isDump == false {
            Divider()
            Button("Move to Trash", role: .destructive) { actions.delete(note.id) }
        }
    }

    // MARK: Reordering

    private func reorder(_ note: NoteRecord) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("tabs"))
            .onChanged { value in
                if dragging == nil {
                    dragging = note.id
                    slotShift = 0
                    startMidX = frames[note.id]?.midX ?? 0
                    if order.count != notes.count { order = notes.map(\.id) }
                }
                translation = value.translation.width
                swapIfNeeded(note.id)
            }
            .onEnded { _ in
                let finalIndex = order.firstIndex(of: note.id)
                withAnimation(spring) {
                    dragging = nil
                    translation = 0
                    slotShift = 0
                }
                if let finalIndex, finalIndex != notes.firstIndex(where: { $0.id == note.id }) {
                    actions.move(note.id, finalIndex)
                }
            }
    }

    /// Swap with a neighbour once the dragged tab's centre passes theirs.
    private func swapIfNeeded(_ id: UUID) {
        guard let index = order.firstIndex(of: id) else { return }
        let center = startMidX + translation
        if index + 1 < order.count, let next = frames[order[index + 1]], center > next.midX {
            withAnimation(spring) { order.swapAt(index, index + 1) }
            slotShift += next.width + spacing
        } else if index > 0, let prev = frames[order[index - 1]], center < prev.midX {
            withAnimation(spring) { order.swapAt(index, index - 1) }
            slotShift -= prev.width + spacing
        }
    }

    // MARK: Renaming

    private func startRename(_ note: NoteRecord) {
        draft = note.title
        renaming = note.id
        DispatchQueue.main.async { renameFocused = true }
    }

    private func finishRename(_ id: UUID, commit: Bool) {
        guard renaming == id else { return }
        renaming = nil
        renameFocused = false
        if commit { actions.rename(id, draft) }
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03), .init(color: .black, location: 0.97), .init(color: .clear, location: 1)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// The round + at the end of the bar.
private struct BarButton: View {
    var symbol: String
    var help: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.55))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .onHover { hovering = $0 }
        .help(help)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct TabFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
