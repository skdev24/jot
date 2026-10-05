import CodeBlockLowlight from '@tiptap/extension-code-block-lowlight'
import { common, createLowlight } from 'lowlight'

export const lowlight = createLowlight(common)

// Languages offered in the picker; anything lowlight knows still highlights.
export const LANGUAGES = [
  ['', 'Plain text'],
  ['bash', 'Shell'],
  ['c', 'C'],
  ['cpp', 'C++'],
  ['csharp', 'C#'],
  ['css', 'CSS'],
  ['diff', 'Diff'],
  ['go', 'Go'],
  ['java', 'Java'],
  ['javascript', 'JavaScript'],
  ['json', 'JSON'],
  ['kotlin', 'Kotlin'],
  ['markdown', 'Markdown'],
  ['php', 'PHP'],
  ['python', 'Python'],
  ['ruby', 'Ruby'],
  ['rust', 'Rust'],
  ['sql', 'SQL'],
  ['swift', 'Swift'],
  ['typescript', 'TypeScript'],
  ['xml', 'HTML / XML'],
  ['yaml', 'YAML'],
]

const ALIASES = { js: 'javascript', ts: 'typescript', sh: 'bash', zsh: 'bash', shell: 'bash', html: 'xml', yml: 'yaml', py: 'python', rb: 'ruby', md: 'markdown' }

export function languageLabel(language) {
  const key = ALIASES[language] || language || ''
  return LANGUAGES.find(([id]) => id === key)?.[1] || language || 'Plain text'
}

// The header's buttons only announce intent; the UI layer owns the picker
// and the clipboard (the page has no clipboard access of its own).
function announce(dom, type, detail) {
  dom.dispatchEvent(new CustomEvent(type, { bubbles: true, detail }))
}

export const CodeBlock = CodeBlockLowlight.extend({
  addNodeView() {
    return ({ node, getPos }) => {
      let current = node
      const dom = document.createElement('div')
      dom.className = 'jot-code'
      const head = document.createElement('div')
      head.className = 'jot-code-head'
      head.contentEditable = 'false'
      const lang = document.createElement('button')
      lang.type = 'button'
      lang.className = 'jot-code-lang'
      const copy = document.createElement('button')
      copy.type = 'button'
      copy.className = 'jot-code-copy'
      copy.textContent = 'Copy'
      head.append(lang, copy)
      const pre = document.createElement('pre')
      const code = document.createElement('code')
      pre.append(code)
      dom.append(head, pre)

      const paint = () => {
        lang.textContent = languageLabel(current.attrs.language)
        code.className = current.attrs.language ? `language-${current.attrs.language}` : ''
      }
      paint()

      lang.addEventListener('mousedown', (event) => {
        event.preventDefault()
        announce(dom, 'jot:code-language', { pos: getPos(), anchor: lang, language: current.attrs.language || '' })
      })
      copy.addEventListener('mousedown', (event) => {
        event.preventDefault()
        announce(dom, 'jot:copy', { text: current.textContent })
        copy.textContent = 'Copied'
        copy.classList.add('is-done')
        setTimeout(() => {
          copy.textContent = 'Copy'
          copy.classList.remove('is-done')
        }, 1200)
      })

      return {
        dom,
        contentDOM: code,
        update(next) {
          if (next.type !== current.type) return false
          current = next
          paint()
          return true
        },
        stopEvent: (event) => head.contains(event.target),
        ignoreMutation: (mutation) => head.contains(mutation.target),
      }
    }
  },
}).configure({ lowlight, defaultLanguage: null, enableTabIndentation: true, tabSize: 2 })
