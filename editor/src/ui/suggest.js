import { Extension } from '@tiptap/core'
import { PluginKey } from '@tiptap/pm/state'
import Suggestion, { exitSuggestion } from '@tiptap/suggestion'
import { createMenu } from './menu.js'
import { createSurface } from './surface.js'

// Ranks `text` against `query`: prefix > word start > in-order letters.
export function fuzzy(query, text) {
  const q = query.toLowerCase().trim()
  if (q === '') return 1
  const t = text.toLowerCase()
  if (t.startsWith(q)) return 100 - t.length / 100
  if (t.split(/[\s/_-]+/).some((word) => word.startsWith(q))) return 60 - t.length / 100
  const at = t.indexOf(q)
  if (at >= 0) return 40 - at / 10
  let i = 0
  for (const char of t) if (char === q[i]) i += 1
  return i === q.length ? 10 - t.length / 100 : 0
}

// A trigger character that opens a menu at the caret: "/" for blocks,
// "[[" for note links, "@" for dates, "#" for tags. Shares one look,
// one keyboard model and one animation.
export function suggestExtension({
  name,
  char,
  items,
  command,
  className = '',
  emptyLabel = 'No results',
  allowSpaces = false,
  minQueryLength = 0,
  placeholder = '',
  allow = () => true,
  priority = 1100,
  hideWhenEmpty = false,
}) {
  const key = new PluginKey(name)
  const extension = Extension.create({
    name,
    priority,
    addProseMirrorPlugins() {
      return [
        Suggestion({
          editor: this.editor,
          pluginKey: key,
          char,
          allowSpaces,
          minQueryLength,
          allowedPrefixes: [' ', ' ', '(', '\n'],
          decorationClass: 'jot-suggest',
          decorationContent: placeholder,
          allow: ({ editor, state, range }) => {
            if (editor.isEditable === false) return false
            const $from = state.doc.resolve(range.from)
            if ($from.parent.type.name === 'codeBlock') return false
            if ($from.marks().some((mark) => mark.type.name === 'code')) return false
            return allow({ editor, state, range })
          },
          items: ({ query, editor }) => items(query, editor),
          command: ({ editor, range, props }) => command({ editor, range, item: props }),
          render: () => {
            let menu
            let surface
            let latest
            let misses = 0
            let lastQuery = null
            const reference = () => ({
              getBoundingClientRect: () => latest?.decorationNode?.getBoundingClientRect() || latest?.clientRect?.() || new DOMRect(),
              contextElement: latest?.editor.view.dom,
            })
            return {
              onStart(props) {
                latest = props
                misses = 0
                lastQuery = props.query
                menu = createMenu({ className: `is-suggest ${className}`, emptyLabel, onChoose: (item) => latest.command(item) })
                const root = menu.root
                document.body.appendChild(root)
                // Only drop the element once this menu is over (a hidden-but-
                // live tag menu must stay mounted to show again).
                surface = createSurface(root, { placement: 'bottom-start', gap: 6, maxHeight: 300, onHidden: () => menu?.root !== root && root.remove() })
                menu.render(props.items)
                if (hideWhenEmpty === false || props.items.length) surface.show(reference())
              },
              onUpdate(props) {
                latest = props
                // Count keystrokes, not updates: items can arrive in a second
                // update for the same query.
                if (props.query !== lastQuery) misses = props.items.length === 0 ? misses + 1 : 0
                else if (props.items.length) misses = 0
                lastQuery = props.query
                menu.render(props.items)
                if (hideWhenEmpty && props.items.length === 0) surface.hide()
                else if (surface.isOpen) surface.place()
                else surface.show(reference())
                // A few keystrokes past "no results" means it wasn't a command.
                if (misses > 3) exitSuggestion(props.editor.view, key)
              },
              onKeyDown({ event }) {
                if (event.key === 'Escape') return surface?.isOpen === true
                if (menu == null || surface?.isOpen !== true) return false
                return menu.onKeyDown(event)
              },
              onExit() {
                const leaving = menu
                menu = null
                if (surface?.hide() !== true) leaving?.root.remove()
                surface = null
                latest = null
              },
            }
          },
        }),
      ]
    },
  })
  extension.key = key
  return extension
}

export function isSuggesting(state, extensions) {
  return extensions.some((extension) => extension.key.getState(state)?.active)
}
