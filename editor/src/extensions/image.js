import Image from '@tiptap/extension-image'

// Images live next to the notes (vault/assets/…) and are written with
// relative paths. The web view can't read the vault directly, so local paths
// are served through Swift's jot-asset:// scheme. Width uses Obsidian's
// `![alt|320](assets/shot.png)` convention.

const SCHEME = 'jot-asset:///'
const MIN_WIDTH = 80

export function displaySrc(src) {
  if (!src) return ''
  if (/^[a-z][a-z0-9+.-]*:/i.test(src) || src.startsWith('//')) return src
  return SCHEME + src.split('/').map(encodeURIComponent).join('/')
}

function storedSrc(src) {
  if (!src) return ''
  if (src.startsWith(SCHEME)) return src.slice(SCHEME.length).split('/').map(decodeURIComponent).join('/')
  return src
}

function splitAlt(text = '') {
  const match = /^(.*?)\|(\d+)(?:x\d+)?$/.exec(text)
  return match ? { alt: match[1], width: Number(match[2]) } : { alt: text, width: null }
}

function markdownSrc(src) {
  return /[\s()<>]/.test(src) ? `<${src}>` : src
}

export const JotImage = Image.extend({
  draggable: true,

  addAttributes() {
    return {
      ...this.parent?.(),
      src: {
        default: null,
        parseHTML: (element) => storedSrc(element.getAttribute('src')),
        renderHTML: (attributes) => ({ src: displaySrc(attributes.src) }),
      },
      width: {
        default: null,
        parseHTML: (element) => {
          const value = Number.parseInt(element.getAttribute('width') || element.style.width, 10)
          return Number.isFinite(value) ? value : null
        },
        renderHTML: (attributes) => (attributes.width ? { width: attributes.width } : {}),
      },
    }
  },

  parseMarkdown(token, helpers) {
    const { alt, width } = splitAlt(token.text)
    return helpers.createNode('image', { src: token.href, title: token.title || null, alt, width })
  },

  renderMarkdown(node) {
    const { src = '', alt = '', title, width } = node.attrs || {}
    const label = `${alt || ''}${width ? `|${width}` : ''}`
    return `![${label}](${markdownSrc(src || '')}${title ? ` "${title}"` : ''})`
  },

  // Resizable figure: drag either edge. Width is committed on release so a
  // drag is one undo step.
  addNodeView() {
    return ({ node, getPos, editor }) => {
      let current = node
      const dom = document.createElement('figure')
      dom.className = 'jot-image'
      const img = document.createElement('img')
      img.draggable = false
      const left = document.createElement('span')
      left.className = 'jot-image-grip is-left'
      const right = document.createElement('span')
      right.className = 'jot-image-grip is-right'
      dom.append(img, left, right)

      const paint = () => {
        img.src = displaySrc(current.attrs.src)
        img.alt = current.attrs.alt || ''
        img.style.width = current.attrs.width ? `${current.attrs.width}px` : ''
      }
      paint()

      const startResize = (event, side) => {
        event.preventDefault()
        event.stopPropagation()
        const startX = event.clientX
        const startWidth = img.getBoundingClientRect().width
        const max = editor.view.dom.getBoundingClientRect().width
        dom.classList.add('is-resizing')
        const move = (moveEvent) => {
          const delta = (moveEvent.clientX - startX) * (side === 'left' ? -1 : 1)
          img.style.width = `${Math.round(Math.min(max, Math.max(MIN_WIDTH, startWidth + delta)))}px`
        }
        const up = () => {
          window.removeEventListener('mousemove', move)
          window.removeEventListener('mouseup', up)
          dom.classList.remove('is-resizing')
          const width = Math.round(img.getBoundingClientRect().width)
          const pos = getPos()
          if (typeof pos !== 'number') return
          editor.view.dispatch(editor.state.tr.setNodeMarkup(pos, undefined, { ...current.attrs, width: width >= max - 1 ? null : width }))
        }
        window.addEventListener('mousemove', move)
        window.addEventListener('mouseup', up)
      }
      left.addEventListener('mousedown', (event) => startResize(event, 'left'))
      right.addEventListener('mousedown', (event) => startResize(event, 'right'))

      return {
        dom,
        update(next) {
          if (next.type !== current.type) return false
          current = next
          paint()
          return true
        },
        selectNode: () => dom.classList.add('ProseMirror-selectednode'),
        deselectNode: () => dom.classList.remove('ProseMirror-selectednode'),
        stopEvent: (event) => event.target === left || event.target === right,
        ignoreMutation: () => true,
      }
    }
  },
}).configure({ inline: false, allowBase64: false })
