import { Node } from '@tiptap/core'

// A due date or reminder, stored in the file as `📅 2026-10-06` or
// `📅 2026-10-06 15:00` — the Obsidian Tasks format — so other tools and Jot's
// own reminder scanner can read it. The chip shows a relative label.

const PATTERN = /^📅️?[ \t]?(\d{4}-\d{2}-\d{2})(?:[ \t]+(\d{1,2}:\d{2}))?/u

const pad = (value) => String(value).padStart(2, '0')

export function isoDate(date) {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

export function isoTime(date) {
  return `${pad(date.getHours())}:${pad(date.getMinutes())}`
}

export function toDate(attrs) {
  const [y, m, d] = String(attrs.date).split('-').map(Number)
  const [hh, mm] = attrs.time ? attrs.time.split(':').map(Number) : [0, 0]
  return new Date(y, m - 1, d, hh, mm)
}

function dayDelta(date, now = new Date()) {
  const a = new Date(date.getFullYear(), date.getMonth(), date.getDate())
  const b = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  return Math.round((a - b) / 86400000)
}

export function dateLabel(attrs, now = new Date()) {
  const date = toDate(attrs)
  if (Number.isNaN(date.getTime())) return attrs.date
  const delta = dayDelta(date, now)
  let day
  if (delta === 0) day = 'Today'
  else if (delta === 1) day = 'Tomorrow'
  else if (delta === -1) day = 'Yesterday'
  else if (delta > 1 && delta < 7) day = date.toLocaleDateString(undefined, { weekday: 'long' })
  else {
    const sameYear = date.getFullYear() === now.getFullYear()
    day = date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', ...(sameYear ? {} : { year: 'numeric' }) })
  }
  if (attrs.time == null) return day
  return `${day} ${date.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}`
}

export function dateStatus(attrs, now = new Date()) {
  const date = toDate(attrs)
  const delta = dayDelta(date, now)
  if (delta < 0 || (attrs.time && date < now)) return 'overdue'
  if (delta === 0) return 'today'
  return 'upcoming'
}

// Chips re-label themselves as days pass (Today → Yesterday).
const live = new Set()
function paint(dom, attrs) {
  dom.textContent = dateLabel(attrs)
  dom.dataset.status = dateStatus(attrs)
}
setInterval(() => live.forEach(({ dom, attrs }) => paint(dom, attrs)), 60_000).unref?.()

export const DateChip = Node.create({
  name: 'date',
  group: 'inline',
  inline: true,
  atom: true,
  selectable: true,
  draggable: false,

  addAttributes() {
    return {
      date: { default: null, parseHTML: (element) => element.getAttribute('data-date') },
      time: { default: null, parseHTML: (element) => element.getAttribute('data-time') || null },
    }
  },

  parseHTML() {
    return [{ tag: 'span[data-date]' }]
  },

  renderHTML({ node }) {
    const attrs = { 'data-date': node.attrs.date, class: 'jot-date' }
    if (node.attrs.time) attrs['data-time'] = node.attrs.time
    return ['span', attrs, dateLabel(node.attrs)]
  },

  renderText({ node }) {
    return `📅 ${node.attrs.date}${node.attrs.time ? ` ${node.attrs.time}` : ''}`
  },

  addNodeView() {
    return ({ node }) => {
      const dom = document.createElement('span')
      dom.className = 'jot-date'
      dom.contentEditable = 'false'
      const entry = { dom, attrs: node.attrs }
      paint(dom, node.attrs)
      live.add(entry)
      return {
        dom,
        update(next) {
          if (next.type.name !== 'date') return false
          entry.attrs = next.attrs
          paint(dom, next.attrs)
          return true
        },
        destroy() {
          live.delete(entry)
        },
      }
    }
  },

  markdownTokenizer: {
    name: 'date',
    level: 'inline',
    start: (src) => {
      const index = src.indexOf('📅')
      return index < 0 ? undefined : index
    },
    tokenize(src) {
      const match = PATTERN.exec(src)
      if (match == null) return undefined
      return { type: 'date', raw: match[0], date: match[1], time: match[2] ? match[2].padStart(5, '0') : null }
    },
  },

  parseMarkdown(token, helpers) {
    return helpers.createNode('date', { date: token.date, time: token.time })
  },

  renderMarkdown(node) {
    return `📅 ${node.attrs?.date}${node.attrs?.time ? ` ${node.attrs.time}` : ''}`
  },
})
