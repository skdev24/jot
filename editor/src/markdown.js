import { createDocument } from '@tiptap/core'

// Notes are stored as Markdown. Parsing and writing go through TipTap's
// Markdown manager (marked + each extension's own syntax); this module tunes
// it for files people read by hand and adds the helpers the app needs.

const PUNCT = /[!-/:-@[-`{-~]/
const WORD = /[\p{L}\p{N}]/u

// TipTap escapes every *, _, [, ] and HTML-encodes & and <. That is safe but
// leaves "snake\_case" and "us &amp; them" in the file. Escape only what
// would actually change meaning when read back.
export function escapeText(text) {
  let out = ''
  const bracketed = /\[[^\]]*\]/.test(text)
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index]
    const next = text[index + 1] || ''
    const prev = text[index - 1] || ''
    if (char === '\\') out += PUNCT.test(next) ? '\\\\' : '\\'
    else if (char === '*' || char === '`') out += `\\${char}`
    else if (char === '_') out += WORD.test(prev) && WORD.test(next) ? '_' : '\\_'
    else if ((char === '~' || char === '=' || char === '+') && next === char) {
      out += `\\${char}\\${char}`
      index += 1
    } else if ((char === '[' || char === ']') && bracketed) out += `\\${char}`
    else if (char === '&' && /^&#?[a-z0-9]+;/i.test(text.slice(index))) out += '&amp;'
    else if (char === '<' && /[A-Za-z/!?]/.test(next)) out += '&lt;'
    else out += char
  }
  return out
}

export function tuneMarkdown(manager) {
  if (manager == null || manager.__jotTuned) return manager
  const codeTypes = manager.codeTypes
  manager.encodeTextForMarkdown = (text, node, parentNode) => {
    const inCode =
      (parentNode?.type != null && codeTypes?.has(parentNode.type)) ||
      (node?.marks || []).some((mark) => codeTypes?.has(typeof mark === 'string' ? mark : mark.type))
    return inCode ? text : escapeText(text)
  }
  manager.__jotTuned = true
  return manager
}

const LISTS = new Set(['bulletList', 'orderedList', 'taskList'])
const EMPHASIS = new Set(['bold', 'italic', 'strike', 'underline', 'highlight', 'textColor'])
const BARE = /^[\p{P}\p{S}\s]*$/u

// Shapes Markdown can't express are normalized before writing, so what's
// read back matches what was written:
// - two lists of the same kind side by side merge when re-read; join them now.
// - emphasis on bare punctuation (a bold ", ") can't be delimited; drop it.
export function normalizeForMarkdown(node) {
  if (node.type === 'text') {
    if (node.marks && BARE.test(node.text || '')) {
      const marks = node.marks.filter((mark) => EMPHASIS.has(mark.type) === false)
      return marks.length ? { ...node, marks } : { type: 'text', text: node.text }
    }
    return node
  }
  if (node.content == null) return node
  const isEmpty = (child) => child?.type === 'paragraph' && (child.content == null || child.content.length === 0)
  const isText = (child) => child?.type === 'paragraph'
  // Blank lines only survive between paragraphs; elsewhere they'd vanish on
  // the next read, so don't write them (keeps every save byte-stable).
  const children = node.type === 'doc'
    ? node.content.filter((child, index, all) => isEmpty(child) === false || (isText(all[index - 1]) && isText(all[index + 1])) || index === all.length - 1)
    : node.content
  const content = []
  for (const child of children.map(normalizeForMarkdown)) {
    const prev = content[content.length - 1]
    if (prev && LISTS.has(child.type) && prev.type === child.type) {
      content[content.length - 1] = { ...prev, content: [...(prev.content || []), ...(child.content || [])] }
    } else content.push(child)
  }
  return { ...node, content }
}

export function docToMarkdown(editor, doc = editor.state.doc) {
  const manager = tuneMarkdown(editor.markdown)
  return manager.serialize(normalizeForMarkdown(doc.toJSON())).replace(/\s*$/, '\n')
}

export function markdownToDoc(editor, markdown) {
  const manager = tuneMarkdown(editor.markdown)
  const json = manager.parse(markdown || '')
  return createDocument(json, editor.schema, editor.options.parseOptions)
}

export function sliceToMarkdown(editor, slice) {
  const manager = tuneMarkdown(editor.markdown)
  return manager.serialize({ type: 'doc', content: slice.content.toJSON() }).trim()
}

// ---------------------------------------------------------------------------
// Paste: plain text that looks like Markdown becomes blocks, unless the
// clipboard also carries real rich text (then the HTML is better).

export function looksLikeMarkdown(text) {
  return (
    /^\s*(#{1,6}\s|[-*+•]\s|\d+[.)]\s|>\s?|```|- \[[ xX]\]|<details)/m.test(text) ||
    /\*\*[^*]+\*\*|~~[^~]+~~|==[^=]+==|`[^`]+`|\[[^\]]+\]\([^)]+\)|\[\[[^\]]+\]\]|📅 \d{4}-\d{2}-\d{2}/u.test(text)
  )
}

const RICH_HTML = /<(ul|ol|li|h[1-6]|strong|b|em|i|a|blockquote|pre|table|mark|s|del|u)\b/i

export function preferMarkdown(text, html) {
  if (text === '' || looksLikeMarkdown(text) === false) return false
  if (html === '') return true
  if (html.includes('data-type="taskList"')) return false
  return RICH_HTML.test(html) === false
}
