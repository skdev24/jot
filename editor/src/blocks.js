import { Fragment, Slice } from '@tiptap/pm/model'
import { NodeSelection, TextSelection } from '@tiptap/pm/state'
import { glideFrom, settle } from './ui/motion.js'

const ITEM_TYPES = ['listItem', 'taskItem']

// The "block" a command acts on: a list item when inside a list, otherwise
// the top-level node. Matches what the hover handle targets.
export function blockAt(state, from = state.selection.from) {
  const { selection } = state
  if (selection instanceof NodeSelection && from === selection.from) {
    return { pos: selection.from, node: selection.node }
  }
  const $pos = state.doc.resolve(from)
  for (let depth = $pos.depth; depth > 0; depth -= 1) {
    const node = $pos.node(depth)
    if (ITEM_TYPES.includes(node.type.name)) return { pos: $pos.before(depth), node }
  }
  if ($pos.depth === 0) {
    const node = state.doc.nodeAt(from)
    return node ? { pos: from, node } : null
  }
  return { pos: $pos.before(1), node: $pos.node(1) }
}

function restoreSelection(tr, oldSelection, oldStart, newStart) {
  const shift = newStart - oldStart
  if (oldSelection instanceof NodeSelection) {
    tr.setSelection(NodeSelection.create(tr.doc, oldSelection.from + shift))
  } else {
    tr.setSelection(TextSelection.create(tr.doc, oldSelection.anchor + shift, oldSelection.head + shift))
  }
}

export function moveBlock(editor, direction) {
  const { state, view } = editor
  const block = blockAt(state)
  if (block == null) return false
  const $pos = state.doc.resolve(block.pos)
  const parent = $pos.parent
  const index = $pos.index()
  const tr = state.tr
  const top = (pos) => view.nodeDOM(pos)?.getBoundingClientRect?.().top
  let moved
  let swapped
  if (direction < 0) {
    if (index === 0) return true
    const prev = parent.child(index - 1)
    const start = block.pos - prev.nodeSize
    moved = { from: top(block.pos), to: start }
    swapped = { from: top(start), to: start + block.node.nodeSize }
    tr.replaceWith(start, block.pos + block.node.nodeSize, [block.node, prev])
    restoreSelection(tr, state.selection, block.pos, start)
  } else {
    if (index >= parent.childCount - 1) return true
    const next = parent.child(index + 1)
    const end = block.pos + block.node.nodeSize + next.nodeSize
    moved = { from: top(block.pos), to: block.pos + next.nodeSize }
    swapped = { from: top(block.pos + block.node.nodeSize), to: block.pos }
    tr.replaceWith(block.pos, end, [next, block.node])
    restoreSelection(tr, state.selection, block.pos, block.pos + next.nodeSize)
  }
  view.dispatch(tr.scrollIntoView())
  // Both blocks glide to their new places instead of jumping.
  glideFrom(view.nodeDOM(moved.to), moved.from)
  glideFrom(view.nodeDOM(swapped.to), swapped.from)
  return true
}

export function duplicateBlock(editor, pos) {
  const { state, view } = editor
  const block = blockAt(state, pos ?? state.selection.from)
  if (block == null) return false
  const after = block.pos + block.node.nodeSize
  const tr = state.tr.insert(after, block.node)
  tr.setSelection(TextSelection.near(tr.doc.resolve(after + 1)))
  view.dispatch(tr.scrollIntoView())
  settle(view.nodeDOM(after))
  return true
}

export function deleteBlock(editor, pos) {
  const { state, view } = editor
  const block = blockAt(state, pos ?? state.selection.from)
  if (block == null) return false
  const tr = state.tr.delete(block.pos, block.pos + block.node.nodeSize)
  const near = Math.min(block.pos, tr.doc.content.size)
  tr.setSelection(TextSelection.near(tr.doc.resolve(near), -1))
  view.dispatch(tr.scrollIntoView())
  return true
}

// Focus without TipTap's focus command: on WebKit it focuses the DOM before
// syncing the selection, so the caret jumps to the top of the note.
// ProseMirror's own view.focus() writes the selection first.
export function focusView(editor, selection = editor.state.selection) {
  const { view } = editor
  if (selection.eq(view.state.selection) === false) view.dispatch(view.state.tr.setSelection(selection))
  view.focus()
}

