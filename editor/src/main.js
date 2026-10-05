import './styles/editor.css'
import { Editor } from '@tiptap/core'
import { EditorState, NodeSelection, Selection, TextSelection } from '@tiptap/pm/state'
import Placeholder from '@tiptap/extension-placeholder'
import { focusView, insertPlainText } from './blocks.js'
import { jotExtensions } from './extensions/index.js'
import { HeldSelection } from './extensions/held.js'
import { Find, clearFind, runFind } from './extensions/find.js'
import { applyFolds, foldedHeadings } from './extensions/fold.js'
import { tagsIn } from './extensions/tags.js'
import { LANGUAGES } from './extensions/codeblock.js'
import { docToMarkdown, markdownToDoc, preferMarkdown, sliceToMarkdown } from './markdown.js'
import { createBlockMenu } from './ui/blockmenu.js'
import { createBubble } from './ui/bubble.js'
import { createColorPicker } from './ui/colors.js'
import { DateSuggest, createDateEditor } from './ui/dates.js'
import { createHandle } from './ui/handle.js'
import { icon } from './ui/icons.js'
import { createLinks } from './ui/linkedit.js'
import { createTagSuggest, createWikiSuggest } from './ui/links.js'
import { createMenu } from './ui/menu.js'
import { animatedFold, settle, slideIn } from './ui/motion.js'
import { createPalette } from './ui/palette.js'
import { createSlash } from './ui/slash.js'
import { createSurface } from './ui/surface.js'

const $ = (id) => document.getElementById(id)
const scroller = $('scroller')
const SAVE_DELAY = 400

// ---------------------------------------------------------------------------
// Bridge to Swift. JotEditor.* (bottom of file) is called from Swift;
// post() goes the other way. request() waits for Swift to answer through
// JotEditor.resolve.

function post(message) {
  window.webkit?.messageHandlers?.jot?.postMessage(message)
}

const pending = new Map()
let requestSeq = 0
function request(type, payload = {}) {
  requestSeq += 1
  const requestId = requestSeq
  post({ type, requestId, ...payload })
  return new Promise((resolve) => pending.set(requestId, resolve))
}

let editor
let ui = {}

// ---------------------------------------------------------------------------
// Notes. The editor keeps every opened note's live state (doc, undo history,
// caret, scroll) for the life of the app; Swift supplies Markdown the first
// time a note opens. Every save names the note it belongs to.

const notes = new Map()
let currentID = null
let dirty = false
let saveTimer = null
let indexNotes = []

function stateFor(markdown, meta) {
  const doc = markdownToDoc(editor, markdown)
  let state = EditorState.create({ doc, plugins: editor.state.plugins })
  state = applyFolds(state, meta?.folded)
  return state.apply(state.tr.setSelection(Selection.atEnd(state.doc)).setMeta('addToHistory', false))
}

function snapshot() {
  if (currentID == null) return
  notes.set(currentID, { state: editor.state, scroll: scroller.scrollTop })
}

function save() {
  clearTimeout(saveTimer)
  if (dirty === false || currentID == null) return
  dirty = false
  post({
    type: 'save',
    noteId: currentID,
    markdown: docToMarkdown(editor),
    meta: { folded: foldedHeadings(editor.state.doc) },
  })
}

function scheduleSave() {
  dirty = true
  clearTimeout(saveTimer)
  saveTimer = setTimeout(save, SAVE_DELAY)
}

function closeOverlays() {
  ui.blockMenu?.close()
  ui.links?.close(false)
  ui.links?.hidePreview()
  ui.dates?.close(false)
  ui.bubble?.hide()
  ui.palette?.close(false)
  closeFind(false)
}

function openNote(id, markdown, title, meta, direction = 0) {
  if (title != null) setTitle(title)
  if (id === currentID) return
  save()
  snapshot()
  closeOverlays()
  ui.handle?.hide()
  const cached = notes.get(id)
  editor.view.updateState(cached ? cached.state : stateFor(markdown, meta))
  currentID = id
  scroller.scrollTop = cached ? cached.scroll : 0
  document.body.classList.toggle('is-empty', editor.isEmpty)
  slideIn(editor.view.dom, direction)
}

function setTitle(title) {
  $('title').textContent = title || 'Note'
}

