import { Extension } from '@tiptap/core'
import { Plugin, PluginKey, TextSelection } from '@tiptap/pm/state'
import { Decoration, DecorationSet } from '@tiptap/pm/view'

export const foldKey = new PluginKey('jot-fold')

// Collapsible headings. `collapsed` lives on the heading node and a
// decoration hides the blocks under it until the next heading of the same or
// higher rank. Markdown has no place for it, so the app stores which headings
// are folded next to the note (see foldedHeadings / applyFolds).
function toggleWidget(collapsed) {
  return () => {
    const button = document.createElement('span')
    button.className = collapsed ? 'jot-fold is-collapsed' : 'jot-fold'
    button.contentEditable = 'false'
    button.title = collapsed ? 'Expand section' : 'Collapse section'
    return button
  }
}

function folds(doc) {
  const decorations = []
  let hideBelow = 0
  doc.forEach((node, pos) => {
    const level = node.type.name === 'heading' ? node.attrs.level : 0
    if (level && hideBelow === 0 && node.content.size > 0) {
      // Chevron after the heading text: on hover, or always when collapsed.
      decorations.push(
        Decoration.widget(pos + node.nodeSize - 1, toggleWidget(node.attrs.collapsed), {
          side: 1,
          ignoreSelection: true,
          key: `fold-${node.attrs.collapsed ? 1 : 0}`,
          heading: pos,
        }),
      )
    }
    if (hideBelow && level && level <= hideBelow) hideBelow = 0
    if (hideBelow) {
      decorations.push(Decoration.node(pos, pos + node.nodeSize, { class: 'is-folded' }, { folded: true }))
      return
    }
    if (level && node.attrs.collapsed) {
      hideBelow = level
      decorations.push(Decoration.node(pos, pos + node.nodeSize, { class: 'is-fold-head' }))
    }
  })
  return DecorationSet.create(doc, decorations)
}

function foldEnd(doc, headingPos, level) {
  let end = doc.content.size
  doc.forEach((node, pos) => {
    if (pos <= headingPos || end !== doc.content.size) return
    if (node.type.name === 'heading' && node.attrs.level <= level) end = pos
  })
  return end
}

// Top-level positions of the blocks a heading at `pos` folds away.
export function foldRange(doc, pos) {
  const heading = doc.nodeAt(pos)
  if (heading == null || heading.type.name !== 'heading') return []
  const end = foldEnd(doc, pos, heading.attrs.level)
  const out = []
  doc.forEach((_node, at) => {
    if (at > pos && at < end) out.push(at)
  })
  return out
}

export function foldedHeadings(doc) {
  const out = []
  doc.forEach((node) => {
    if (node.type.name === 'heading' && node.attrs.collapsed) out.push(node.textContent)
  })
  return out
}

// Re-fold headings by their text after the note is read from Markdown.
export function applyFolds(state, titles) {
  if (!titles || titles.length === 0) return state
  const wanted = new Set(titles)
  const tr = state.tr
  state.doc.forEach((node, pos) => {
    if (node.type.name === 'heading' && wanted.has(node.textContent)) tr.setNodeMarkup(pos, undefined, { ...node.attrs, collapsed: true })
  })
  return tr.docChanged ? state.apply(tr.setMeta('addToHistory', false)) : state
}

export function toggleFold(view, pos) {
  const node = view.state.doc.nodeAt(pos)
  if (node == null || node.type.name !== 'heading') return false
  const collapsing = !node.attrs.collapsed
  const tr = view.state.tr.setNodeMarkup(pos, undefined, { ...node.attrs, collapsed: collapsing })
  // Don't leave the caret inside text that's about to disappear.
  const sectionEnd = collapsing ? foldEnd(view.state.doc, pos, node.attrs.level) : pos
  if (collapsing && view.state.selection.from > pos + node.nodeSize && view.state.selection.from < sectionEnd) {
    tr.setSelection(TextSelection.create(tr.doc, pos + node.nodeSize - 1))
  }
  view.dispatch(tr)
  return true
}

function headingPosFromToggle(view, event) {
  const toggle = event.target.closest?.('.jot-fold')
  if (toggle == null) return null
  const heading = toggle.closest('h1, h2, h3, h4, h5, h6')
  if (heading == null) return null
  return view.posAtDOM(heading, 0) - 1
}

export const Fold = Extension.create({
  name: 'jotFold',
  addOptions() {
    return { onToggle: toggleFold }
  },
  addGlobalAttributes() {
    return [
      {
        types: ['heading'],
        attributes: {
          collapsed: {
            default: false,
            keepOnSplit: false,
            parseHTML: (element) => element.getAttribute('data-collapsed') === 'true',
            renderHTML: (attributes) => (attributes.collapsed ? { 'data-collapsed': 'true' } : {}),
          },
        },
      },
    ]
  },
  addProseMirrorPlugins() {
    const onToggle = this.options.onToggle
    return [
      new Plugin({
        key: foldKey,
        state: {
          init: (_config, state) => folds(state.doc),
          apply: (tr, value) => (tr.docChanged ? folds(tr.doc) : value),
        },
        props: {
          decorations: (state) => foldKey.getState(state),
          handleDOMEvents: {
            mousedown(view, event) {
              const pos = headingPosFromToggle(view, event)
              if (pos == null) return false
              event.preventDefault()
              return onToggle(view, pos)
            },
          },
        },
        // A caret that lands inside a folded section unfolds it.
        appendTransaction(transactions, _old, state) {
          if (transactions.some((tr) => tr.selectionSet) === false) return null
          const { $from } = state.selection
          if ($from.depth === 0) return null
          const top = $from.before(1)
          if (foldKey.getState(state).find(top, top + 1, (spec) => spec.folded).length === 0) return null
          let owner = null
          state.doc.forEach((node, pos) => {
            if (pos >= top || node.type.name !== 'heading') return
            if (owner && node.attrs.level <= owner.node.attrs.level) owner = null
            if (owner == null && node.attrs.collapsed) owner = { node, pos }
          })
          if (owner == null) return null
          return state.tr.setNodeMarkup(owner.pos, undefined, { ...owner.node.attrs, collapsed: false })
        },
      }),
    ]
  },
})
