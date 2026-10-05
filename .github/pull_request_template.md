### What and why

<!-- One or two sentences. Link the issue if there is one. -->

### How it looks

<!-- UI changes: a screenshot or short clip. -->

### Checklist

- [ ] `cd editor && npm test && npm run build` (and the rebuilt `Jot/Editor/Web/` is committed)
- [ ] `xcodebuild test -project Jot.xcodeproj -scheme Jot CODE_SIGN_IDENTITY=-`
- [ ] New Markdown syntax has a round-trip case in `editor/test/markdown.test.js`
- [ ] Motion is short and respects Reduce Motion