// Someone else changed the file (Obsidian, git, iCloud). Take it unless
// there are unsaved edits here — then ours win and overwrite on save.
function reloadNote(id, markdown, meta) {
  if (id !== currentID) {
    notes.delete(id)
    return
  }
  if (dirty) return
  const next = markdownToDoc(editor, markdown)
  if (next.eq(editor.state.doc)) return
  const { from } = editor.state.selection
  const tr = editor.state.tr.replaceWith(0, editor.state.doc.content.size, next.content)
  tr.setSelection(Selection.near(tr.doc.resolve(Math.min(from, tr.doc.content.size))))
  tr.setMeta('jotExternal', true)
  editor.view.dispatch(tr)
  editor.view.updateState(applyFolds(editor.state, meta?.folded))
}

function liveMarkdown(id) {
  if (id === currentID) return docToMarkdown(editor)
  const cached = notes.get(id)
  return cached ? docToMarkdown(editor, cached.state.doc) : null
}

const index = {
  notes: () => indexNotes.map((note) => ({ ...note, markdown: liveMarkdown(note.id) ?? note.markdown })),
  tags: () => {
    const all = new Set()
    for (const note of index.notes()) tagsIn(note.markdown).forEach((tag) => all.add(tag))
    return [...all].sort()
  },
}

// Add Markdown at the end of a note (Services menu, drops onto the notch).
// Returns false when the note isn't loaded here, so Swift writes the file.
function appendTo(id, markdown) {
  const isCurrent = id === currentID
  const cached = notes.get(id)
  if (isCurrent === false && cached == null) return false
  const state = isCurrent ? editor.state : cached.state
  const doc = markdownToDoc(editor, markdown)
  let end = state.doc.content.size
  const last = state.doc.lastChild
  if (last?.type.name === 'paragraph' && last.content.size === 0) end -= last.nodeSize
  const tr = state.tr.insert(end, doc.content)
  if (isCurrent) {
    editor.view.dispatch(tr.scrollIntoView())
    const dom = editor.view.nodeDOM(end)
    settle(dom)
  } else {
    notes.set(id, { ...cached, state: cached.state.apply(tr) })
    post({ type: 'save', noteId: id, markdown: docToMarkdown(editor, notes.get(id).state.doc), meta: { folded: foldedHeadings(notes.get(id).state.doc) } })
  }
  return true
}

// Quick capture: caret on a fresh line at the end of the note.
function capture() {
  const { state } = editor
  const last = state.doc.lastChild
  let tr = state.tr
  if (!(last?.type.name === 'paragraph' && last.content.size === 0)) {
    tr = tr.insert(state.doc.content.size, state.schema.nodes.paragraph.create())
  }
  tr.setSelection(Selection.atEnd(tr.doc)).scrollIntoView()
  editor.view.dispatch(tr)
  focusView(editor)
}

// ---------------------------------------------------------------------------
// Images and files

function readBase64(file) {
  return new Promise((resolve) => {
    const reader = new FileReader()
    reader.onload = () => resolve(String(reader.result).split(',')[1] || '')
    reader.onerror = () => resolve('')
    reader.readAsDataURL(file)
  })
}

function insertImageAt(pos, path, alt = '') {
  const { state, view } = editor
  const node = state.schema.nodes.image.create({ src: path, alt })
  const at = Math.min(pos ?? state.selection.from, state.doc.content.size)
  view.dispatch(state.tr.insert(at, node).scrollIntoView())
  settle(view.nodeDOM(at))
}

async function saveImages(files, pos) {
  for (const file of files) {
    const data = await readBase64(file)
    if (data === '') continue
    const ext = (file.type.split('/')[1] || 'png').replace('jpeg', 'jpg').replace('svg+xml', 'svg')
    const result = await request('saveImage', { noteId: currentID, data, ext, name: file.name || '' })
    if (result?.path) insertImageAt(pos, result.path, (file.name || '').replace(/\.[^.]+$/, ''))
  }
}

async function pickImage() {
  const result = await request('pickImage', { noteId: currentID })
  if (result?.path) insertImageAt(editor.state.selection.from, result.path, result.name || '')
  focusView(editor)
}

// Files dropped from Finder: Swift copies images into assets and links the
// rest, then tells us where the drop landed.
function insertFiles(x, y, items) {
  const hit = editor.view.posAtCoords({ left: x, top: y })
  const pos = hit ? hit.pos : editor.state.selection.from
  const content = []
  for (const item of items) {
    if (item.kind === 'image') content.push({ type: 'image', attrs: { src: item.path, alt: item.name || '' } })
    else content.push({ type: 'paragraph', content: [{ type: 'text', text: item.name || item.url, marks: [{ type: 'link', attrs: { href: item.url } }] }] })
  }
  editor.chain().insertContentAt(pos, content).run()
}

