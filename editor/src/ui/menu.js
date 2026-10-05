import { icon } from './icons.js'

// A keyboard-driven list used by every menu (slash, block, language,
// [[links]], dates, palette). items:
//   { section?, id, title, hint?, icon?, swatch?, detail?, danger?, run? }
export function createMenu({ className = '', onChoose, emptyLabel = 'No results' }) {
  const root = document.createElement('div')
  root.className = `jot-menu ${className}`.trim()
  root.setAttribute('role', 'listbox')
  root.addEventListener('mousedown', (event) => event.preventDefault())

  let items = []
  let active = 0
  let buttons = []

  function highlight(next, scroll = true) {
    if (buttons.length === 0) return
    active = Math.max(0, Math.min(next, buttons.length - 1))
    buttons.forEach((button, index) => {
      const on = index === active
      button.classList.toggle('is-active', on)
      button.setAttribute('aria-selected', on ? 'true' : 'false')
    })
    if (scroll) buttons[active].scrollIntoView({ block: 'nearest' })
  }

  function paint() {
    root.replaceChildren()
    buttons = []
    if (items.length === 0) {
      const empty = document.createElement('div')
      empty.className = 'jot-menu-empty'
      empty.textContent = emptyLabel
      root.appendChild(empty)
      return
    }
    let section = null
    items.forEach((item) => {
      if (item.section && item.section !== section) {
        if (section != null) {
          const rule = document.createElement('div')
          rule.className = 'jot-menu-rule'
          root.appendChild(rule)
        }
        section = item.section
        const label = document.createElement('div')
        label.className = 'jot-menu-section'
        label.textContent = section
        root.appendChild(label)
      }
      const button = document.createElement('button')
      button.type = 'button'
      button.setAttribute('role', 'option')
      if (item.danger) button.classList.add('is-danger')
      if (item.checked) button.classList.add('is-checked')
      let lead = ''
      if (item.swatch) lead = `<span class="jot-menu-icon jot-swatch" data-swatch="${item.swatch}">A</span>`
      else if (item.icon) lead = `<span class="jot-menu-icon">${icon(item.icon)}</span>`
      button.innerHTML = `${lead}<span class="jot-menu-text"><span class="jot-menu-title"></span>${item.detail ? '<span class="jot-menu-detail"></span>' : ''}</span>${item.hint ? '<kbd></kbd>' : ''}`
      button.querySelector('.jot-menu-title').textContent = item.title
      if (item.detail) button.querySelector('.jot-menu-detail').textContent = item.detail
      if (item.hint) button.querySelector('kbd').textContent = item.hint
      const index = buttons.length
      button.addEventListener('mousemove', () => {
        if (active !== index) highlight(index, false)
      })
      button.addEventListener('click', () => onChoose(item))
      buttons.push(button)
      root.appendChild(button)
    })
    highlight(active, false)
  }

  return {
    root,
    render(next) {
      items = next
      active = 0
      paint()
      root.scrollTop = 0
    },
    onKeyDown(event) {
      // An IME is still composing (Chinese, Japanese, Korean…): its Enter
      // confirms the composition, it must not pick a menu item.
      if (event.isComposing || event.keyCode === 229) return false
      if (items.length === 0) return false
      const key = event.key
      if (key === 'ArrowDown' || (event.ctrlKey && key === 'n')) highlight(active + 1 >= buttons.length ? 0 : active + 1)
      else if (key === 'ArrowUp' || (event.ctrlKey && key === 'p')) highlight(active - 1 < 0 ? buttons.length - 1 : active - 1)
      else if (key === 'Home') highlight(0)
      else if (key === 'End') highlight(buttons.length - 1)
      else if (key === 'PageDown') highlight(active + 6)
      else if (key === 'PageUp') highlight(active - 6)
      else if (key === 'Enter' || key === 'Tab') onChoose(items[active])
      else return false
      return true
    },
    get size() {
      return items.length
    },
    get current() {
      return items[active]
    },
  }
}
