import { Extension } from '@tiptap/core'
import { Plugin, PluginKey, TextSelection } from '@tiptap/pm/state'
import { Decoration, DecorationSet } from '@tiptap/pm/view'

export const findKey = new PluginKey('jot-find')

function matches(doc, query) {
  if (query.trim() === '') return []
  const found = []
  const needle = query.toLowerCase()
  doc.descendants((node, pos) => {
    if (node.isText === false) return
    const hay = node.text.toLowerCase()
    let index = 0
    while (index < hay.length) {
      const at = hay.indexOf(needle, index)
      if (at === -1) break
      found.push({ from: pos + at, to: pos + at + needle.length })
      index = at + needle.length
    }
  })
  return found
}

function findPlugin() {
  return new Plugin({
    key: findKey,
    state: {
      init: () => ({ query: '', index: 0, hits: [] }),
      apply(tr, value) {
        const next = tr.getMeta(findKey)
        if (next) return next
        if (tr.docChanged && value.query) {
          const hits = matches(tr.doc, value.query)
          return { ...value, hits, index: Math.min(value.index, Math.max(hits.length - 1, 0)) }
        }
        return value
      },
    },
    props: {
      decorations(state) {
        const value = findKey.getState(state)
        if (value == null || value.hits.length === 0) return null
        return DecorationSet.create(
          state.doc,
          value.hits.map((hit, index) =>
            Decoration.inline(hit.from, hit.to, {
              class: index === value.index ? 'find-hit is-current' : 'find-hit',
            }),
          ),
        )
      },
    },
  })
}

export const Find = Extension.create({
  name: 'jotFind',
  addProseMirrorPlugins() {
    return [findPlugin()]
  },
})

export function runFind(editor, query, delta = 0) {
  const hits = matches(editor.state.doc, query)
  let index = 0
  const current = findKey.getState(editor.state)
  if (current && current.query === query && hits.length) {
    index = (current.index + delta + hits.length) % hits.length
  }
  const tr = editor.state.tr.setMeta(findKey, { query, index, hits })
  if (hits[index]) {
    tr.setSelection(TextSelection.create(editor.state.doc, hits[index].from, hits[index].to))
    tr.scrollIntoView()
  }
  editor.view.dispatch(tr)
  return { count: hits.length, index: hits.length ? index + 1 : 0 }
}

export function clearFind(editor) {
  editor.view.dispatch(editor.state.tr.setMeta(findKey, { query: '', index: 0, hits: [] }))
}
