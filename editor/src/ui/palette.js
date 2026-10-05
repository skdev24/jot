import { dateLabel } from '../extensions/date.js'
import { icon } from './icons.js'
import { createMenu } from './menu.js'
import { reducedMotion } from './surface.js'
import { fuzzy } from './suggest.js'

const MAX_LINES = 14

// Turn a Markdown line into something readable for a result row.
function plain(line) {
  return line
    .replace(/📅\uFE0F?\s?(\d{4}-\d{2}-\d{2})(?:\s+(\d{1,2}:\d{2}))?/gu, (_m, date, time) => `· ${dateLabel({ date, time: time || null })}`)
    .replace(/^\s*(?:[-*+]\s+\[[ xX]\]\s+|[-*+]\s+|\d+[.)]\s+|#{1,6}\s+|>\s*(?:\[!\w+\][+-]?\s*)?)/, '')
    .replace(/<[^>]+>/g, '')
    .replace(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g, (_m, title, alias) => alias || title)
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/[*_~=`]+/g, '')
    .trim()
}

function snippet(text, query) {
  const at = text.toLowerCase().indexOf(query.toLowerCase())
  if (at < 40) return text
  return `…${text.slice(at - 30)}`
}

// ⌘P: jump to a note by name, find text across every note, or make a note.
export function createPalette({ notes, currentId, onOpen, onCreate }) {
  const root = document.createElement('div')
  root.className = 'jot-palette'
  root.hidden = true
  root.innerHTML = `
    <div class="jot-palette-panel" role="dialog" aria-label="Search notes">
      <label class="jot-palette-field">${icon('search')}<input type="text" spellcheck="false" autocomplete="off" placeholder="Search notes, #tags, or type a new title" /><kbd>esc</kbd></label>
    </div>`
  document.body.appendChild(root)
  const panel = root.querySelector('.jot-palette-panel')
  const input = root.querySelector('input')
  const menu = createMenu({
    className: 'is-palette',
    emptyLabel: 'Nothing found',
    onChoose: (item) => {
      close()
      if (item.create) onCreate(item.title)
      else onOpen(item.noteId, item.query || null)
    },
  })
  panel.appendChild(menu.root)
  let previousFocus = null
  let hideTimer = null

  function results(raw) {
    const query = raw.trim()
    const all = notes()
    const out = []
    if (query === '') {
      const active = currentId()
      for (const note of all) {
        out.push({ section: 'Notes', icon: 'note', title: note.title, detail: note.id === active ? 'Current' : '', noteId: note.id })
      }
      return out
    }

    const tagQuery = query.startsWith('#') ? query.slice(1).toLowerCase() : null
    if (tagQuery == null) {
      all
        .map((note) => ({ note, rank: fuzzy(query, note.title) }))
        .filter((row) => row.rank > 0)
        .sort((a, b) => b.rank - a.rank)
        .slice(0, 6)
        .forEach(({ note }) => out.push({ section: 'Notes', icon: 'note', title: note.title, noteId: note.id }))
    }

    const needle = tagQuery != null ? `#${tagQuery}` : query.toLowerCase()
    let lines = 0
    for (const note of all) {
      if (lines >= MAX_LINES) break
      let perNote = 0
      for (const line of note.markdown.split('\n')) {
        if (perNote >= 3 || lines >= MAX_LINES) break
        if (line.toLowerCase().includes(needle) === false) continue
        const text = plain(line)
        if (text === '') continue
        const done = /^\s*[-*+]\s+\[[xX]\]/.test(line)
        out.push({
          section: tagQuery != null ? `Tagged #${tagQuery}` : 'In notes',
          icon: /^\s*[-*+]\s+\[[ xX]\]/.test(line) ? (done ? 'checked' : 'todo') : 'text',
          title: snippet(text, tagQuery != null ? `#${tagQuery}` : query),
          detail: note.title,
          noteId: note.id,
          query: tagQuery != null ? `#${tagQuery}` : query,
        })
        perNote += 1
        lines += 1
      }
    }

    const exists = all.some((note) => note.title.toLowerCase() === query.toLowerCase())
    if (tagQuery == null && exists === false) out.push({ section: 'New', icon: 'plus', title: query, detail: 'Create note', create: true })
    return out
  }

  function refresh() {
    menu.render(results(input.value))
  }

  function open(query = '') {
    clearTimeout(hideTimer)
    previousFocus = document.activeElement
    input.value = query
    refresh()
    root.hidden = false
    requestAnimationFrame(() => root.classList.add('is-open'))
    input.focus()
    input.select()
  }

  function close(restore = true) {
    if (root.hidden) return false
    root.classList.remove('is-open')
    hideTimer = setTimeout(() => (root.hidden = true), reducedMotion() ? 0 : 160)
    if (restore) previousFocus?.focus?.()
    return true
  }

  input.addEventListener('input', refresh)
  input.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      event.preventDefault()
      event.stopPropagation()
      close()
      return
    }
    if (menu.onKeyDown(event)) event.preventDefault()
  })
  root.addEventListener('mousedown', (event) => {
    if (panel.contains(event.target) === false) {
      event.preventDefault()
      close()
    }
  })

  return {
    open,
    close,
    get isOpen() {
      return root.hidden === false
    },
  }
}
