import { foldRange, toggleFold } from '../extensions/fold.js'
import { reducedMotion } from './surface.js'

// Small, physical motions. Everything checks Reduce Motion and silently
// does nothing where the DOM can't animate (tests).

const EASE = 'cubic-bezier(0.2, 0.8, 0.2, 1)'
const canAnimate = (el) => el instanceof HTMLElement && typeof el.animate === 'function' && reducedMotion() === false

// FLIP: the element is already in its new place; play it in from `fromTop`.
export function glideFrom(el, fromTop, duration = 220) {
  if (canAnimate(el) === false || fromTop == null) return
  const delta = fromTop - el.getBoundingClientRect().top
  if (Math.abs(delta) < 1) return
  el.animate([{ transform: `translateY(${delta}px)` }, { transform: 'translateY(0)' }], { duration, easing: EASE })
}

// A block that just landed (drop, duplicate): settle in.
export function settle(el) {
  if (canAnimate(el) === false) return
  el.animate(
    [
      { opacity: 0.4, transform: 'scale(0.985)', backgroundColor: 'var(--accent-soft)' },
      { opacity: 1, transform: 'scale(1)', backgroundColor: 'transparent' },
    ],
    { duration: 320, easing: EASE },
  )
}

// Switching tabs: the new note slides in from the side you moved toward.
export function slideIn(el, direction) {
  if (canAnimate(el) === false || !direction) return
  el.animate(
    [
      { opacity: 0, transform: `translateX(${direction > 0 ? 18 : -18}px)` },
      { opacity: 1, transform: 'translateX(0)' },
    ],
    { duration: 240, easing: EASE },
  )
}

// Collapse/expand a heading's section with a height animation instead of
// a snap. Folding itself stays a plain document change (undoable).
export function animatedFold(view, pos) {
  const blocks = foldRange(view.state.doc, pos)
    .map((at) => view.nodeDOM(at))
    .filter((el) => el instanceof HTMLElement)
  const heading = view.state.doc.nodeAt(pos)
  if (heading == null) return false
  const collapsing = heading.attrs.collapsed !== true
  if (blocks.length === 0 || canAnimate(blocks[0]) === false) return toggleFold(view, pos)

  if (collapsing) {
    let pending = blocks.length
    blocks.forEach((el) => {
      const height = el.getBoundingClientRect().height
      el.style.overflow = 'hidden'
      el.animate(
        [
          { height: `${height}px`, opacity: 1 },
          { height: '0px', opacity: 0, marginTop: '0px', marginBottom: '0px', paddingTop: '0px', paddingBottom: '0px' },
        ],
        { duration: 200, easing: EASE },
      ).onfinish = () => {
        el.style.overflow = ''
        pending -= 1
        if (pending === 0) toggleFold(view, pos)
      }
    })
    return true
  }

  toggleFold(view, pos)
  foldRange(view.state.doc, pos)
    .map((at) => view.nodeDOM(at))
    .filter((el) => el instanceof HTMLElement)
    .forEach((el, index) => {
      const height = el.getBoundingClientRect().height
      el.style.overflow = 'hidden'
      el.animate([{ height: '0px', opacity: 0 }, { height: `${height}px`, opacity: 1 }], { duration: 220, delay: Math.min(index, 6) * 12, easing: EASE, fill: 'backwards' }).onfinish = () => {
        el.style.overflow = ''
      }
    })
  return true
}