// ---------------------------------------------------------------------------
// Find

function setFindCount(result) {
  $('findcount').textContent = result == null || result.count === 0 ? ($('findq').value ? 'None' : '') : `${result.index} of ${result.count}`
}

function openFind(query) {
  document.body.classList.add('is-finding')
  const input = $('findq')
  if (typeof query === 'string') input.value = query
  input.focus()
  input.select()
  if (input.value) setFindCount(runFind(editor, input.value))
}

function closeFind(refocus = true) {
  if (document.body.classList.contains('is-finding') === false) return false
  document.body.classList.remove('is-finding')
  $('findq').value = ''
  $('findcount').textContent = ''
  clearFind(editor)
  if (refocus) focusView(editor)
  return true
}

// After jumping to a note from search: land on the match.
function reveal(query) {
  if (!query) return
  const result = runFind(editor, query)
  clearFind(editor)
  if (result.count) {
    const { from, to } = editor.state.selection
    editor.view.dispatch(editor.state.tr.setSelection(TextSelection.create(editor.state.doc, from, to)).scrollIntoView())
    const dom = editor.view.domAtPos(from).node
    settle(dom instanceof HTMLElement ? dom : dom.parentElement?.closest('p, li, h1, h2, h3, h4, h5, h6'))
  }
  focusView(editor)
}

// ---------------------------------------------------------------------------
// Header

// A word in the header for a moment ("Copied"), in place of a dialog.
function toast(text) {
  const el = $('toast')
  el.textContent = text
  el.classList.add('is-on')
  clearTimeout(toast.timer)
  toast.timer = setTimeout(() => el.classList.remove('is-on'), 1400)
}

function copyText(text, label = 'Copied') {
  post({ type: 'copy', text })
  toast(label)
}

function copyAll() {
  copyText(docToMarkdown(editor).trim(), 'Copied as Markdown')
}

// The ⋯ button: less-used actions, out of the way.
function createMoreMenu() {
  const menu = createMenu({
    className: 'is-more',
    onChoose: (item) => {
      surface.hide()
      item.run()
    },
  })
  document.body.appendChild(menu.root)
  const surface = createSurface(menu.root, { placement: 'bottom-end', gap: 4 })
  const items = [
    { id: 'find', title: 'Find in note', icon: 'search', hint: '⌘F', run: () => openFind() },
    { id: 'copy', title: 'Copy as Markdown', icon: 'copy', hint: '⌘⇧C', run: () => copyAll() },
    { id: 'rename', title: 'Rename note', icon: 'edit', run: () => startRename() },
    { id: 'settings', title: 'Settings…', icon: 'settings', hint: '⌘,', run: () => post({ type: 'settings' }) },
  ]
  return {
    open(anchor) {
      menu.render(items)
      surface.show(anchor)
    },
    close: () => surface.hide(),
    onKeyDown: (event) => surface.isOpen && menu.onKeyDown(event),
    contains: (node) => menu.root.contains(node),
    get isOpen() {
      return surface.isOpen
    },
  }
}

function copyBlock(pos) {
  const node = editor.state.doc.nodeAt(pos)
  if (node == null) return
  copyText(sliceToMarkdown(editor, editor.state.doc.slice(pos, pos + node.nodeSize)))
}

// Double-click the title to rename the note (and its file).
function startRename() {
  const title = $('title')
  if (title.isContentEditable) return
  const before = title.textContent
  title.contentEditable = 'plaintext-only'
  title.classList.add('is-editing')
  title.focus()
  document.getSelection().selectAllChildren(title)
  const finish = (commit) => {
    title.contentEditable = 'false'
    title.classList.remove('is-editing')
    const next = title.textContent.replace(/\s+/g, ' ').trim()
    if (commit && next && next !== before) post({ type: 'rename', noteId: currentID, title: next })
    else title.textContent = before
    focusView(editor)
  }
  title.onkeydown = (event) => {
    if (event.key === 'Enter') {
      event.preventDefault()
      finish(true)
    } else if (event.key === 'Escape') {
      event.preventDefault()
      event.stopPropagation()
      finish(false)
    }
  }
  title.onblur = () => title.isContentEditable && finish(true)
}

// ---------------------------------------------------------------------------
// Escape: close the innermost thing; with nothing open, close the island.

