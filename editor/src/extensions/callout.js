import { Node, mergeAttributes } from '@tiptap/core'

// Callouts use Obsidian's syntax, so the same file reads well there:
//   > [!tip] Optional title
//   > Body text
// The kind picks the color. Unknown kinds are kept as written.
export const CALLOUTS = [
  { kind: 'note', title: 'Gray callout', color: 'gray' },
  { kind: 'info', title: 'Blue callout', color: 'blue' },
  { kind: 'tip', title: 'Green callout', color: 'green' },
  { kind: 'warning', title: 'Yellow callout', color: 'yellow' },
  { kind: 'danger', title: 'Red callout', color: 'red' },
  { kind: 'example', title: 'Purple callout', color: 'purple' },
]

const START = /^ {0,3}> ?\[!/m
const BLOCK = /^ {0,3}> ?\[!([\w-]+)\]([+-]?)[ \t]*([^\n]*)(?:\n|$)((?: {0,3}>[^\n]*(?:\n|$))*)/

export const Callout = Node.create({
  name: 'callout',
  group: 'block',
  content: 'block+',
  defining: true,

  addAttributes() {
    return {
      kind: {
        default: 'note',
        parseHTML: (element) => element.getAttribute('data-kind') || 'note',
        renderHTML: (attributes) => ({ 'data-kind': attributes.kind }),
      },
      // Obsidian's optional title and fold marker, kept so files round-trip.
      title: {
        default: '',
        parseHTML: (element) => element.getAttribute('data-title') || '',
        renderHTML: (attributes) => (attributes.title ? { 'data-title': attributes.title } : {}),
      },
      fold: {
        default: '',
        rendered: false,
      },
    }
  },

  parseHTML() {
    return [{ tag: 'div[data-callout]' }]
  },

  renderHTML({ HTMLAttributes }) {
    return ['div', mergeAttributes(HTMLAttributes, { 'data-callout': '' }), 0]
  },

  // The Obsidian title shows as a heading line above the body. It is kept
  // from the file but edited there, not here.
  addNodeView() {
    return ({ node }) => {
      let current = node
      const dom = document.createElement('div')
      dom.setAttribute('data-callout', '')
      const title = document.createElement('div')
      title.className = 'jot-callout-title'
      title.contentEditable = 'false'
      const body = document.createElement('div')
      body.className = 'jot-callout-body'
      dom.append(title, body)
      const paint = () => {
        dom.setAttribute('data-kind', current.attrs.kind)
        title.textContent = current.attrs.title || ''
        title.hidden = !current.attrs.title
      }
      paint()
      return {
        dom,
        contentDOM: body,
        update(next) {
          if (next.type !== current.type) return false
          current = next
          paint()
          return true
        },
        ignoreMutation: (mutation) => title.contains(mutation.target),
      }
    }
  },

  addCommands() {
    return {
      setCallout:
        (kind = 'note') =>
        ({ commands }) =>
          commands.wrapIn(this.name, { kind }),
      setCalloutKind:
        (kind) =>
        ({ commands }) =>
          commands.updateAttributes(this.name, { kind }),
      unsetCallout:
        () =>
        ({ commands }) =>
          commands.lift(this.name),
    }
  },

  markdownTokenizer: {
    name: 'callout',
    level: 'block',
    start: (src) => {
      const match = START.exec(src)
      return match ? match.index : -1
    },
    tokenize(src, _tokens, lexer) {
      const match = BLOCK.exec(src)
      if (match == null) return undefined
      const body = match[4]
        .split('\n')
        .map((line) => line.replace(/^ {0,3}> ?/, ''))
        .join('\n')
      return {
        type: 'callout',
        raw: match[0],
        kind: match[1].toLowerCase(),
        fold: match[2],
        title: match[3].trim(),
        tokens: lexer.blockTokens(body),
      }
    },
  },

  parseMarkdown(token, helpers) {
    const children = helpers.parseChildren(token.tokens || [])
    const content = children.length ? children : [helpers.createNode('paragraph', undefined, [])]
    return helpers.createNode('callout', { kind: token.kind, title: token.title || '', fold: token.fold || '' }, content)
  },

  renderMarkdown(node, helpers) {
    const head = `> [!${node.attrs?.kind || 'note'}]${node.attrs?.fold || ''}${node.attrs?.title ? ` ${node.attrs.title}` : ''}`
    const body = helpers.renderChildren(node.content || [], '\n\n')
    const lines = body.split('\n').map((line) => (line ? `> ${line}` : '>'))
    return [head, ...lines].join('\n')
  },
})
