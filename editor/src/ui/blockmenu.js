import { NodeSelection, TextSelection } from '@tiptap/pm/state'
import { deleteBlock, duplicateBlock, moveBlock, turnInto } from '../blocks.js'
import { CALLOUTS } from '../extensions/callout.js'
import { createMenu } from './menu.js'
import { BLOCKS } from './slash.js'
import { createSurface } from './surface.js'

const TURNABLE = ['text', 'h1', 'h2', 'h3', 'todo', 'bullet', 'numbered', 'toggle', 'quote', 'callout', 'code']

// The menu behind the ⋮⋮ grip: act on one block.
export function createBlockMenu(editor, { handle, colors, copyMarkdown }) {
  const view = editor.view
  let target = null
  let anchor = null
  // The color picker is shared with the selection toolbar; only count it as
  // ours while we opened it.
  let ownsColors = false
  const colorsOpen = () => ownsColors && colors.isOpen

  const select = (pos) => {
    view.dispatch(view.state.tr.setSelection(NodeSelection.create(view.state.doc, pos)))
    return true
  }

  // Color a whole block: text color / highlight over its text, or the
  // callout's own color.
  function colorBlock({ text, background }) {
    const node = view.state.doc.nodeAt(target.pos)
    if (node == null) return
    if (background !== undefined && node.type.name === 'callout') {
      const kind = CALLOUTS.find((callout) => callout.color === background)?.kind || 'note'
      view.dispatch(view.state.tr.setNodeMarkup(target.pos, undefined, { ...node.attrs, kind }))
      return
    }
    const from = target.pos + 1
    const to = target.pos + node.nodeSize - 1
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, from, to)))
    const chain = editor.chain()
    if (text !== undefined) (text ? chain.setTextColor(text) : chain.unsetTextColor()).run()
    if (background !== undefined) (background ? chain.setHighlight({ color: background }) : chain.unsetHighlight()).run()
    select(target.pos)
  }

  const menu = createMenu({
    className: 'is-block',
    onChoose: (item) => {
      if (item.id === 'color') {
        const node = view.state.doc.nodeAt(target.pos)
        const background = node?.type.name === 'callout' ? CALLOUTS.find((c) => c.kind === node.attrs.kind)?.color : null
        surface.hide({ instant: true })
        ownsColors = true
        colors.open(anchor, { background }, colorBlock)
        return
      }
      close()
      item.run()
      view.focus()
    },
  })
  document.body.appendChild(menu.root)
  const surface = createSurface(menu.root, { placement: 'bottom-start', gap: 4, maxHeight: 340, onHidden: () => colorsOpen() || handle.unlock() })

  function open(next, button) {
    ownsColors = false
    target = next
    anchor = button
    handle.lock()
    const pos = next.pos
    menu.render([
      { section: 'Block', id: 'dup', title: 'Duplicate', icon: 'duplicate', hint: '⌘D', run: () => duplicateBlock(editor, pos) },
      { section: 'Block', id: 'up', title: 'Move up', icon: 'up', hint: '⌘⇧↑', run: () => select(pos) && moveBlock(editor, -1) },
      { section: 'Block', id: 'down', title: 'Move down', icon: 'down', hint: '⌘⇧↓', run: () => select(pos) && moveBlock(editor, 1) },
      { section: 'Block', id: 'copy', title: 'Copy as Markdown', icon: 'copy', run: () => copyMarkdown(pos) },
      { section: 'Block', id: 'color', title: 'Color', icon: 'palette' },
      { section: 'Block', id: 'delete', title: 'Delete', icon: 'trash', hint: '⌫', danger: true, run: () => deleteBlock(editor, pos) },
      ...BLOCKS.filter((item) => TURNABLE.includes(item.id)).map((item) => ({
        section: 'Turn into',
        id: item.id,
        title: item.title,
        icon: item.icon,
        run: () => turnInto(editor, item.id, pos),
      })),
    ])
    surface.show(button)
  }

  function close() {
    const was = surface.hide()
    if (colorsOpen()) {
      colors.close()
      ownsColors = false
      handle.unlock()
      return true
    }
    ownsColors = false
    return was
  }

  return {
    open,
    close,
    onKeyDown: (event) => surface.isOpen && menu.onKeyDown(event),
    contains: (node) => menu.root.contains(node) || colors.contains(node),
    get isOpen() {
      return surface.isOpen || colorsOpen()
    },
  }
}
