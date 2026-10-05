import { test } from 'node:test'
import assert from 'node:assert/strict'
import { TextSelection } from '@tiptap/pm/state'
import { docToMarkdown, makeEditor } from './helpers.js'

const { moveBlock, duplicateBlock, toggleTodo, liftAtStart, turnInto } = await import('../src/blocks.js')

// Puts the caret inside the first textblock whose text starts with `text`.
function caretAt(editor, text, offset = 0) {
  let pos = null
  editor.state.doc.descendants((node, at) => {
    if (pos == null && node.isTextblock && node.textContent.startsWith(text)) pos = at + 1 + offset
  })
  editor.view.dispatch(editor.state.tr.setSelection(TextSelection.create(editor.state.doc, pos)))
}

const md = (editor) => docToMarkdown(editor)

test('⌘⇧↑/↓ moves a list item within its list', () => {
  const editor = makeEditor('- [ ] one\n- [ ] two\n- [ ] three\n')
  caretAt(editor, 'three')
  moveBlock(editor, -1)
  assert.equal(md(editor), '- [ ] one\n- [ ] three\n- [ ] two\n')
  moveBlock(editor, 1)
  assert.equal(md(editor), '- [ ] one\n- [ ] two\n- [ ] three\n')
})

test('moving keeps the caret in the moved block', () => {
  const editor = makeEditor('first\n\nsecond\n')
  caretAt(editor, 'second', 3)
  moveBlock(editor, -1)
  assert.equal(editor.state.selection.$from.parent.textContent, 'second')
  assert.equal(editor.state.selection.$from.parentOffset, 3)
})

test('⌘D duplicates the block', () => {
  const editor = makeEditor('## Plan\n')
  caretAt(editor, 'Plan')
  duplicateBlock(editor)
  assert.equal(md(editor), '## Plan\n\n## Plan\n')
})

test('⌘↵ ticks a to-do, or makes the line one', () => {
  const editor = makeEditor('- [ ] call Sam\n\nplain\n')
  caretAt(editor, 'call')
  toggleTodo(editor)
  assert.match(md(editor), /- \[x\] call Sam/)
  caretAt(editor, 'plain')
  toggleTodo(editor)
  assert.match(md(editor), /- \[ \] plain/)
})

test('Backspace at the start of a to-do turns it into text', () => {
  const editor = makeEditor('- [ ] one\n- [ ] two\n')
  caretAt(editor, 'one')
  assert.equal(liftAtStart(editor), true)
  assert.equal(md(editor), 'one\n\n- [ ] two\n')
})

test('Backspace at the start of a heading or callout unwraps it', () => {
  const editor = makeEditor('## Title\n\n> [!tip]\n> inside\n')
  caretAt(editor, 'Title')
  liftAtStart(editor)
  caretAt(editor, 'inside')
  liftAtStart(editor)
  assert.equal(md(editor), 'Title\n\ninside\n')
})

test('Turn into converts the block under the caret', () => {
  const editor = makeEditor('plain\n')
  caretAt(editor, 'plain')
  turnInto(editor, 'h2')
  assert.equal(md(editor), '## plain\n')
  turnInto(editor, 'todo')
  assert.equal(md(editor), '- [ ] plain\n')
  turnInto(editor, 'callout')
  assert.equal(md(editor), '> [!note]\n> plain\n')
})

test('Backspace on an empty line between two lists joins them', () => {
  const editor = makeEditor()
  editor.commands.setContent('<ul><li><p>a</p></li></ul><p></p><ul><li><p>b</p></li></ul>')
  let pos = null
  editor.state.doc.forEach((node, at) => {
    if (node.type.name === 'paragraph' && node.content.size === 0 && pos == null) pos = at + 1
  })
  editor.view.dispatch(editor.state.tr.setSelection(TextSelection.create(editor.state.doc, pos)))
  editor.commands.keyboardShortcut('Backspace')
  assert.equal(md(editor), '- a\n- b\n')
})

test('⌘⇧V pastes text literally, in the style at the caret', async () => {
  const { insertPlainText } = await import('../src/blocks.js')
  const editor = makeEditor('**bold here**\n')
  caretAt(editor, 'bold', 4)
  insertPlainText(editor, ' **not bold** https://x.com')
  // Takes the bold of where it lands; the asterisks and URL stay text.
  assert.equal(md(editor), '**bold \\*\\*not bold\\*\\* https://x.com here**\n')
})

test('⌘⇧V with several lines makes paragraphs', async () => {
  const { insertPlainText } = await import('../src/blocks.js')
  const editor = makeEditor('start end\n')
  caretAt(editor, 'start', 6)
  insertPlainText(editor, 'one\ntwo\n- three')
  assert.equal(md(editor), 'start one\n\ntwo\n\n\\- threeend\n')
})

test('@ suggests a date while the weekday is half typed', async () => {
  const { dateOptions } = await import('../src/ui/dates.js')
  for (const query of ['f', 'fr', 'fri', 'fri 3pm', 'tom', 'in 2 weeks']) {
    assert.ok(dateOptions(query).length > 0, `no options for "${query}"`)
  }
  assert.equal(dateOptions('fri 3pm')[0].attrs.time, '15:00')
})
