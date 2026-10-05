import { Extension } from '@tiptap/core'
import { Plugin, PluginKey } from '@tiptap/pm/state'
import { Decoration, DecorationSet } from '@tiptap/pm/view'

// #tags stay plain text in the file (Obsidian reads them natively); the
// editor only paints them. Same rule as Obsidian: a tag needs at least one
// non-digit, so "#1" or "#2024" stay text.
export const TAG = /(^|[\s(])#([\p{L}\p{N}_][\p{L}\p{N}_/-]*)/gu

export const tagsKey = new PluginKey('jot-tags')

export function tagsIn(text) {
  const found = new Set()
  for (const match of text.matchAll(TAG)) {
    if (/\D/.test(match[2])) found.add(match[2].toLowerCase())
  }
  return [...found]
}

function decorate(doc) {
  const decorations = []
  doc.descendants((node, pos, parent) => {
    if (node.type.name === 'codeBlock') return false
    if (node.isText === false) return true
    if (node.marks.some((mark) => mark.type.name === 'code' || mark.type.name === 'link')) return false
    if (parent?.type.name === 'heading' && pos === 0) return false
    for (const match of node.text.matchAll(TAG)) {
      if (/\D/.test(match[2]) === false) continue
      const from = pos + match.index + match[1].length
      decorations.push(Decoration.inline(from, from + match[2].length + 1, { class: 'jot-tag', 'data-tag': match[2] }))
    }
    return false
  })
  return DecorationSet.create(doc, decorations)
}

export const Tags = Extension.create({
  name: 'jotTags',
  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: tagsKey,
        state: {
          init: (_config, state) => decorate(state.doc),
          apply: (tr, value) => (tr.docChanged ? decorate(tr.doc) : value),
        },
        props: {
          decorations: (state) => tagsKey.getState(state),
        },
      }),
    ]
  },
})
