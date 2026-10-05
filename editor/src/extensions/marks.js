import { Mark, mergeAttributes } from '@tiptap/core'
import Highlight from '@tiptap/extension-highlight'
import Underline from '@tiptap/extension-underline'

// Notion's palette. Stored by name, so the theme decides the exact shade and
// other apps degrade to plain (or default-highlighted) text.
export const COLORS = ['gray', 'brown', 'orange', 'yellow', 'green', 'blue', 'purple', 'pink', 'red']

const isColor = (value) => COLORS.includes(value)

// Inline HTML with one known tag, e.g. <span data-color="red">text</span>.
// Nested tags of the same name are not supported (and never written).
function htmlMarkTokenizer(name, tag) {
  const pattern = new RegExp(`^<${tag}\\s+data-color="([a-z]+)"\\s*>([\\s\\S]*?)<\\/${tag}>`)
  return {
    name,
    level: 'inline',
    start: (src) => {
      const index = src.indexOf(`<${tag} data-color=`)
      return index < 0 ? undefined : index
    },
    tokenize(src, _tokens, lexer) {
      const match = pattern.exec(src)
      if (match == null) return undefined
      return { type: name, raw: match[0], color: match[1], tokens: lexer.inlineTokens(match[2]) }
    },
  }
}

export const TextColor = Mark.create({
  name: 'textColor',

  addAttributes() {
    return {
      color: {
        default: null,
        parseHTML: (element) => element.getAttribute('data-color'),
        renderHTML: (attributes) => (attributes.color ? { 'data-color': attributes.color } : {}),
      },
    }
  },

  parseHTML() {
    return [{ tag: 'span[data-color]', getAttrs: (element) => (isColor(element.getAttribute('data-color')) ? null : false) }]
  },

  renderHTML({ HTMLAttributes }) {
    return ['span', mergeAttributes(HTMLAttributes, { class: 'jot-color' }), 0]
  },

  addCommands() {
    return {
      setTextColor:
        (color) =>
        ({ commands }) =>
          commands.setMark(this.name, { color }),
      unsetTextColor:
        () =>
        ({ commands }) =>
          commands.unsetMark(this.name),
    }
  },

  markdownTokenizer: htmlMarkTokenizer('textColor', 'span'),

  parseMarkdown(token, helpers) {
    return helpers.applyMark('textColor', helpers.parseInline(token.tokens || []), { color: token.color })
  },

  renderMarkdown(node, helpers) {
    const color = node.attrs?.color
    const inner = helpers.renderChildren(node)
    return color ? `<span data-color="${color}">${inner}</span>` : inner
  },
})

// ==text== for the default yellow; <mark data-color="blue">text</mark> for the rest.
const MARK_TAG = /^<mark\s+data-color="([a-z]+)"\s*>([\s\S]*?)<\/mark>/
const MARK_EQ = /^==([^=\n]+)==/

export const ColorHighlight = Highlight.extend({
  addAttributes() {
    return {
      color: {
        default: null,
        parseHTML: (element) => element.getAttribute('data-color'),
        renderHTML: (attributes) => (attributes.color ? { 'data-color': attributes.color } : {}),
      },
    }
  },

  markdownTokenizer: {
    name: 'highlight',
    level: 'inline',
    start: (src) => {
      const candidates = [src.indexOf('=='), src.indexOf('<mark data-color=')].filter((index) => index >= 0)
      return candidates.length ? Math.min(...candidates) : undefined
    },
    tokenize(src, _tokens, lexer) {
      const tag = MARK_TAG.exec(src)
      if (tag) return { type: 'highlight', raw: tag[0], color: tag[1], tokens: lexer.inlineTokens(tag[2]) }
      const eq = MARK_EQ.exec(src)
      if (eq) return { type: 'highlight', raw: eq[0], color: null, tokens: lexer.inlineTokens(eq[1]) }
      return undefined
    },
  },

  parseMarkdown(token, helpers) {
    return helpers.applyMark('highlight', helpers.parseInline(token.tokens || []), token.color ? { color: token.color } : undefined)
  },

  renderMarkdown(node, helpers) {
    const inner = helpers.renderChildren(node)
    const color = node.attrs?.color
    return color && color !== 'yellow' ? `<mark data-color="${color}">${inner}</mark>` : `==${inner}==`
  },
}).configure({ multicolor: true })

// TipTap writes underline as ++text++, which nothing else understands.
// Write <u>, and still read ++ for files from older builds.
export const JotUnderline = Underline.extend({
  markdownTokenizer: {
    name: 'underline',
    level: 'inline',
    start: (src) => {
      const candidates = [src.indexOf('<u>'), src.indexOf('++')].filter((index) => index >= 0)
      return candidates.length ? Math.min(...candidates) : undefined
    },
    tokenize(src, _tokens, lexer) {
      const match = /^<u>([\s\S]*?)<\/u>/.exec(src) || /^\+\+([^+\n]+)\+\+/.exec(src)
      if (match == null) return undefined
      return { type: 'underline', raw: match[0], tokens: lexer.inlineTokens(match[1]) }
    },
  },
  renderMarkdown(node, helpers) {
    return `<u>${helpers.renderChildren(node)}</u>`
  },
})
