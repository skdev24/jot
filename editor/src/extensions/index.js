import StarterKit from '@tiptap/starter-kit'
import HardBreak from '@tiptap/extension-hard-break'
import { TaskItem, TaskList } from '@tiptap/extension-list'
import Typography from '@tiptap/extension-typography'
import { Markdown } from '@tiptap/markdown'
import { Callout } from './callout.js'
import { CodeBlock } from './codeblock.js'
import { DateChip } from './date.js'
import { Details, DetailsContent, DetailsSummary } from './details.js'
import { Fold } from './fold.js'
import { JotImage } from './image.js'
import { JotKeys } from './keys.js'
import { ColorHighlight, JotUnderline, TextColor } from './marks.js'
import { JotParagraph } from './paragraph.js'
import { Tags } from './tags.js'
import { WikiLink } from './wikilink.js'

// The document schema and its Markdown format. Shared by the app and the
// tests, so it must not depend on any UI.
export function jotExtensions({ onLink, onFold } = {}) {
  return [
    StarterKit.configure({
      paragraph: false,
      hardBreak: false,
      underline: false,
      codeBlock: false,
      heading: { levels: [1, 2, 3, 4, 5, 6] },
      link: { openOnClick: false, autolink: true, linkOnPaste: true, defaultProtocol: 'https' },
      dropcursor: { color: 'var(--accent)', width: 2 },
      trailingNode: { node: 'paragraph' },
    }),
    JotParagraph,
    // "\" line ends survive editors that strip trailing spaces; "  " doesn't.
    HardBreak.extend({ renderMarkdown: () => '\\\n' }),
    JotUnderline,
    CodeBlock,
    TaskList,
    TaskItem.configure({ nested: true }),
    ColorHighlight,
    TextColor,
    Typography.configure({ oneHalf: false, oneQuarter: false, threeQuarters: false, superscriptTwo: false, superscriptThree: false }),
    Callout,
    Details,
    DetailsSummary,
    DetailsContent,
    DateChip,
    WikiLink,
    JotImage,
    Tags,
    onFold ? Fold.configure({ onToggle: onFold }) : Fold,
    JotKeys.configure({ onLink }),
    Markdown.configure({ markedOptions: { gfm: true } }),
  ]
}