function handleEscape() {
  if (ui.palette.close()) return true
  if (ui.blockMenu.isOpen) {
    ui.blockMenu.close()
    return true
  }
  if (ui.codeLang.isOpen) {
    ui.codeLang.close()
    return true
  }
  if (ui.more.isOpen) {
    ui.more.close()
    return true
  }
  if (ui.links.close()) return true
  if (ui.dates.close()) return true
  if (closeFind()) return true
  if (ui.bubble.isOpen) {
    ui.bubble.hide()
    return true
  }
  if (editor.state.selection instanceof NodeSelection) {
    editor.commands.setTextSelection(editor.state.selection.to)
    return true
  }
  save()
  post({ type: 'escape' })
  return true
}

// Language picker for code blocks.
function createCodeLanguageMenu() {
  let pos = null
  const menu = createMenu({
    className: 'is-languages',
    onChoose: (item) => {
      surface.hide()
      const node = editor.state.doc.nodeAt(pos)
      if (node) editor.view.dispatch(editor.state.tr.setNodeMarkup(pos, undefined, { ...node.attrs, language: item.id || null }))
      focusView(editor)
    },
  })
  document.body.appendChild(menu.root)
  const surface = createSurface(menu.root, { placement: 'bottom-start', gap: 4, maxHeight: 280 })
  return {
    open(at, anchor, language) {
      pos = at
      menu.render(LANGUAGES.map(([id, title]) => ({ id, title, section: 'Language', checked: id === language })))
      surface.show(anchor)
    },
    close: () => surface.hide(),
    onKeyDown: (event) => surface.isOpen && menu.onKeyDown(event),
    contains: (node) => menu.root.contains(node),
    get isOpen() {
      return surface.isOpen
    },
  }
}

// ---------------------------------------------------------------------------
// Mount

