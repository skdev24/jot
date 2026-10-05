# Contributing to Jot

Thanks for helping. Jot is small on purpose: a fast notch editor whose notes are plain Markdown. Changes that keep it fast, keep files portable and keep the UI quiet are the easiest to merge.

## Setup

- macOS 15+, Xcode 26+.
- Node 20+ if you touch the editor.

```bash
git clone https://github.com/skdev24/jot.git
cd jot
open Jot.xcodeproj          # run the "Jot" scheme
```

If you already run a release build, quit it first (`killall Jot`): two copies both claim the notch and the shortcuts. To keep your real notes out of a dev session, point the debug build at another folder for that run only:

```bash
build/derived/Build/Products/Debug/Jot.app/Contents/MacOS/Jot -vaultPath ~/Desktop/jot-dev
```

## Where things are

```
Jot/                  the macOS app (Swift, SwiftUI)
  App/                launch, preferences, notifications, updates
  Island/             the notch island, its tabs, the due badge
  Editor/             the bridge to the web editor; Web/ is its built bundle
  Settings/           the Settings window
  Vault/              notes on disk: Markdown files, index, watching, backups
JotTests/             Swift tests (and the README demo capture)
editor/               the editor's source: TipTap, styles, tests
  src/extensions/     document schema + Markdown syntax
  src/ui/             menus, toolbar, palette, drag handle
  src/styles/         editor.css
docs/                 architecture, releasing, README images
packaging/homebrew/   cask template for the tap
build/                everything generated (ignored)
```

Build the Xcode project into `build/derived` so it stays out of the way:

```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -derivedDataPath build/derived build
```

The app icon is `Jot/AppIcon.icon`, an Icon Composer document (wallpaper, notch and note layers). Open it in Icon Composer, which ships with Xcode. macOS 26 renders it as Liquid Glass, and Xcode flattens it for macOS 15. The other styles you can pick in Settings (Check, Scribble) are macOS renders of their own `.icon` documents, in `Jot/Assets.xcassets/AppIcon*.imageset`. Jot sets the chosen one as a custom icon on Jot.app.

## The editor

```bash
cd editor
npm ci
npm test          # Markdown round-trips and editor behaviour (node --test + happy-dom)
npm run dev       # rebuild Jot/Editor/Web/ on save
npm run build     # minified bundle; commit it
```

The built editor in `Jot/Editor/Web/` is committed so the app builds without Node. Don't edit it by hand; CI fails if it doesn't match `editor/`.

Right-click inside the island → **Inspect Element** opens Web Inspector on the live editor (debug builds).

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before larger changes. It covers the bridge protocol and a few WebKit traps.

## Tests

| | |
| --- | --- |
| `cd editor && npm test` | Markdown format and editor commands |
| `xcodebuild test -project Jot.xcodeproj -scheme Jot CODE_SIGN_IDENTITY=-` | Note store, migration, reminder scanning |

New Markdown syntax needs a byte-for-byte round-trip case in `editor/test/markdown.test.js`. A file that changes when Jot merely opens it is a bug.

## The README demo

`docs/assets/demo.gif` and `docs/assets/screenshot.jpg` come from the real app, not a mockup. `JotTests/DemoCapture.swift` drives the shipped editor in a WKWebView (it types a dated to-do, then searches with ⌘P) and snapshots each step, plus the SwiftUI tab bar. It's skipped unless `JOT_DEMO_OUT` is set; maintainers turn the snapshots into the GIF when the UI changes.

## Style

- Swift: match the surrounding code. Small types, comments that explain *why*.
- JS: plain ES modules, no framework. Floating UI goes through `ui/surface.js`, lists through `ui/menu.js`.
- No new runtime dependencies without a reason in the PR. Everything shipped must be MIT-compatible. Tiptap Pro packages and the paid Tiptap templates can't be used.
- Motion: short (≤ 300 ms), from the thing that caused it, and off under Reduce Motion.

## Pull requests

- One change per PR, with a sentence on why.
- UI changes: a screenshot or short clip.
- Run both test suites and `npm run build` before pushing.
