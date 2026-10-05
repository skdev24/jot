import { computePosition, flip, offset, shift, size } from '@floating-ui/dom'

// Every floating thing (menus, toolbar, popovers) goes through here so they
// all move the same way: they grow out of their anchor on the way in and
// shrink back toward it on the way out. CSS owns the motion; this only sets
// data-state / data-side and waits for the exit to finish.

export const reducedMotion = () => window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true

const ORIGIN = { top: 'bottom', bottom: 'top', left: 'right', right: 'left' }

export function createSurface(el, { placement = 'bottom-start', gap = 6, maxHeight = null, onHidden } = {}) {
  el.classList.add('jot-surface')
  el.hidden = true
  el.style.position = 'fixed'
  el.style.top = '0'
  el.style.left = '0'
  let reference = null
  let open = false
  let hideTimer = null

  async function place() {
    if (reference == null) return
    const middleware = [offset(gap), flip({ padding: 8 }), shift({ padding: 8 })]
    if (maxHeight) {
      middleware.push(
        size({
          padding: 8,
          apply({ availableHeight, elements }) {
            elements.floating.style.maxHeight = `${Math.max(120, Math.min(maxHeight, availableHeight))}px`
          },
        }),
      )
    }
    const result = await computePosition(reference, el, { placement, strategy: 'fixed', middleware })
    const side = result.placement.split('-')[0]
    const align = result.placement.split('-')[1]
    el.dataset.side = side
    const cross = align === 'start' ? 'left' : align === 'end' ? 'right' : 'center'
    el.style.transformOrigin = side === 'top' || side === 'bottom' ? `${cross} ${ORIGIN[side]}` : `${ORIGIN[side]} center`
    el.style.left = `${Math.round(result.x)}px`
    el.style.top = `${Math.round(result.y)}px`
  }

  return {
    el,
    get isOpen() {
      return open
    },
    async show(ref) {
      reference = ref
      clearTimeout(hideTimer)
      const wasOpen = open
      open = true
      el.hidden = false
      await place()
      if (wasOpen === false || el.dataset.state !== 'open') {
        el.dataset.state = 'closed'
        // Commit the closed style, then flip: the transition runs without
        // waiting on a frame callback (those pause in background windows).
        void el.offsetWidth
        if (open) el.dataset.state = 'open'
      }
    },
    place,
    hide({ instant = false } = {}) {
      if (open === false) return false
      open = false
      el.dataset.state = 'closed'
      clearTimeout(hideTimer)
      const finish = () => {
        if (open) return
        el.hidden = true
        onHidden?.()
      }
      if (instant || reducedMotion()) finish()
      else hideTimer = setTimeout(finish, 140)
      return true
    },
  }
}

// A rectangle that follows a document range, for anchoring to text.
export function rangeReference(view, from, to) {
  return {
    getBoundingClientRect() {
      const start = view.coordsAtPos(from)
      const end = view.coordsAtPos(to, -1)
      if (start.top === end.top || from === to) {
        return new DOMRect(start.left, start.top, Math.max(end.right - start.left, 1), start.bottom - start.top)
      }
      const box = view.dom.getBoundingClientRect()
      return new DOMRect(box.left, start.top, box.width, end.bottom - start.top)
    },
    contextElement: view.dom,
  }
}
