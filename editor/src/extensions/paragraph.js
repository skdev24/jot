import Paragraph from '@tiptap/extension-paragraph'

// A paragraph whose text happens to start like Markdown block syntax
// ("# idea", "- not a list", "1. not ordered") must stay a paragraph after
// the file is read back, so those line starts are escaped.
const BLOCK_START = /^( {0,3})(#{1,6}(?=[ \t]|$)|[-+*](?=[ \t])|\d{1,9}(?=[.)][ \t])|>|`{3,}|~{3,}|(?:[-*_][ \t]*){3,}$|=+[ \t]*$|<(?=[A-Za-z/!?]))/

export function escapeLineStart(line) {
  const match = BLOCK_START.exec(line)
  if (match == null) return line
  const [whole, indent, marker] = match
  if (/^\d/.test(marker)) return `${indent}${marker}\\${line.slice(whole.length)}`
  if (marker.startsWith('<')) return line
  return `${indent}\\${line.slice(indent.length)}`
}

export const JotParagraph = Paragraph.extend({
  renderMarkdown(node, helpers, ctx) {
    const out = this.parent(node, helpers, ctx)
    if (!out) return out
    return out.split('\n').map(escapeLineStart).join('\n')
  },
})
