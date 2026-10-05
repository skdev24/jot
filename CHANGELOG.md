# Changelog

## 2.0

A new editor, and notes that are plain Markdown files.

**Notes**
- Every tab is now a `.md` file in your notes folder (Settings → Notes). Obsidian, git and iCloud Drive work on it as-is, and edits made elsewhere show up in Jot.
- Jot 1.x notes are converted on first launch; the old files move to `.jot/legacy/`.
- Images you paste or drop are saved in `assets/`. Rolling backups in `.jot/backups/`.

**Editor**
- Always editable, Notion-style: `/` menu, drag handle on every line, block menu (duplicate, move, color, turn into), selection toolbar with colors, Markdown shortcuts.
- To-dos, toggles, callouts, quotes, code with syntax highlighting, images with resizing, collapsible headings.
- `@` dates and reminders with notifications; the closed notch shows what's due.
- `[[` links between notes, `#tags`, and ⌘P search across every note.
- ⌘⇧V pastes as plain text. Each tab keeps its own undo history.

**App**
- Quick capture (⌃⌥N), Send to Jot from the Services menu, drag onto the notch.
- Opens on the display you hover, or only the built-in one.
- New tab bar: drag to reorder, rename in place, ⌘1…9.
- New Settings window. New Liquid Glass app icon, in three styles to choose from in Settings.
- Auto-updates on signed builds.

## 1.0

First release: a notch island with a Dump list and extra notes.