function mount() {
  $('searchbtn').innerHTML = icon('search')
  $('morebtn').innerHTML = icon('more')
  $('findprev').innerHTML = icon('up')
  $('findnext').innerHTML = icon('down')
  $('findclose').innerHTML = icon('close')

  const slash = createSlash({ pickImage })
  const wiki = createWikiSuggest(index)
  const tagSuggest = createTagSuggest(index)
  const suggestions = [slash, wiki, tagSuggest, DateSuggest]

  editor = new Editor({
    element: $('editor'),
    editable: true,
    extensions: [
      ...jotExtensions({
        onLink: () => ui.links.open(),
        onFold: (view, pos) => animatedFold(view, pos),
      }),
      ...suggestions,
      Find,
      HeldSelection,
      Placeholder.configure({
        includeChildren: true,
        showOnlyCurrent: true,
        // To-do / list / quote / empty-note variants are set in CSS.
        placeholder: ({ node }) => {
          if (node.type.name === 'heading') return `Heading ${node.attrs.level}`
          if (node.type.name === 'codeBlock') return ''
          if (node.type.name === 'detailsSummary') return 'Toggle'
          return 'Type / for blocks, @ for dates, [[ to link'
        },
      }),
    ],
    editorProps: {
      attributes: { class: 'tiptap', spellcheck: 'true' },
      // Keep the caret clear of the scroller's fade-out edges.
      scrollMargin: { top: 24, bottom: 44, left: 0, right: 0 },
      scrollThreshold: { top: 24, bottom: 44, left: 0, right: 0 },
      clipboardTextSerializer: (slice) => sliceToMarkdown(editor, slice),
      handlePaste(_view, event) {
        const files = [...(event.clipboardData?.files || [])].filter((file) => file.type.startsWith('image/'))
        if (files.length) {
          saveImages(files, editor.state.selection.from)
          return true
        }
        const text = event.clipboardData?.getData('text/plain') || ''
        const html = event.clipboardData?.getData('text/html') || ''
        if (editor.isActive('codeBlock') || preferMarkdown(text, html) === false) return false
        const doc = markdownToDoc(editor, text)
        editor.chain().insertContent(doc.toJSON().content).scrollIntoView().run()
        return true
      },
      handleDrop(view, event, _slice, moved) {
        if (moved) return false
        const files = [...(event.dataTransfer?.files || [])].filter((file) => file.type.startsWith('image/'))
        if (files.length === 0) return false
        const hit = view.posAtCoords({ left: event.clientX, top: event.clientY })
        saveImages(files, hit?.pos)
        return true
      },
      handleKeyDown(view, event) {
        // View props run before plugins; leave Escape to an open suggestion.
        if (event.key !== 'Escape') return false
        if (suggestions.some((extension) => extension.key.getState(view.state)?.active)) return false
        return handleEscape()
      },
    },
    onUpdate({ transaction }) {
      if (transaction.getMeta('jotExternal') !== true) scheduleSave()
      document.body.classList.toggle('is-empty', editor.isEmpty)
      ui.handle?.refresh()
    },
    onSelectionUpdate() {
      ui.bubble?.update()
    },
    onTransaction({ transaction }) {
      // A block landed from a drag: let it settle in.
      if (transaction.getMeta('uiEvent') === 'drop') {
        const at = editor.state.selection.from
        requestAnimationFrame(() => settle(editor.view.nodeDOM(at)))
      }
    },
    onBlur: () => save(),
  })

  const view = editor.view
  const colors = createColorPicker()
  ui.handle = createHandle(editor, scroller, { onMenu: (target, anchor) => ui.blockMenu.open(target, anchor) })
  ui.links = createLinks(editor, { openURL: (url) => post({ type: 'openURL', url }) })
  ui.blockMenu = createBlockMenu(editor, { handle: ui.handle, colors, copyMarkdown: copyBlock })
  ui.dates = createDateEditor(editor)
  ui.codeLang = createCodeLanguageMenu()
  ui.more = createMoreMenu()
  ui.bubble = createBubble(editor, {
    colors,
    links: ui.links,
    isBusy: () => ui.palette?.isOpen || ui.blockMenu.isOpen || ui.links.isOpen || ui.dates.isOpen,
  })
  ui.palette = createPalette({
    notes: index.notes,
    currentId: () => currentID,
    onOpen: (id, query) => {
      if (id === currentID) reveal(query)
      else post({ type: 'navigate', noteId: id, query })
    },
    onCreate: (title) => post({ type: 'createNote', title }),
  })

  // Clicks on things inside the text.
  view.dom.addEventListener('click', (event) => {
    const wiki = event.target.closest?.('.jot-wiki')
    if (wiki) {
      event.preventDefault()
      post({ type: 'navigate', title: wiki.dataset.title })
      return
    }
    const tag = event.target.closest?.('.jot-tag')
    if (tag && (event.metaKey || view.state.selection.empty)) {
      const word = tag.dataset.tag
      if (word && event.metaKey) ui.palette.open(`#${word}`)
    }
  })
  view.dom.addEventListener('jot:copy', (event) => copyText(event.detail.text))
  view.dom.addEventListener('jot:code-language', (event) => {
    ui.codeLang.open(event.detail.pos, event.detail.anchor, event.detail.language)
  })

  // App keys that work wherever focus is.
  document.addEventListener(
    'keydown',
    (event) => {
      for (const menu of [ui.blockMenu, ui.codeLang, ui.more]) {
        if (menu.isOpen === false) continue
        if (event.key === 'Escape') {
          event.preventDefault()
          event.stopPropagation()
          menu.close()
          focusView(editor)
          return
        }
        if (menu.onKeyDown(event)) {
          event.preventDefault()
          event.stopPropagation()
          return
        }
        menu.close()
      }
      if (ui.bubble.menuKeyDown(event)) {
        event.preventDefault()
        event.stopPropagation()
        return
      }
      const mod = event.metaKey || event.ctrlKey
      const key = event.key.toLowerCase()
      // Tabs: ⌘1…⌘8 by position, ⌘9 the last; ⌃Tab / ⌃⇧Tab cycle.
      if (event.metaKey && /^[1-9]$/.test(event.key)) {
        event.preventDefault()
        post({ type: 'switchTab', index: event.key === '9' ? -1 : Number(event.key) - 1 })
        return
      }
      if (event.ctrlKey && event.key === 'Tab') {
        event.preventDefault()
        post({ type: 'switchTab', delta: event.shiftKey ? -1 : 1 })
        return
      }
      if (mod && key === 'p') {
        event.preventDefault()
        ui.palette.isOpen ? ui.palette.close() : ui.palette.open()
      } else if (mod && key === 'f') {
        event.preventDefault()
        openFind()
      } else if (mod && key === 'g' && document.body.classList.contains('is-finding')) {
        event.preventDefault()
        setFindCount(runFind(editor, $('findq').value, event.shiftKey ? -1 : 1))
      } else if (mod && event.shiftKey && key === 'c' && editor.state.selection.empty) {
        event.preventDefault()
        copyAll()
      } else if (mod && key === 'n') {
        event.preventDefault()
        post({ type: 'createNote', title: '' })
      } else if (mod && key === ',') {
        event.preventDefault()
        post({ type: 'settings' })
      }
    },
    true,
  )
  document.addEventListener('keydown', (event) => {
    if (event.defaultPrevented || event.key !== 'Escape') return
    if (event.target === $('findq') || event.target === $('title')) return
    handleEscape()
  })
  document.addEventListener('mousedown', (event) => {
    const target = event.target
    if (ui.blockMenu.isOpen && ui.blockMenu.contains(target) === false && target.closest?.('.jot-handle-grip') == null) ui.blockMenu.close()
    if (ui.codeLang.isOpen && ui.codeLang.contains(target) === false) ui.codeLang.close()
    if (ui.more.isOpen && ui.more.contains(target) === false && target.closest?.('#morebtn') == null) ui.more.close()
    if (colors.isOpen && colors.contains(target) === false && ui.bubble.contains(target) === false) colors.close()
  })

  // Clicking the empty space under the last block puts the caret at the end.
  scroller.addEventListener('mousedown', (event) => {
    if (event.target !== scroller) return
    if (event.clientY < view.dom.getBoundingClientRect().bottom) return
    event.preventDefault()
    focusView(editor, Selection.atEnd(editor.state.doc))
  })

  // Files dropped outside the text would navigate the page away.
  document.addEventListener('dragover', (event) => {
    if (event.dataTransfer?.types?.includes('Files')) event.preventDefault()
  })
  document.addEventListener('drop', (event) => {
    if (event.dataTransfer?.types?.includes('Files')) event.preventDefault()
  })

  $('title').addEventListener('dblclick', startRename)
  $('searchbtn').addEventListener('click', () => ui.palette.open())
  $('morebtn').addEventListener('mousedown', (event) => {
    event.preventDefault()
    ui.more.isOpen ? ui.more.close() : ui.more.open($('morebtn'))
  })
  $('findq').addEventListener('input', (event) => setFindCount(runFind(editor, event.target.value)))
  $('findq').addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      event.preventDefault()
      setFindCount(runFind(editor, event.target.value, event.shiftKey ? -1 : 1))
    } else if (event.key === 'Escape') {
      event.preventDefault()
      closeFind()
    }
  })
  for (const [id, delta] of [['findprev', -1], ['findnext', 1]]) {
    $(id).addEventListener('mousedown', (event) => {
      event.preventDefault()
      setFindCount(runFind(editor, $('findq').value, delta))
    })
  }
  $('findclose').addEventListener('mousedown', (event) => {
    event.preventDefault()
    closeFind()
  })

  window.addEventListener('blur', save)
  post({ type: 'ready' })
}