// Put a text cursor inside the block at `pos` so chain commands apply to it.
export function focusBlock(editor, pos) {
  const { state, view } = editor
  const node = state.doc.nodeAt(pos)
  if (node == null) return
  const inside = Math.min(pos + 1, state.doc.content.size)
  const selection = node.isAtom ? NodeSelection.create(state.doc, pos) : TextSelection.near(state.doc.resolve(inside))
  view.dispatch(state.tr.setSelection(selection))
  view.focus()
}

export const TURN_INTO = {
  text: (chain) => chain.clearNodes().setParagraph(),
  h1: (chain) => chain.clearNodes().setHeading({ level: 1 }),
  h2: (chain) => chain.clearNodes().setHeading({ level: 2 }),
  h3: (chain) => chain.clearNodes().setHeading({ level: 3 }),
  todo: (chain) => chain.clearNodes().toggleTaskList(),
  bullet: (chain) => chain.clearNodes().toggleBulletList(),
  numbered: (chain) => chain.clearNodes().toggleOrderedList(),
  quote: (chain) => chain.clearNodes().toggleBlockquote(),
  code: (chain) => chain.clearNodes().setCodeBlock(),
  toggle: (chain) => chain.clearNodes().setDetails(),
  callout: (chain) => chain.clearNodes().setCallout('note'),
}

export function turnInto(editor, kind, pos) {
  if (typeof pos === 'number') focusBlock(editor, pos)
  const run = TURN_INTO[kind]
  if (run == null) return false
  return run(editor.chain()).run()
}

// ⌘↵: tick the todo under the caret, or turn the block into one.
export function toggleTodo(editor) {
  const { state, view } = editor
  const $from = state.selection.$from
  for (let depth = $from.depth; depth > 0; depth -= 1) {
    const node = $from.node(depth)
    if (node.type.name === 'taskItem') {
      const pos = $from.before(depth)
      view.dispatch(state.tr.setNodeMarkup(pos, undefined, { ...node.attrs, checked: !node.attrs.checked }))
      return true
    }
  }
  return editor.chain().toggleTaskList().run()
}

// Backspace at the very start of a list item turns it into plain text
// (Notion behaviour) instead of merging it into the previous item.
export function liftAtStart(editor) {
  const { selection } = editor.state
  if (selection.empty === false) return false
  const { $from } = selection
  if ($from.parentOffset !== 0) return false
  for (const type of ITEM_TYPES) {
    if (editor.isActive(type)) {
      const depth = $from.depth - 1
      if (depth < 1 || $from.node(depth).type.name !== type) return false
      if ($from.index(depth) !== 0) return false
      return editor.commands.liftListItem(type)
    }
  }
  const inCallout = $from.depth > 1 && $from.node($from.depth - 1).type.name === 'callout'
  if (inCallout && $from.index($from.depth - 1) === 0) {
    return editor.commands.unsetCallout()
  }
  if (editor.isActive('heading') || editor.isActive('blockquote') || editor.isActive('codeBlock')) {
    if (editor.isActive('codeBlock') && $from.parent.textContent !== '') return false
    return editor.chain().clearNodes().setParagraph().run()
  }
  return false
}

// Paste and Match Style (⌘⇧V): the text exactly as copied — no paste rules,
// so **x** and URLs stay literal — styled like the text at the caret.
// Lines become paragraphs.
export function insertPlainText(editor, text) {
  const { state, view } = editor
  const lines = text.replace(/\r\n?/g, '\n').split('\n')
  const marks = state.storedMarks || state.selection.$from.marks()
  let tr
  if (lines.length === 1 || state.selection.$from.parent.type.name === 'codeBlock') {
    tr = state.tr.insertText(text)
  } else {
    const { paragraph } = state.schema.nodes
    const blocks = lines.map((line) => paragraph.create(null, line ? state.schema.text(line, marks) : null))
    tr = state.tr.replaceSelection(new Slice(Fragment.from(blocks), 1, 1))
  }
  view.dispatch(tr.scrollIntoView())
  return true
}
