import { test } from 'node:test'
import assert from 'node:assert/strict'
import { escapeText, json, makeEditor, docToMarkdown, roundTrip } from './helpers.js'

// Files Jot writes must read back to exactly the same text: these are the
// canonical forms, so each one round-trips byte for byte.
const CANONICAL = {
  headings: '# One\n\n## Two\n\n### Three\n',
  marks: 'Some **bold**, *italic*, ~~strike~~, `code`, <u>under</u> and [a link](https://example.com).\n',
  highlight: 'Plain ==yellow== and <mark data-color="blue">blue</mark> highlight.\n',
  color: 'Text <span data-color="red">in red</span> and **<span data-color="green">bold green</span>**.\n',
  tasks: '- [ ] first\n- [x] done\n  - [ ] nested child\n- [ ] third\n',
  ordered: '3. three\n4. four\n',
  bullets: '- one\n  - nested\n- two\n',
  quote: '> a quote\n',
  callout: '> [!tip] Remember\n> Body text\n>\n> - [ ] a task inside\n',
  calloutPlain: '> [!warning]\n> Careful\n',
  details: '<details open>\n<summary>Toggle title</summary>\n\nHidden text\n\n- [ ] inside\n\n</details>\n',
  code: '```swift\nlet x = 1\n```\n',
  rule: 'above\n\n---\n\nbelow\n',
  image: '![shot|320](assets/2026-10-05-shot.png)\n',
  date: '- [ ] ship it 📅 2026-10-06\n- [ ] call 📅 2026-10-07 15:30\n',
  wiki: 'See [[Ordecto]] and [[Ordecto ideas|the ideas]].\n',
  tags: 'Tagged #work and #ideas/later here.\n',
  hardBreak: 'line one\\\nline two\n',
}

for (const [name, text] of Object.entries(CANONICAL)) {
  test(`round-trips ${name}`, () => {
    assert.equal(roundTrip(text), text)
  })
}

test('plain text stays readable in the file', () => {
  const text = 'us & europe, snake_case, a_b, 3 < 4, x > y\n'
  assert.equal(roundTrip(text), text)
})

test('text that looks like syntax is escaped and reads back as text', () => {
  const editor = makeEditor()
  editor.commands.setContent(
    '<p># not a heading</p><p>- not a bullet</p><p>1. not a list</p><p>a *star* and [x] box</p><p>&lt;details&gt; text</p>',
  )
  const text = docToMarkdown(editor)
  const again = makeEditor(text)
  const types = again.getJSON().content.map((node) => node.type)
  assert.deepEqual(types.slice(0, 5), ['paragraph', 'paragraph', 'paragraph', 'paragraph', 'paragraph'])
  assert.equal(again.state.doc.child(0).textContent, '# not a heading')
  assert.equal(again.state.doc.child(1).textContent, '- not a bullet')
  assert.equal(again.state.doc.child(2).textContent, '1. not a list')
  assert.equal(again.state.doc.child(3).textContent, 'a *star* and [x] box')
  assert.equal(again.state.doc.child(4).textContent, '<details> text')
})

test('empty lines between paragraphs survive', () => {
  const first = json('one\n\n\n\ntwo\n')
  const editor = makeEditor()
  editor.commands.setContent(first)
  assert.deepEqual(json(docToMarkdown(editor)), first)
})

test('nodes parse to the right types', () => {
  const doc = json(Object.values(CANONICAL).join('\n'))
  const types = new Set()
  const walk = (node) => {
    types.add(node.type)
    node.content?.forEach(walk)
    node.marks?.forEach((mark) => types.add(`mark:${mark.type}`))
  }
  walk(doc)
  for (const type of ['callout', 'details', 'detailsSummary', 'detailsContent', 'date', 'wikiLink', 'image', 'codeBlock', 'taskItem', 'mark:highlight', 'mark:textColor', 'mark:underline']) {
    assert.ok(types.has(type), `missing ${type}`)
  }
})

test('date chips keep their attributes', () => {
  const doc = json('- [ ] call 📅 2026-10-07 9:05\n')
  const date = doc.content[0].content[0].content[0].content[1]
  assert.deepEqual({ ...date.attrs }, { date: '2026-10-07', time: '09:05' })
})

test('legacy ++underline++ still reads', () => {
  assert.equal(roundTrip('a ++word++ here\n'), 'a <u>word</u> here\n')
})

test('escapeText leaves ordinary prose alone', () => {
  assert.equal(escapeText('Hamed\'s idea: ship by 5pm'), 'Hamed\'s idea: ship by 5pm')
  assert.equal(escapeText('5 * 3'), '5 \\* 3')
  assert.equal(escapeText('_lead and trail_'), '\\_lead and trail\\_')
  assert.equal(escapeText('a ~~b~~'), 'a \\~\\~b\\~\\~')
})

// Every save must be byte-stable: writing what was just read changes nothing,
// otherwise each open would touch the file (and show up in git).
test('saves are stable for awkward shapes', () => {
  const shapes = [
    '<p>a</p><p></p><p>b</p>',
    '<p>a</p><p></p><p></p><p>b</p>',
    '<h2>h</h2><p></p><p>a</p>',
    '<p>a</p><p></p><ul><li><p>x</p></li></ul>',
    '<ul data-type="taskList"><li data-type="taskItem" data-checked="false"><p>one</p></li></ul><ul data-type="taskList"><li data-type="taskItem" data-checked="true"><p>two</p></li></ul>',
    '<p>remediation<strong><em>, </em></strong>faster</p>',
  ]
  for (const html of shapes) {
    const editor = makeEditor()
    editor.commands.setContent(html)
    const first = docToMarkdown(editor)
    assert.equal(roundTrip(first), first, html)
  }
})
