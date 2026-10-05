import { getMarkRange } from '@tiptap/core'
import { TextSelection } from '@tiptap/pm/state'
import { focusView } from '../blocks.js'
import { holdSelection } from '../extensions/held.js'
import { icon } from './icons.js'
import { createSurface, rangeReference } from './surface.js'

const SAFE = /^(https?|mailto|tel|ftp|file|obsidian|x-apple[\w.-]*):/i

export function normalizeURL(raw) {
  const value = raw.trim()
  if (value === '') return ''
  if (/^[a-z][a-z0-9+.-]*:/i.test(value)) return value
  if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) return `mailto:${value}`
  return `https://${value}`
}

// Only open schemes that can't run code in the page.
export function safeURL(raw) {
  const url = normalizeURL(raw || '')
  return SAFE.test(url) ? url : null
}

export function createLinks(editor, { openURL }) {
  const view = editor.view

  // ⌘K / toolbar: edit the link on the selection.
  const form = document.createElement('form')
  form.className = 'jot-pop jot-linkedit'
  form.innerHTML = `
    <span class="jot-pop-icon">${icon('link')}</span>
    <input type="text" spellcheck="false" autocomplete="off" placeholder="Paste or type a link" />
    <button type="submit" class="is-primary">Done</button>`
  document.body.appendChild(form)
  const input = form.querySelector('input')
  const editSurface = createSurface(form, { placement: 'bottom-start', gap: 6 })
  let range = null

  // Hovering a link: where it goes, and what you can do with it.
  const preview = document.createElement('div')
  preview.className = 'jot-pop jot-linkpreview'
  preview.innerHTML = `
    <a class="jot-linkpreview-url" href="#"></a>
    <button type="button" class="icon" data-act="open" title="Open  ⌘-click">${icon('external')}</button>
    <button type="button" class="icon" data-act="edit" title="Edit">${icon('edit')}</button>
    <button type="button" class="icon" data-act="unlink" title="Remove link">${icon('unlink')}</button>`
  document.body.appendChild(preview)
  const urlLabel = preview.querySelector('.jot-linkpreview-url')
  const previewSurface = createSurface(preview, { placement: 'bottom-start', gap: 4 })
  let hovered = null
  let showTimer = null
  let hideTimer = null

  function openEditor() {
    hidePreview()
    const { state } = view
    let { from, to } = state.selection
    const markRange = getMarkRange(state.doc.resolve(from), state.schema.marks.link)
    if (markRange && from === to) ({ from, to } = markRange)
    range = { from, to }
    view.dispatch(state.tr.setSelection(TextSelection.create(state.doc, from, to)))
    holdSelection(view)
    input.value = editor.getAttributes('link').href || ''
    editSurface.show(rangeReference(view, from, to)).then(() => {
      input.focus()
      input.select()
    })
    return true
  }

  function closeEditor(refocus = true) {
    if (editSurface.hide() === false) return false
    holdSelection(view, false)
    range = null
    if (refocus) view.focus()
    return true
  }

  function apply() {
    if (range == null) return closeEditor()
    const href = normalizeURL(input.value)
    const { from, to } = range
    closeEditor(false)
    focusView(editor, TextSelection.create(editor.state.doc, from, to))
    const chain = editor.chain()
    if (href === '') chain.extendMarkRange('link').unsetLink().run()
    else if (from === to) {
      chain.insertContent({ type: 'text', text: input.value.trim(), marks: [{ type: 'link', attrs: { href } }] }).unsetMark('link').run()
    } else chain.extendMarkRange('link').setLink({ href }).setTextSelection(to).run()
  }

  form.addEventListener('submit', (event) => {
    event.preventDefault()
    apply()
  })
  input.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      event.preventDefault()
      event.stopPropagation()
      closeEditor()
    }
  })
  input.addEventListener('blur', () => setTimeout(() => form.contains(document.activeElement) || closeEditor(false), 0))

  function showPreview(anchor) {
    hovered = anchor
    const href = anchor.getAttribute('href') || ''
    urlLabel.textContent = href.replace(/^mailto:/, '').replace(/^https?:\/\/(www\.)?/, '').replace(/\/$/, '')
    urlLabel.title = href
    previewSurface.show(anchor)
  }

  function hidePreview() {
    clearTimeout(showTimer)
    previewSurface.hide()
    hovered = null
  }

  view.dom.addEventListener('mouseover', (event) => {
    const anchor = event.target.closest('a[href]')
    clearTimeout(hideTimer)
    if (anchor == null || editSurface.isOpen || anchor === hovered) return
    clearTimeout(showTimer)
    showTimer = setTimeout(() => showPreview(anchor), 420)
  })
  const scheduleHide = () => {
    clearTimeout(showTimer)
    clearTimeout(hideTimer)
    hideTimer = setTimeout(hidePreview, 240)
  }
  view.dom.addEventListener('mouseout', (event) => {
    if (event.target.closest('a[href]')) scheduleHide()
  })
  preview.addEventListener('mouseenter', () => clearTimeout(hideTimer))
  preview.addEventListener('mouseleave', scheduleHide)
  preview.addEventListener('mousedown', (event) => event.preventDefault())
  preview.addEventListener('click', (event) => {
    event.preventDefault()
    const anchor = hovered
    if (anchor == null) return
    const act = event.target.closest('[data-act]')?.dataset.act || 'open'
    if (act === 'open') {
      const url = safeURL(anchor.getAttribute('href'))
      if (url) openURL(url)
      hidePreview()
      return
    }
    focusView(editor, TextSelection.create(editor.state.doc, view.posAtDOM(anchor, 0)))
    hidePreview()
    if (act === 'edit') openEditor()
    if (act === 'unlink') editor.chain().extendMarkRange('link').unsetLink().run()
  })

  // ⌘-click follows a link; a plain click just places the caret.
  view.dom.addEventListener('click', (event) => {
    const anchor = event.target.closest('a[href]:not([data-wiki])')
    if (anchor == null || event.metaKey === false) return
    event.preventDefault()
    const url = safeURL(anchor.getAttribute('href'))
    if (url) openURL(url)
  })

  return {
    open: openEditor,
    close: closeEditor,
    hidePreview,
    get isOpen() {
      return editSurface.isOpen
    },
  }
}
