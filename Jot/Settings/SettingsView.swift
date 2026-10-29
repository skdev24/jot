import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Settings: a sidebar of panes, each a stack of cards. Laid out for a window
/// with a transparent title bar (the traffic lights sit over the sidebar).
struct SettingsView: View {
    @State private var pane: SettingsPane

    init(pane: SettingsPane = .general) {
        _pane = State(initialValue: pane)
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $pane)
                .frame(width: 200)
            Divider().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PaneHeader(pane: pane)
                    switch pane {
                    case .general: GeneralPane()
                    case .shortcuts: ShortcutsPane()
                    case .notes: NotesPane()
                    case .reminders: RemindersPane()
                    case .about: AboutPane()
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 34)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 720, height: 540)
        .ignoresSafeArea()
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, shortcuts, notes, reminders, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .notes: "Notes"
        case .reminders: "Reminders"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "How the island opens, how text looks, and the app icon."
        case .shortcuts: "Keys that work everywhere, and the ones inside Jot."
        case .notes: "Where your Markdown files live."
        case .reminders: "Notifications for to-dos with a date."
        case .about: ""
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .shortcuts: "command"
        case .notes: "folder.fill"
        case .reminders: "bell.badge.fill"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .general: Color(white: 0.55)
        case .shortcuts: .indigo
        case .notes: .blue
        case .reminders: .orange
        case .about: Color(white: 0.3)
        }
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane
    @AppStorage(Prefs.appIcon) private var appIcon = AppIconStyle.note.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(nsImage: (AppIconStyle(rawValue: appIcon) ?? .note).image)
                    .resizable()
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Jot").font(.system(size: 15, weight: .semibold))
                    Text("Version \(AppInfo.version)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 50)
            .padding(.bottom, 16)

            ForEach(SettingsPane.allCases) { pane in
                SidebarRow(pane: pane, selected: pane == selection)
                    .onTapGesture { selection = pane }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VisualEffect(material: .sidebar).ignoresSafeArea())
    }
}

