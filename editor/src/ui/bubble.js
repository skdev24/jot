import { NodeSelection } from '@tiptap/pm/state'
import { TURN_INTO } from '../blocks.js'
import { icon } from './icons.js'
import { createMenu } from './menu.js'
import { BLOCKS } from './slash.js'
import { createSurface, rangeReference } from './surface.js'

const MARKS = [
  { cmd: 'bold', icon: 'bold', title: 'Bold  ⌘B', run: (c) => c.toggleBold() },
  { cmd: 'italic', icon: 'italic', title: 'Italic  ⌘I', run: (c) => c.toggleItalic() },
  { cmd: 'underline', icon: 'underline', title: 'Underline  ⌘U', run: (c) => c.toggleUnderline() },
  { cmd: 'strike', icon: 'strike', title: 'Strikethrough  ⌘⇧S', run: (c) => c.toggleStrike() },
  { cmd: 'code', icon: 'code', title: 'Inline code  ⌘E', run: (c) => c.toggleCode() },
]

const TURNABLE = ['text', 'h1', 'h2', 'h3', 'todo', 'bullet', 'numbered', 'quote', 'code']

function blockKind(editor) {
  if (editor.isActive('heading', { level: 1 })) return 'h1'
  if (editor.isActive('heading', { level: 2 })) return 'h2'
  if (editor.isActive('heading', { level: 3 })) return 'h3'
  if (editor.isActive('taskList')) return 'todo'
  if (editor.isActive('bulletList')) return 'bullet'
  if (editor.isActive('orderedList')) return 'numbered'
  if (editor.isActive('blockquote')) return 'quote'
  if (editor.isActive('codeBlock')) return 'code'
  return 'text'
}

// The selection toolbar. It appears when a mouse selection ends (never
// while you're still dragging) or as soon as a keyboard selection exists.
export function createBubble(editor, { colors, links, isBusy }) {
  const view = editor.view
  const el = document.createElement('div')
  el.className = 'jot-bubble'
  el.innerHTML = `
    <button type="button" class="jot-bubble-turn" data-act="turn"><span></span>${icon('chevronDown')}</button>
    <span class="rule"></span>
    ${MARKS.map((mark) => `<button type="button" class="icon" data-cmd="${mark.cmd}" title="${mark.title}">${icon(mark.icon)}</button>`).join('')}
    <span class="rule"></span>
    <button type="button" class="icon jot-bubble-color" data-act="color" title="Color">${icon('palette')}</button>
    <button type="button" class="icon" data-act="link" title="Link  ⌘K">${icon('link')}</button>`
  document.body.appendChild(el)
  const surface = createSurface(el, { placement: 'top', gap: 8 })
  const turnLabel = el.querySelector('.jot-bubble-turn span')

  let pointerDown = false
  // Dismissed (Esc, note switch) for this exact selection; any new one shows.
  let dismissedAt = null

  // Turn-into dropdown, anchored under the toolbar's first button.
  const turnMenu = createMenu({
    className: 'is-turn',
    onChoose: (item) => {
      closeTurn()
      TURN_INTO[item.id]?.(editor.chain()).run()
      view.focus()
    },
  })
  document.body.appendChild(turnMenu.root)
  const turnSurface = createSurface(turnMenu.root, { placement: 'bottom-start', gap: 4, maxHeight: 320 })
  const closeTurn = () => turnSurface.hide()

  function valid() {
    const { selection } = view.state
    if (editor.isEditable === false || selection.empty || selection instanceof NodeSelection) return false
    if (editor.isActive('codeBlock') || view.hasFocus() === false || isBusy()) return false
    return view.state.doc.textBetween(selection.from, selection.to, ' ').trim() !== ''
  }

  function paint() {
    turnLabel.textContent = BLOCKS.find((item) => item.id === blockKind(editor))?.title.replace(' list', '') || 'Text'
    el.querySelectorAll('[data-cmd]').forEach((button) => button.classList.toggle('is-active', editor.isActive(button.dataset.cmd)))
    const color = editor.getAttributes('textColor').color || editor.getAttributes('highlight').color
    el.querySelector('.jot-bubble-color').dataset.swatch = color || ''
  }

  function update() {
    if (pointerDown) return
    if (dismissedAt && view.state.selection.eq(dismissedAt)) return
    dismissedAt = null
    if (valid() === false) {
      if (surface.isOpen) hide()
      return
    }
    paint()
    const { from, to } = view.state.selection
    surface.show(rangeReference(view, from, to))
  }

  function hide() {
    surface.hide()
    closeTurn()
    colors.close()
  }

  view.dom.addEventListener('mousedown', () => {
    pointerDown = true
    dismissedAt = null
    if (surface.isOpen) hide()
  })
  window.addEventListener('mouseup', () => {
    if (pointerDown === false) return
    pointerDown = false
    setTimeout(update, 0)
  })
  view.dom.addEventListener('dragstart', hide)

  el.addEventListener('mousedown', (event) => {
    event.preventDefault()
    const button = event.target.closest('button')
    if (button == null) return
    const mark = MARKS.find((item) => item.cmd === button.dataset.cmd)
    if (mark) {
      mark.run(editor.chain()).run()
      paint()
      return
    }
    const act = button.dataset.act
    if (act === 'link') {
      hide()
      links.open()
    } else if (act === 'turn') {
      if (turnSurface.isOpen) return closeTurn()
      colors.close()
      turnMenu.render(BLOCKS.filter((item) => TURNABLE.includes(item.id)).map((item) => ({ ...item, section: 'Turn into', checked: item.id === blockKind(editor), hint: undefined })))
      turnSurface.show(button)
    } else if (act === 'color') {
      closeTurn()
      if (colors.isOpen) return colors.close()
      colors.open(button, { text: editor.getAttributes('textColor').color || null, background: editor.getAttributes('highlight').color || null }, ({ text, background }) => {
        if (text !== undefined) (text ? editor.chain().setTextColor(text) : editor.chain().unsetTextColor()).run()
        if (background !== undefined) (background ? editor.chain().setHighlight({ color: background }) : editor.chain().unsetHighlight()).run()
        paint()
      })
    }
  })

  return {
    update,
    hide() {
      dismissedAt = view.state.selection
      hide()
    },
    menuKeyDown(event) {
      if (turnSurface.isOpen === false) return false
      if (event.key === 'Escape') {
        closeTurn()
        return true
      }
      return turnMenu.onKeyDown(event)
    },
    contains: (node) => el.contains(node) || turnMenu.root.contains(node),
    get isOpen() {
      return surface.isOpen
    },
  }
}
