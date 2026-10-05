import { fuzzy, suggestExtension } from './suggest.js'

// [[ — link another note. Titles come from the app's note index.
export function createWikiSuggest(index) {
  return suggestExtension({
    name: 'jotWiki',
    char: '[[',
    allowSpaces: true,
    placeholder: 'Note title',
    className: 'is-notes',
    items: (query) => {
      const q = query.replace(/\]+$/, '')
      const notes = index
        .notes()
        .map((note) => ({ note, rank: fuzzy(q, note.title) }))
        .filter((row) => row.rank > 0)
        .sort((a, b) => b.rank - a.rank)
        .slice(0, 8)
        .map(({ note }) => ({ id: note.id, section: 'Notes', icon: 'note', title: note.title }))
      const exact = notes.some((item) => item.title.toLowerCase() === q.trim().toLowerCase())
      if (q.trim() && exact === false) notes.push({ id: 'new', section: 'New', icon: 'plus', title: q.trim(), detail: 'Create note' })
      return notes
    },
    command: ({ editor, range, item }) => {
      editor.chain().deleteRange(range).insertContent([{ type: 'wikiLink', attrs: { title: item.title } }, { type: 'text', text: ' ' }]).run()
    },
  })
}

// # — reuse tags you already have, across all notes.
export function createTagSuggest(index) {
  return suggestExtension({
    name: 'jotTagSuggest',
    char: '#',
    minQueryLength: 1,
    className: 'is-tags',
    priority: 1050,
    hideWhenEmpty: true,
    // "# " at the start of a line is a heading, not a tag.
    items: (query) => {
      if (/^\d+$/.test(query)) return []
      return index
        .tags()
        .map((tag) => ({ tag, rank: fuzzy(query, tag) }))
        .filter((row) => row.rank > 0 && row.tag !== query.toLowerCase())
        .sort((a, b) => b.rank - a.rank)
        .slice(0, 6)
        .map(({ tag }) => ({ id: tag, section: 'Tags', icon: 'tag', title: `#${tag}` }))
    },
    command: ({ editor, range, item }) => {
      editor.chain().deleteRange(range).insertContent(`${item.title} `).run()
    },
  })
}
