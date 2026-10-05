import { Details as BaseDetails, DetailsContent as BaseContent, DetailsSummary as BaseSummary } from '@tiptap/extension-details'

// Toggle blocks, stored as plain HTML that GitHub and Obsidian both render:
//   <details>
//   <summary>Title</summary>
//
//   Body markdown
//
//   </details>
// `open` is persisted so a toggle stays the way you left it.

const OPEN = /^ {0,3}<details(\s+open)?\s*>[ \t]*\n?/i
const SUMMARY = /^\s*<summary>([\s\S]*?)<\/summary>[ \t]*\n?/i

// Finds the matching </details>, allowing nested toggles.
function closingIndex(src, from) {
  const tag = /<\/?details\b[^>]*>/gi
  tag.lastIndex = from
  let depth = 1
  for (let match = tag.exec(src); match; match = tag.exec(src)) {
    depth += match[0][1] === '/' ? -1 : 1
    if (depth === 0) return { start: match.index, end: match.index + match[0].length }
  }
  return null
}

export const Details = BaseDetails.extend({
  markdownTokenizer: {
    name: 'details',
    level: 'block',
    start: (src) => {
      const index = src.search(/^ {0,3}<details[\s>]/im)
      return index < 0 ? undefined : index
    },
    tokenize(src, _tokens, lexer) {
      const open = OPEN.exec(src)
      if (open == null) return undefined
      const close = closingIndex(src, open[0].length)
      if (close == null) return undefined
      let inner = src.slice(open[0].length, close.start)
      let summary = ''
      const head = SUMMARY.exec(inner)
      if (head) {
        summary = head[1].trim()
        inner = inner.slice(head[0].length)
      }
      const rest = src.slice(close.end).match(/^[ \t]*\n?/)[0]
      return {
        type: 'details',
        raw: src.slice(0, close.end) + rest,
        open: Boolean(open[1]),
        summaryTokens: lexer.inlineTokens(summary),
        tokens: lexer.blockTokens(inner.replace(/^\n+|\n+$/g, '')),
      }
    },
  },

  parseMarkdown(token, helpers) {
    const body = helpers.parseChildren(token.tokens || [])
    return helpers.createNode('details', { open: token.open }, [
      helpers.createNode('detailsSummary', undefined, helpers.parseInline(token.summaryTokens || [])),
      helpers.createNode('detailsContent', undefined, body.length ? body : [helpers.createNode('paragraph', undefined, [])]),
    ])
  },

  renderMarkdown(node, helpers) {
    const [summary, content] = node.content || []
    const title = summary ? helpers.renderChildren(summary.content || []) : ''
    const body = content ? helpers.renderChildren(content.content || [], '\n\n') : ''
    return `<details${node.attrs?.open ? ' open' : ''}>\n<summary>${title}</summary>\n\n${body}\n\n</details>`
  },
}).configure({ persist: true, HTMLAttributes: { class: 'jot-toggle' } })

// Children are written by the parent; these only exist so the generic
// `:::block` fallback never kicks in for them.
export const DetailsSummary = BaseSummary.extend({
  renderMarkdown: (node, helpers) => helpers.renderChildren(node.content || []),
})

export const DetailsContent = BaseContent.extend({
  renderMarkdown: (node, helpers) => helpers.renderChildren(node.content || [], '\n\n'),
})
