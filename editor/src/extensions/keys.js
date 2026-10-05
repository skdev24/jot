import { Extension, InputRule } from '@tiptap/core'
import { TextSelection } from '@tiptap/pm/state'
import { duplicateBlock, liftAtStart, moveBlock, toggleTodo } from '../blocks.js'

const LISTS = ['bulletList', 'orderedList', 'taskList']

// Backspace in an empty line that sits between two lists of the same kind
// removes the line and joins the lists, so they behave as one again.
function joinListsAround(editor) {
  const { state, view } = editor
  const { selection } = state
  if (selection.empty === false) return false
  const { $from } = selection
  if ($from.depth !== 1 || $from.parent.type.name !== 'paragraph' || $from.parent.content.size !== 0) return false
  const index = $from.index(0)
  const before = index > 0 ? state.doc.child(index - 1) : null
  const after = index < state.doc.childCount - 1 ? state.doc.child(index + 1) : null
  if (before == null || after == null || LISTS.includes(before.type.name) === false || before.type !== after.type) return false
  const start = $from.before(1)
  const tr = state.tr.delete(start, start + $from.parent.nodeSize)
  tr.join(start)
  // Caret at the end of the last item of the upper list.
  tr.setSelection(TextSelection.near(tr.doc.resolve(start - 1), -1))
  view.dispatch(tr.scrollIntoView())
  return true
}

export const JotKeys = Extension.create({
  name: 'jotKeys',
  priority: 1000,

  addOptions() {
    return { onLink: () => false }
  },

  addKeyboardShortcuts() {
    const editor = this.editor
    const inItem = () => (editor.isActive('taskItem') ? 'taskItem' : editor.isActive('listItem') ? 'listItem' : null)
    return {
      'Mod-Enter': () => toggleTodo(editor),
      'Mod-Shift-ArrowUp': () => moveBlock(editor, -1),
      'Mod-Shift-ArrowDown': () => moveBlock(editor, 1),
      'Mod-d': () => duplicateBlock(editor),
      'Mod-k': () => this.options.onLink(),
      Backspace: () => joinListsAround(editor) || liftAtStart(editor),
      Tab: () => {
        const type = inItem()
        if (type) return editor.commands.sinkListItem(type) || true
        // Code blocks indent themselves; elsewhere Tab must not leave the editor.
        return editor.isActive('codeBlock') === false
      },
      'Shift-Tab': () => {
        const type = inItem()
        if (type) return editor.commands.liftListItem(type) || true
        return editor.isActive('codeBlock') === false
      },
    }
  },

  addInputRules() {
    return [
      // "- [ ] " typed inside a fresh bullet becomes a to-do, not a nested list.
      new InputRule({
        find: /^\s*\[([ xX])?\]\s$/,
        handler: ({ state, range, chain }) => {
          const $from = state.doc.resolve(range.from)
          if ($from.depth < 2 || $from.node(-1).type.name !== 'listItem') return null
          const checked = /x/i.test(state.doc.textBetween(range.from, range.to))
          chain().deleteRange(range).liftListItem('listItem').toggleTaskList().updateAttributes('taskItem', { checked }).run()
        },
      }),
      // "> [!tip] " starts a callout, Obsidian style. "> " has already made a
      // quote by the time "[!tip] " is typed, so swap the quote for a callout.
      new InputRule({
        find: /^\[!(\w+)\]\s$/,
        handler: ({ state, range, match, chain }) => {
          const $from = state.doc.resolve(range.from)
          if ($from.depth < 2 || $from.node(-1).type.name !== 'blockquote') return null
          chain().deleteRange(range).lift('blockquote').setCallout(match[1].toLowerCase()).run()
        },
      }),
    ]
  },
})