private struct SidebarRow: View {
    var pane: SettingsPane
    var selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: pane.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(pane.tint.gradient))
            Text(pane.title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.primary.opacity(0.09) : (hovering ? Color.primary.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct PaneHeader: View {
    var pane: SettingsPane

    var body: some View {
        if pane != .about {
            VStack(alignment: .leading, spacing: 4) {
                Text(pane.title).font(.system(size: 22, weight: .bold))
                Text(pane.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Building blocks

/// A rounded group of rows with hairline separators. Unboxed for content
/// that brings its own tiles (like the display and icon choices), so they
/// aren't boxes inside a box.
private struct Card<Content: View>: View {
    var title: String?
    var footer: String?
    var boxed = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            if boxed {
                VStack(spacing: 0) { content }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
            } else {
                content
            }
            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct Row<Control: View>: View {
    var title: String
    var detail: String?
    var divider = true
    @ViewBuilder var control: Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13))
                    if let detail {
                        Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                control
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            if divider {
                Divider().padding(.leading, 14)
            }
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

enum AppInfo {
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    /// The project page, once the repo has a real home.
    static var homepage: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "JotHomepage") as? String, raw.contains("OWNER") == false else { return nil }
        return URL(string: raw)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @AppStorage(Prefs.openOnHover) private var openOnHover = true
    @AppStorage(Prefs.hoverDelay) private var hoverDelay = 0.08
    @AppStorage(Prefs.display) private var display = DisplayMode.followMouse.rawValue
    @AppStorage(Prefs.fontSize) private var fontSize = 15.0
    @AppStorage(Prefs.appIcon) private var appIcon = AppIconStyle.note.rawValue
    @State private var iconFailed = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Card(title: "Opening") {
            Row(title: "Open when the pointer touches the notch", detail: "Otherwise, open it with the shortcut.") {
                Toggle("", isOn: $openOnHover).toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            Row(title: "Hover delay", divider: false) {
                Picker("", selection: $hoverDelay) {
                    Text("Instant").tag(0.08)
                    Text("Short").tag(0.25)
                    Text("Long").tag(0.6)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                .disabled(openOnHover == false)
            }
        }

        Card(title: "Display", footer: "With more than one display, choose where the island appears.", boxed: false) {
            HStack(spacing: 12) {
                ForEach(DisplayMode.allCases) { mode in
                    DisplayChoice(mode: mode, selected: display == mode.rawValue)
                        .onTapGesture { display = mode.rawValue }
                }
            }
        }

        Card(title: "Text") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("A").font(.system(size: 11))
                    Slider(value: $fontSize, in: 13...19, step: 1)
                    Text("A").font(.system(size: 17))
                    Text("\(Int(fontSize)) pt")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                TextPreview(size: fontSize)
            }
            .padding(14)
        }

        Card(title: "App icon", footer: iconFailed
            ? "Jot can't change its own icon here. Move Jot.app to a folder you can write to, like Applications, and try again."
            : "Shown in Finder, the Dock and Launchpad.", boxed: false) {
            HStack(spacing: 12) {
                ForEach(AppIconStyle.allCases) { style in
                    IconChoice(style: style, selected: appIcon == style.rawValue)
                        .onTapGesture {
                            guard appIcon != style.rawValue else { return }
                            appIcon = style.rawValue
                            iconFailed = style.apply() == false
                        }
                }
            }
        }

        Card {
            Row(title: "Open at login", divider: false) {
                Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).labelsHidden().controlSize(.small)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
    }
}

/// A tiny drawing of where the island will appear.
private struct DisplayChoice: View {
    var mode: DisplayMode
    var selected: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                screen(notch: true, island: true)
                screen(notch: false, island: mode == .followMouse)
            }
            .frame(height: 64)
            VStack(spacing: 2) {
                Text(mode == .followMouse ? "Follow the pointer" : "Built-in display only")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(mode == .followMouse ? "Opens on whichever display you hover" : "Ignores external displays")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private func screen(notch: Bool, island: Bool) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.6, blue: 0.95), Color(red: 0.85, green: 0.5, blue: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if island {
                UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5)
                    .fill(.black)
                    .frame(width: 40, height: 24)
            } else if notch {
                UnevenRoundedRectangle(bottomLeadingRadius: 2, bottomTrailingRadius: 2)
                    .fill(.black)
                    .frame(width: 14, height: 4)
            }
        }
        .frame(width: notch ? 76 : 90, height: notch ? 50 : 60)
        .opacity(island ? 1 : 0.55)
    }
}

/// One app icon style, picked like a display mode.
private struct IconChoice: View {
    var style: AppIconStyle
    var selected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: style.image)
                .resizable()
                .frame(width: 76, height: 76)
                .scaleEffect(hovering && selected == false ? 1.04 : 1)
            Text(style.title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// What notes will look like at this size, on the island's black.
private struct TextPreview: View {
    var size: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3.5).strokeBorder(.white.opacity(0.4), lineWidth: 1.5).frame(width: 14, height: 14)
                Text("Send the deck to Sam").font(.system(size: size)).foregroundStyle(.white.opacity(0.92))
                Text("Friday 3:00 PM")
                    .font(.system(size: size * 0.86, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.08)))
            }
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3.5).fill(.white.opacity(0.9)).frame(width: 14, height: 14)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.black))
                Text("Book flights to Lisbon").font(.system(size: size)).strikethrough().foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black))
        .animation(.easeOut(duration: 0.15), value: size)
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    var body: some View {
        Card(title: "Everywhere", footer: "Click a shortcut, then press the keys you want.") {
            Row(title: "Show or hide Jot") { KeyboardShortcuts.Recorder(for: .toggleJot) }
            Row(title: "Quick capture to Dump", detail: "Opens Dump with the caret on a fresh line.", divider: false) {
                KeyboardShortcuts.Recorder(for: .captureJot)
            }
        }
        Card(title: "Inside Jot") {
            let keys: [(String, String)] = [
                ("Search all notes", "⌘P"),
                ("New note", "⌘N"),
                ("Go to tab 1–9 · next tab", "⌘1…9 · ⌃⇥"),
                ("Tick a to-do", "⌘↵"),
                ("Move block up / down", "⌘⇧↑ / ⌘⇧↓"),
                ("Duplicate block", "⌘D"),
                ("Link", "⌘K"),
                ("Paste as plain text", "⌘⇧V"),
                ("Find in note", "⌘F"),
                ("Copy note as Markdown", "⌘⇧C"),
            ]
            ForEach(Array(keys.enumerated()), id: \.offset) { index, item in
                Row(title: item.0, divider: index < keys.count - 1) {
                    Text(item.1)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
                }
            }
        }
        Card(title: "While typing") {
            Row(title: "/", detail: "Blocks: to-do, heading, toggle, callout, code, image…") { EmptyView() }
            Row(title: "@", detail: "A date or reminder: today, fri 3pm, in 2 weeks") { EmptyView() }
            Row(title: "[[", detail: "Link another note") { EmptyView() }
            Row(title: "#", detail: "Tag, shared across notes", divider: false) { EmptyView() }
        }
    }
}

// MARK: - Notes

private struct NotesPane: View {
    @Environment(NoteStore.self) private var store
    @State private var backedUp = false

