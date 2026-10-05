import { TURN_INTO } from '../blocks.js'
import { fuzzy, suggestExtension } from './suggest.js'

const BASIC = 'Basic blocks'
const INSERT = 'Insert'

export const BLOCKS = [
  { id: 'text', section: BASIC, title: 'Text', icon: 'text', keys: 'paragraph plain p' },
  { id: 'todo', section: BASIC, title: 'To-do list', icon: 'todo', hint: '[]', keys: 'task checkbox check todo' },
  { id: 'h1', section: BASIC, title: 'Heading 1', icon: 'h1', hint: '#', keys: 'title big h1' },
  { id: 'h2', section: BASIC, title: 'Heading 2', icon: 'h2', hint: '##', keys: 'subtitle medium h2' },
  { id: 'h3', section: BASIC, title: 'Heading 3', icon: 'h3', hint: '###', keys: 'small h3' },
  { id: 'bullet', section: BASIC, title: 'Bulleted list', icon: 'bullet', hint: '-', keys: 'ul unordered list' },
  { id: 'numbered', section: BASIC, title: 'Numbered list', icon: 'numbered', hint: '1.', keys: 'ol ordered list' },
  { id: 'toggle', section: BASIC, title: 'Toggle', icon: 'toggle', keys: 'details collapse fold expand' },
  { id: 'quote', section: BASIC, title: 'Quote', icon: 'quote', hint: '>', keys: 'blockquote citation' },
  { id: 'callout', section: BASIC, title: 'Callout', icon: 'callout', keys: 'note info tip warning box highlight' },
  { id: 'code', section: BASIC, title: 'Code', icon: 'code', hint: '```', keys: 'snippet pre codeblock' },
  { id: 'divider', section: BASIC, title: 'Divider', icon: 'divider', hint: '---', keys: 'hr rule line separator' },
]

const INSERTS = [
  { id: 'date', section: INSERT, title: 'Date or reminder', icon: 'calendar', hint: '@', keys: 'due remind today tomorrow time deadline' },
  { id: 'note', section: INSERT, title: 'Link to note', icon: 'note', hint: '[[', keys: 'page wiki reference backlink' },
  { id: 'image', section: INSERT, title: 'Image', icon: 'image', keys: 'picture photo screenshot png jpg' },
]

const ALL = [...BLOCKS, ...INSERTS]

function search(query) {
  const q = query.toLowerCase().trim()
  // Titles match loosely; keywords only by word start ("tog" ≠ "photo").
  const byKeys = (item) => (q && item.keys.split(' ').some((word) => word.startsWith(q)) ? 50 : 0)
  return ALL.map((item) => ({ item, rank: Math.max(fuzzy(query, item.title), byKeys(item)) }))
    .filter((row) => row.rank > 0)
    .sort((a, b) => (query ? b.rank - a.rank : 0))
    .map((row) => (query ? { ...row.item, section: 'Results' } : row.item))
}

// `actions` comes from the app: the inserts that need other UI.
export function createSlash(actions) {
  return suggestExtension({
    name: 'jotSlash',
    char: '/',
    placeholder: 'Filter…',
    emptyLabel: 'No matching blocks',
    items: (query) => search(query),
    command: ({ editor, range, item }) => {
      editor.chain().deleteRange(range).run()
      if (item.id === 'divider') return editor.chain().setHorizontalRule().run()
      if (item.id === 'toggle') return editor.chain().clearNodes().setDetails().run()
      if (item.id === 'callout') return editor.chain().clearNodes().setCallout('note').run()
      if (item.id === 'date') return editor.chain().insertContent('@').run()
      if (item.id === 'note') return editor.chain().insertContent('[[').run()
      if (item.id === 'image') return actions.pickImage()
      // Turning a to-do into a to-do (etc.) would toggle it off; keep it.
      if ((item.id === 'todo' && editor.isActive('taskItem')) || (item.id === 'bullet' && editor.isActive('bulletList'))) return true
      return TURN_INTO[item.id]?.(editor.chain()).run()
    },
  })
}
