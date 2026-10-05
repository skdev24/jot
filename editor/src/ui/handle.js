import { NodeSelection } from '@tiptap/pm/state'
import { icon } from './icons.js'

const ITEM_TYPES = ['listItem', 'taskItem']
const SIZE = 22
// Gutter width the grip sits in, left of the text column.
const GUTTER = 21

// The hover grip: drag to move a block, click for the block menu.
// Lives inside the scroller so it scrolls with the text.
export function createHandle(editor, scroller, { onMenu }) {
  const view = editor.view
  const el = document.createElement('div')
  el.className = 'jot-handle'
  el.innerHTML = `
    <button type="button" class="jot-handle-grip" tabindex="-1" draggable="true" aria-label="Drag or open menu">${icon('grip')}</button>`
  scroller.appendChild(el)
  const grip = el.querySelector('.jot-handle-grip')

  let current = null
  let locked = false
  let dragging = false

  function targetAt(clientX, clientY) {
    const content = view.dom.getBoundingClientRect()
    const x = Math.min(Math.max(clientX, content.left + 4), content.right - 4)
    const hit = view.posAtCoords({ left: x, top: clientY })
    if (hit == null) return null
    const doc = view.state.doc
    const probe = hit.inside >= 0 ? hit.inside : hit.pos
    const $pos = doc.resolve(Math.min(probe, doc.content.size))
    let depthNode = null
    for (let depth = $pos.depth; depth > 0; depth -= 1) {
      if (ITEM_TYPES.includes($pos.node(depth).type.name)) {
        depthNode = { pos: $pos.before(depth), node: $pos.node(depth) }
        break
      }
    }
    if (depthNode == null) {
      if ($pos.depth >= 1) depthNode = { pos: $pos.before(1), node: $pos.node(1) }
      else {
        const node = doc.nodeAt(probe)
        if (node == null) return null
        depthNode = { pos: probe, node }
      }
    }
    const dom = view.nodeDOM(depthNode.pos)
    if (!(dom instanceof HTMLElement)) return null
    return { ...depthNode, dom }
  }

  function place(target) {
    const box = scroller.getBoundingClientRect()
    const line = target.dom.matches('li') ? target.dom.querySelector(':scope > div > p, :scope > p') || target.dom : target.dom
    const rect = line.getBoundingClientRect()
    const style = getComputedStyle(line)
    const lineHeight = parseFloat(style.lineHeight) || rect.height
    const padTop = parseFloat(style.paddingTop) || 0
    let top = rect.top + padTop + Math.min(lineHeight, rect.height) / 2 - SIZE / 2
    if (target.node.type.name === 'horizontalRule') top = rect.top + rect.height / 2 - SIZE / 2
    // Top-level blocks share one gutter; nested list items follow their indent.
    const nested = ITEM_TYPES.includes(target.node.type.name) && view.state.doc.resolve(target.pos).depth > 1
    const marker = target.node.type.name === 'taskItem' ? 0 : 20
    const anchor = nested ? target.dom.getBoundingClientRect().left - marker : view.dom.getBoundingClientRect().left
    const left = anchor - GUTTER - box.left + scroller.scrollLeft
    el.style.transform = `translate(${Math.round(left)}px, ${Math.round(top - box.top + scroller.scrollTop)}px)`
  }

  function show(target) {
    const appearing = el.classList.contains('is-visible') === false
    current = target
    // Glide between blocks, but appear in place (no slide in from the last spot).
    if (appearing) el.classList.add('is-instant')
    place(target)
    el.classList.add('is-visible')
    if (appearing) requestAnimationFrame(() => el.classList.remove('is-instant'))
  }

  // Attribute changes re-render a block's DOM; follow it instead of vanishing.
  function reacquire() {
    if (current == null) return
    const node = view.state.doc.nodeAt(current.pos)
    const dom = node ? view.nodeDOM(current.pos) : null
    if (node == null || !(dom instanceof HTMLElement) || node.type !== current.node.type) {
      locked = false
      hide()
      return
    }
    current = { pos: current.pos, node, dom }
    place(current)
  }

  function hide() {
    if (locked || dragging) return
    current = null
    el.classList.remove('is-visible')
  }

  scroller.addEventListener('mousemove', (event) => {
    if (locked || dragging || editor.isEditable === false) return
    if (event.buttons !== 0 && el.contains(event.target) === false) return
    if (el.contains(event.target)) return
    // Out of the way while text is selected (the toolbar owns that moment).
    const { selection } = view.state
    if (selection.empty === false && (selection instanceof NodeSelection) === false) {
      hide()
      return
    }
    const target = targetAt(event.clientX, event.clientY)
    if (target) show(target)
    else hide()
  })
  scroller.addEventListener('mouseleave', hide)
  view.dom.addEventListener('keydown', () => hide())
  scroller.addEventListener('scroll', () => {
    if (current && current.dom.isConnected) place(current)
  })

  grip.addEventListener('mousedown', (event) => {
    if (current == null) return
    const sel = NodeSelection.create(view.state.doc, current.pos)
    view.dispatch(view.state.tr.setSelection(sel))
    view.focus()
    event.stopPropagation()
  })
  grip.addEventListener('click', () => {
    if (current == null) return
    onMenu(current, grip)
  })

  grip.addEventListener('dragstart', (event) => {
    if (current == null) return
    dragging = true
    const sel = NodeSelection.create(view.state.doc, current.pos)
    view.dispatch(view.state.tr.setSelection(sel))
    const slice = sel.content()
    const { dom, text } = view.serializeForClipboard(slice)
    event.dataTransfer.clearData()
    event.dataTransfer.setData('text/html', dom.innerHTML)
    event.dataTransfer.setData('text/plain', text)
    event.dataTransfer.effectAllowed = 'copyMove'
    const rect = current.dom.getBoundingClientRect()
    event.dataTransfer.setDragImage(current.dom, Math.min(event.clientX - rect.left, 40), event.clientY - rect.top)
    view.dragging = { slice, move: true, node: sel }
    el.classList.add('is-dragging')
  })
  grip.addEventListener('dragend', () => {
    dragging = false
    el.classList.remove('is-dragging')
    hide()
  })

  return {
    lock() {
      locked = true
      el.classList.add('is-locked')
    },
    unlock() {
      locked = false
      el.classList.remove('is-locked')
    },
    hide() {
      locked = false
      el.classList.remove('is-locked')
      hide()
    },
    refresh: reacquire,
  }
}
