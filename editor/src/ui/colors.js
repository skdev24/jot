import { COLORS } from '../extensions/marks.js'
import { createSurface } from './surface.js'

const NAMES = { gray: 'Gray', brown: 'Brown', orange: 'Orange', yellow: 'Yellow', green: 'Green', blue: 'Blue', purple: 'Purple', pink: 'Pink', red: 'Red' }

// Notion-style palette: a row of text colors and a row of backgrounds.
// `apply({ text })` / `apply({ background })`; null means default.
export function createColorPicker() {
  const el = document.createElement('div')
  el.className = 'jot-pop jot-colors'
  const row = (kind, label) => {
    const swatches = [null, ...COLORS]
      .map((color) => {
        const name = color ? NAMES[color] : 'Default'
        return `<button type="button" class="jot-swatch" data-kind="${kind}" data-swatch="${color || 'default'}" title="${name} ${kind === 'text' ? 'text' : 'background'}">A</button>`
      })
      .join('')
    return `<div class="jot-colors-label">${label}</div><div class="jot-colors-row">${swatches}</div>`
  }
  el.innerHTML = row('text', 'Text') + row('background', 'Background')
  document.body.appendChild(el)
  const surface = createSurface(el, { placement: 'bottom-start', gap: 6 })
  let onPick = null
  let current = { text: null, background: null }

  el.addEventListener('mousedown', (event) => {
    event.preventDefault()
    const button = event.target.closest('.jot-swatch')
    if (button == null || onPick == null) return
    const value = button.dataset.swatch === 'default' ? null : button.dataset.swatch
    onPick(button.dataset.kind === 'text' ? { text: value } : { background: value })
    current = { ...current, ...(button.dataset.kind === 'text' ? { text: value } : { background: value }) }
    paint()
  })

  function paint() {
    el.querySelectorAll('.jot-swatch').forEach((button) => {
      const value = button.dataset.swatch === 'default' ? null : button.dataset.swatch
      button.classList.toggle('is-active', current[button.dataset.kind] === value)
    })
  }

  return {
    open(anchor, { text = null, background = null } = {}, pick) {
      onPick = pick
      current = { text, background }
      paint()
      surface.show(anchor)
    },
    close: () => surface.hide(),
    contains: (node) => el.contains(node),
    get isOpen() {
      return surface.isOpen
    },
  }
}