    var body: some View {
        Card(footer: "Each tab is a Markdown file in this folder, so Obsidian, git and iCloud Drive work on it as-is. Images go in assets/.") {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: store.vaultURL.path))
                    .resizable()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.vaultURL.lastPathComponent).font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(store.vaultURL.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Show in Finder") { store.revealVault() }
                Button("Change…", action: chooseFolder)
            }
            .padding(14)
        }

        Card(title: "Safety net", footer: "Every 30 minutes, if anything changed, Jot copies your notes to .jot/backups and keeps the last 30 copies. Notes you delete go to the Trash.") {
            Row(title: "Back up now", detail: store.notes.count == 1 ? "1 note" : "\(store.notes.count) notes", divider: false) {
                Button(backedUp ? "Done" : "Back Up") {
                    try? store.backup(force: true)
                    withAnimation { backedUp = true }
                }
                .disabled(backedUp)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose the folder for your notes. Existing .md files become tabs."
        panel.directoryURL = store.vaultURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        NotificationCenter.default.post(name: .jotVaultChange, object: url)
    }
}

// MARK: - Reminders

private struct RemindersPane: View {
    @AppStorage(Prefs.reminders) private var reminders = true
    @AppStorage(Prefs.reminderHour) private var hour = 9
    @AppStorage(Prefs.showDueBadge) private var showDueBadge = true

    var body: some View {
        Card(footer: "Type @ in a to-do, like “@fri 3pm”. It's saved as 📅 2026-10-09 15:00 — the Obsidian Tasks format.") {
            Row(title: "Notify me about dated to-dos") {
                Toggle("", isOn: $reminders).toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            Row(title: "To-dos without a time", detail: "When to notify for a date like “@tomorrow”.", divider: false) {
                Picker("", selection: $hour) {
                    ForEach([7, 8, 9, 10, 12, 14, 17, 20], id: \.self) { Text(Self.label($0)).tag($0) }
                }
                .labelsHidden()
                .frame(width: 110)
                .disabled(reminders == false)
            }
        }

        Card(title: "On the notch") {
            HStack(spacing: 18) {
                BadgePreview(visible: showDueBadge)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Show what's due beside the notch", isOn: $showDueBadge)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Text("Counts to-dos due today or overdue, while the island is closed.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
    }

    private static func label(_ hour: Int) -> String {
        var parts = DateComponents()
        parts.hour = hour
        return (Calendar.current.date(from: parts) ?? Date()).formatted(date: .omitted, time: .shortened)
    }
}

private struct BadgePreview: View {
    var visible: Bool
    private let orange = Color(red: 1, green: 0.62, blue: 0.4)

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.6, blue: 0.95), Color(red: 0.85, green: 0.5, blue: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
            HStack(spacing: 0) {
                Image(systemName: "calendar").font(.system(size: 8, weight: .bold)).foregroundStyle(orange).frame(width: visible ? 18 : 0)
                Color.clear.frame(width: 30)
                Text("2").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(orange).frame(width: visible ? 18 : 0)
            }
            .frame(height: 14)
            .clipped()
            .background(UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6).fill(.black))
        }
        .frame(width: 120, height: 60)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: visible)
    }
}

// MARK: - About

private struct AboutPane: View {
    @State private var autoUpdate = Updater.shared.automaticallyChecks
    @AppStorage(Prefs.appIcon) private var appIcon = AppIconStyle.note.rawValue

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: (AppIconStyle(rawValue: appIcon) ?? .note).image)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Jot").font(.system(size: 26, weight: .bold))
            Text("Notes that live in the notch.").font(.system(size: 13)).foregroundStyle(.secondary)
            Text("Version \(AppInfo.version)").font(.system(size: 11.5)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)

        if Updater.shared.isAvailable {
            Card {
                Row(title: "Check for updates automatically") {
                    Toggle("", isOn: $autoUpdate).toggleStyle(.switch).labelsHidden().controlSize(.small)
                        .onChange(of: autoUpdate) { _, on in Updater.shared.automaticallyChecks = on }
                }
                Row(title: "Check now", divider: false) {
                    Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                }
            }
        }

        Card(footer: "Free and open source under the MIT license. Built with TipTap, ProseMirror, lowlight, chrono, Floating UI, Sparkle and KeyboardShortcuts.") {
            if let home = AppInfo.homepage {
                Row(title: "Source code and issues") {
                    Button("Open on GitHub") { NSWorkspace.shared.open(home) }
                }
            }
            Row(title: "Privacy", detail: "No account, no analytics. Notes never leave your folder.", divider: false) {
                EmptyView()
            }
        }
    }
}

extension Notification.Name {
    static let jotVaultChange = Notification.Name("jotVaultChange")
}