// ---------------------------------------------------------------------------
// Called from Swift

window.JotEditor = {
  open: (id, markdown, title, meta, direction) => openNote(id, markdown, title, meta, direction),
  reload: reloadNote,
  setTitle,
  focus() {
    focusView(editor)
    editor.view.dispatch(editor.state.tr.scrollIntoView())
  },
  capture,
  append: appendTo,
  flush: save,
  markdown: () => docToMarkdown(editor),
  forget(id) {
    notes.delete(id)
  },
  setIndex(list) {
    indexNotes = Array.isArray(list) ? list : []
  },
  openPalette: (query) => ui.palette.open(query || ''),
  find: reveal,
  insertFiles,
  insertImage: (path) => insertImageAt(editor.state.selection.from, path),
  // ⌘⇧V "Paste and Match Style": the text alone, taking on the formatting
  // where the caret is. No Markdown, links or images are interpreted.
  pastePlain(text) {
    if (!text) return
    // Typing in the find field or the title? Paste there.
    const active = document.activeElement
    if (active && active !== editor.view.dom && (active.matches('input, textarea') || active.isContentEditable)) {
      document.execCommand('insertText', false, active.matches('input') ? text.replace(/\s*\n\s*/g, ' ') : text)
      return
    }
    focusView(editor)
    insertPlainText(editor, text)
  },
  resolve(requestId, value) {
    pending.get(requestId)?.(value)
    pending.delete(requestId)
  },
  setPrefs(prefs = {}) {
    if (prefs.fontSize) document.documentElement.style.setProperty('--text-size', `${prefs.fontSize}px`)
  },
  // The island just opened: header, text, then the rest fade up in turn.
  reveal() {
    document.body.classList.remove('is-revealing')
    void document.body.offsetWidth
    document.body.classList.add('is-revealing')
  },
  // Migration from the old HTML notes: convert without opening.
  convert(html) {
    const scratch = new Editor({ extensions: jotExtensions(), content: html || '' })
    const out = docToMarkdown(scratch)
    scratch.destroy()
    return out
  },
}

mount()
