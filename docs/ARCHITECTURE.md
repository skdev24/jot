# How Jot fits together

Jot is a small AppKit/SwiftUI app hosting a TipTap (ProseMirror) editor in a `WKWebView`. Swift owns windows, files and the system; JavaScript owns the document while it's being edited.

```
 ┌───────────────── Swift ─────────────────┐        ┌──────────── editor/ (JS) ────────────┐
 │ AppDelegate        shortcuts, Services,   │        │ main.js      notes cache, bridge     │
 │                    notifications, Settings│        │ extensions/  schema + Markdown syntax│
 │ NotchController    island open/close,     │ bridge │ ui/          menus, toolbar, palette,│
 │                    displays, tabs, drops  │◀──────▶│              grip, dates, links      │
 │ EditorBridge       WKWebView, messages,   │        │ markdown.js  escaping, normalising   │
 │                    jot-asset:// images    │        │ blocks.js    block commands          │
 │ NoteStore          .md files, index,      │        └──────────────────────────────────────┘
 │                    watcher, backups       │
 │ Notifier           dated to-dos → alerts  │
 └──────────────────────────────────────────┘
```

## Swift (`Jot/`)

| File | Job |
| --- | --- |
| `App/JotApp.swift` | App delegate: starts the store, wires shortcuts (`KeyboardShortcuts`), the Services menu, notifications, Settings. |
| `App/Prefs.swift` | UserDefaults keys and defaults; shortcut names. |
| `App/Notifier.swift` | Rebuilds pending `UNNotificationRequest`s from scanned reminders. |
| `App/Updater.swift` | Sparkle, only when the build has a real `SUPublicEDKey`. |
| `Island/NotchController.swift` | The island: hover/drag detection, which display, expand/collapse, the due badge, routing notes between the store and the editor. |
| `Island/NotchView.swift` | SwiftUI island shape and the due badge on the closed notch. |
| `Island/TabBar.swift` | Tabs: sliding selection, drag to reorder, rename in place, due dots. |
| `Editor/EditorBridge.swift` | The web view, the JS bridge, the `jot-asset://` scheme, Finder drops and screenshot paste. |
| `Settings/SettingsView.swift` | The Settings window: a sidebar of panes built from cards. |
| `Vault/NoteStore.swift` | The vault: reading/writing `<title>.md`, the `.jot/index.json` index, renames, trash, assets, external-change watching, backups. |
| `Vault/Reminders.swift` | Finds open to-dos with `📅 date [time]`. |
| `Vault/Migration.swift` | Finds Jot 1.x HTML notes and archives the old files. |
| `Vault/FolderWatcher.swift` | FSEvents wrapper. |

## The editor (`editor/src/`)

`npm run build` bundles it into `Jot/Editor/Web/` (`index.html`, `editor.js`, `editor.css`), which ships inside the app. Styles live in `src/styles/editor.css`.

- **`extensions/index.js`** is the schema. It is shared by the app and the tests, so it never imports UI. Each custom node or mark owns its Markdown syntax through TipTap's `markdownTokenizer` / `parseMarkdown` / `renderMarkdown` hooks: `callout.js`, `details.js`, `date.js`, `wikilink.js`, `image.js`, `marks.js` (colors, highlight, underline), `paragraph.js` (escapes text that would read back as syntax).
- **`markdown.js`** tunes `@tiptap/markdown` for hand-read files (minimal escaping) and normalises shapes Markdown can't express, so every save is byte-stable.
- **`ui/`** is plain DOM, no framework. Everything that floats goes through `surface.js` (floating-ui placement + enter/exit animation); every list goes through `menu.js`; every trigger character (`/`, `@`, `[[`, `#`) goes through `suggest.js`.
- **`main.js`** keeps a `Map` of note id → `EditorState`, so each tab keeps its own undo history, caret and scroll for the life of the app.

## The bridge

Swift calls `JotEditor.*` with `callAsyncJavaScript` (typed arguments, no string building). JS posts messages to `window.webkit.messageHandlers.jot`.

| Swift → JS | |
| --- | --- |
| `open(id, markdown, title, meta, direction)` | Show a note. Markdown is only parsed the first time; afterwards the cached state is used. |
| `reload(id, markdown, meta)` | The file changed on disk. Taken unless there are unsaved edits. |
| `append(id, markdown)` → `Bool` | Services / drops. `false` means "not loaded here, write the file yourself". |
| `capture()` · `focus()` · `flush()` · `forget(id)` | |
| `setIndex(notes)` | Titles + Markdown of all notes, for ⌘P, `[[`, `#`. |
| `find(query)` · `openPalette(query)` · `reveal()` · `setPrefs(prefs)` | |
| `insertFiles(x, y, items)` · `insertImage(path)` | Finder drops and native screenshot paste. |
| `pastePlain(text)` | ⌘⇧V. The web view has no menu bar to route it, so Swift catches the key. |
| `resolve(requestId, value)` | Answers a JS request. |
| `convert(html)` → `String` | 1.x migration. |

| JS → Swift | |
| --- | --- |
| `ready` | Page loaded (also after a WebContent crash). |
| `save {noteId, markdown, meta}` | Debounced 400 ms, plus on blur, tab switch and close. Always names its note. |
| `switchTab {index \| delta}` | ⌘1…9, ⌃Tab. |
| `navigate {noteId \| title, query}` · `createNote {title}` · `rename {noteId, title}` | |
| `saveImage {requestId, data, ext}` · `pickImage {requestId}` | Answered via `resolve`. |
| `copy {text}` · `openURL {url}` · `escape` · `settings` | |

## Storage rules

- A note is `<vault>/<title>.md`. The title is the file name. `index.json` holds only what Markdown can't: stable ids, tab order, folded headings.
- Writes are atomic (`AtomicFile`). The store remembers what it last wrote per note, so FSEvents for its own writes are ignored and only real outside edits reach the editor.
- Notes deleted in Jot go to the Trash. Notes deleted in Finder disappear from the tabs. New `.md` files appear.
- Backups: every 30 minutes, if anything changed, `.md` files are copied to `.jot/backups/<time>/`; the newest 30 are kept.

## Things that are easy to get wrong

- **Focus in WebKit.** Never use TipTap's `focus()` command. On WebKit it focuses the DOM before syncing the selection, and the caret jumps to the top. Use `focusView()` from `blocks.js`.
- **View props run before plugins.** `editorProps.handleKeyDown` sees keys before any extension. Escape checks for an active suggestion before closing the island.
- **The island is a non-activating panel.** `EditorWebView.mouseDown` makes it key on the first click; the controller keeps it open while it's key.
- **Byte-stable saves.** If you add syntax, add it to `test/markdown.test.js` `CANONICAL`. Read-then-write must not change the file.
