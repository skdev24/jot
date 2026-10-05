import * as chrono from 'chrono-node'
import { NodeSelection } from '@tiptap/pm/state'
import { dateLabel, isoDate, isoTime } from '../extensions/date.js'
import { icon } from './icons.js'
import { createSurface } from './surface.js'
import { fuzzy, suggestExtension } from './suggest.js'

function at(days, hour = null, minute = 0) {
  const date = new Date()
  date.setDate(date.getDate() + days)
  if (hour != null) date.setHours(hour, minute, 0, 0)
  return date
}

function nextWeekday(weekday) {
  const date = new Date()
  const delta = (weekday - date.getDay() + 7) % 7 || 7
  date.setDate(date.getDate() + delta)
  return date
}

function presets() {
  const evening = new Date().getHours() < 17 ? at(0, 18) : at(1, 9)
  return [
    { title: 'Today', date: at(0), time: false },
    { title: 'Tomorrow', date: at(1), time: false },
    { title: evening.getDate() === new Date().getDate() ? 'This evening' : 'Tomorrow morning', date: evening, time: true },
    { title: 'Next week', date: nextWeekday(1), time: false },
    { title: 'This weekend', date: nextWeekday(6), time: false },
  ]
}

const WEEKDAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday']

const toAttrs = (date, withTime) => ({ date: isoDate(date), time: withTime ? isoTime(date) : null })

// Natural language first ("fri 3pm", "in 2 weeks", "oct 12"), then presets.
export function dateOptions(query) {
  const options = []
  const text = query.trim()
  if (text) {
    const [result] = chrono.parse(text, new Date(), { forwardDate: true })
    if (result) {
      const withTime = result.start.isCertain('hour')
      const attrs = toAttrs(result.start.date(), withTime)
      options.push({ id: 'parsed', section: 'Date', icon: 'calendar', title: dateLabel(attrs), detail: attrs.time ? `${attrs.date} ${attrs.time}` : attrs.date, attrs })
    }
  }
  // Half-typed weekdays ("f", "fr", "tu") already mean the next one.
  const word = text.toLowerCase()
  if (/^[a-z]{1,9}$/.test(word) && options.length === 0) {
    WEEKDAYS.forEach((name, weekday) => {
      if (name.startsWith(word) === false) return
      const attrs = toAttrs(nextWeekday(weekday), false)
      options.push({ id: name, section: 'Date', icon: 'calendar', title: dateLabel(attrs), detail: attrs.date, attrs })
    })
  }
  for (const preset of presets()) {
    if (text && fuzzy(text, preset.title) === 0) continue
    const attrs = toAttrs(preset.date, preset.time)
    options.push({ id: preset.title, section: text ? 'Suggestions' : 'Date', icon: 'calendar', title: preset.title, detail: dateLabel(attrs), attrs })
  }
  return options
}

export const DateSuggest = suggestExtension({
  name: 'jotDates',
  char: '@',
  allowSpaces: true,
  placeholder: 'Today, fri 3pm, in 2 weeks…',
  emptyLabel: 'Type a date, like “fri 3pm”',
  className: 'is-dates',
  items: (query) => dateOptions(query),
  command: ({ editor, range, item }) => {
    editor.chain().deleteRange(range).insertContent([{ type: 'date', attrs: item.attrs }, { type: 'text', text: ' ' }]).run()
  },
})

// Clicking a chip: change it in words, or remove it.
export function createDateEditor(editor) {
  const view = editor.view
  const el = document.createElement('form')
  el.className = 'jot-pop jot-dateedit'
  el.innerHTML = `
    <span class="jot-pop-icon">${icon('calendar')}</span>
    <input type="text" spellcheck="false" autocomplete="off" placeholder="tomorrow 9am" />
    <button type="button" class="icon" data-act="remove" title="Remove date">${icon('trash')}</button>`
  document.body.appendChild(el)
  const input = el.querySelector('input')
  const surface = createSurface(el, { placement: 'bottom-start', gap: 6 })
  let pos = null

  function close(refocus = true) {
    if (surface.hide() === false) return false
    pos = null
    if (refocus) view.focus()
    return true
  }

  function apply() {
    const [option] = dateOptions(input.value)
    if (pos != null && option) {
      view.dispatch(view.state.tr.setNodeMarkup(pos, undefined, option.attrs))
    }
    close()
  }

  el.addEventListener('submit', (event) => {
    event.preventDefault()
    apply()
  })
  el.querySelector('[data-act="remove"]').addEventListener('mousedown', (event) => {
    event.preventDefault()
    if (pos != null) view.dispatch(view.state.tr.delete(pos, pos + 1))
    close()
  })
  input.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      event.preventDefault()
      event.stopPropagation()
      close()
    }
  })
  input.addEventListener('blur', () => setTimeout(() => el.contains(document.activeElement) || close(false), 0))

  view.dom.addEventListener('mousedown', (event) => {
    const chip = event.target.closest?.('.jot-date')
    if (chip == null) return
    event.preventDefault()
    pos = view.posAtDOM(chip, 0)
    const node = view.state.doc.nodeAt(pos)
    if (node?.type.name !== 'date') return
    view.dispatch(view.state.tr.setSelection(NodeSelection.create(view.state.doc, pos)))
    input.value = dateLabel(node.attrs)
    surface.show(chip).then(() => {
      input.focus()
      input.select()
    })
  })

  return { close, get isOpen() { return surface.isOpen } }
}
