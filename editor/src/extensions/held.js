import { Extension } from '@tiptap/core'
import { Plugin, PluginKey } from '@tiptap/pm/state'
import { Decoration, DecorationSet } from '@tiptap/pm/view'

// While focus is in a popover (link field, color picker…) the browser stops
// painting the editor's selection. Holding it paints a stand-in so you can
// still see what you're about to change.
export const heldKey = new PluginKey('jot-held')

export function holdSelection(view, hold = true) {
  const { from, to } = view.state.selection
  view.dispatch(view.state.tr.setMeta(heldKey, hold && from !== to ? { from, to } : null))
}

export const HeldSelection = Extension.create({
  name: 'jotHeldSelection',
  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: heldKey,
        state: {
          init: () => null,
          apply(tr, value) {
            const meta = tr.getMeta(heldKey)
            if (meta !== undefined) return meta
            if (value == null || tr.docChanged === false) return value
            return { from: tr.mapping.map(value.from), to: tr.mapping.map(value.to) }
          },
        },
        props: {
          decorations(state) {
            const held = heldKey.getState(state)
            if (held == null) return null
            return DecorationSet.create(state.doc, [Decoration.inline(held.from, held.to, { class: 'jot-held' })])
          },
        },
      }),
    ]
  },
})
