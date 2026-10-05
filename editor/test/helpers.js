import { GlobalRegistrator } from '@happy-dom/global-registrator'

GlobalRegistrator.register()

const { Editor } = await import('@tiptap/core')
const { jotExtensions } = await import('../src/extensions/index.js')
const markdown = await import('../src/markdown.js')

export const { docToMarkdown, markdownToDoc, escapeText } = markdown

// A headless editor with the app's exact schema.
export function makeEditor(content = '') {
  const editor = new Editor({ extensions: jotExtensions(), content: '' })
  if (content) setMarkdown(editor, content)
  return editor
}

export function setMarkdown(editor, text) {
  const doc = markdownToDoc(editor, text)
  editor.commands.setContent(doc.toJSON(), { emitUpdate: false })
}

export function roundTrip(text) {
  const editor = makeEditor(text)
  const out = docToMarkdown(editor)
  editor.destroy()
  return out
}

export function json(text) {
  const editor = makeEditor(text)
  const out = editor.getJSON()
  editor.destroy()
  return out
}
