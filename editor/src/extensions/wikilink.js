import { Node } from '@tiptap/core'

// [[Note title]] links between notes. Same syntax as Obsidian, including the
// optional alias: [[Note title|shown text]].

const PATTERN = /^\[\[([^\]|\n]+?)(?:\|([^\]\n]+))?\]\]/

export const WikiLink = Node.create({
  name: 'wikiLink',
  group: 'inline',
  inline: true,
  atom: true,
  selectable: true,

  addAttributes() {
    return {
      title: { default: '', parseHTML: (element) => element.getAttribute('data-title') || element.textContent },
      alias: { default: null, parseHTML: (element) => element.getAttribute('data-alias') },
    }
  },

  parseHTML() {
    return [{ tag: 'a[data-wiki]' }]
  },

  renderHTML({ node }) {
    const attrs = { 'data-wiki': '', 'data-title': node.attrs.title, class: 'jot-wiki' }
    if (node.attrs.alias) attrs['data-alias'] = node.attrs.alias
    return ['a', attrs, node.attrs.alias || node.attrs.title]
  },

  renderText({ node }) {
    return `[[${node.attrs.title}${node.attrs.alias ? `|${node.attrs.alias}` : ''}]]`
  },

  markdownTokenizer: {
    name: 'wikiLink',
    level: 'inline',
    start: (src) => {
      const index = src.indexOf('[[')
      return index < 0 ? undefined : index
    },
    tokenize(src) {
      const match = PATTERN.exec(src)
      if (match == null) return undefined
      return { type: 'wikiLink', raw: match[0], title: match[1].trim(), alias: match[2]?.trim() || null }
    },
  },

  parseMarkdown(token, helpers) {
    return helpers.createNode('wikiLink', { title: token.title, alias: token.alias })
  },

  renderMarkdown(node) {
    return `[[${node.attrs?.title}${node.attrs?.alias ? `|${node.attrs.alias}` : ''}]]`
  },
})
