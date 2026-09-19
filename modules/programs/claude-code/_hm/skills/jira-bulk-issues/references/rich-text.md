# Rich text in descriptions and comments

## The format choice is not the lever

CSV and the importer JSON both carry a description as a plain string. Neither is
"richer" than the other for text. What decides whether that string renders as
formatted text or as one flat paragraph is two things the file cannot control:

1. **The destination field's renderer.** A field set to the default text renderer
   displays markup literally. It has to be the wiki-style renderer for markup to
   render. On Data Center and Cloud company-managed projects this is set per-field
   in Field Configuration; team-managed projects generally do not expose it.
2. **Which markup dialect the importer writes.** This is the part that trips
   people, and it is worth stating plainly to anyone about to author a hundred
   descriptions.

## The dialect trap

Jira Cloud's issue view is ADF, and its editor accepts markdown-style input. But
the CSV importer does not go through that editor. It writes the value as **Jira
wiki markup**, the older dialect — so markdown that works when typed into the
issue view does not work when imported, and vice versa. Atlassian has this on file
as JRACLOUD-79205.

Practically: **author descriptions in Jira wiki markup, not markdown.** The two
collide most dangerously on emphasis, because they disagree about asterisks:

| Intent | Markdown | Jira wiki markup |
|---|---|---|
| bold | `**bold**` | `*bold*` |
| italic | `*italic*` | `_italic_` |

Markdown bold pasted into an imported description renders as *italic wrapped in
stray asterisks*. It is the single most common formatting defect in bulk-imported
issues, and because it imports cleanly nobody notices until someone reads a ticket.

## Wiki markup cheat sheet

```
*bold*            _italic_          -strikethrough-       +underline+
{{monospace}}     ^superscript^     ~subscript~

h1. Heading 1
h2. Heading 2
h3. Heading 3

* bullet
** nested bullet
# numbered
## nested numbered

[https://example.com]                    bare link
[link text|https://example.com]          labelled link
[PLAT-101]                               issue key, auto-linked
[~accountid:5b10a2844c20165700ede21g]    user mention (Cloud)
[~username]                              user mention (Data Center)

{code:python}
def f():
    return 1
{code}

{noformat}
literal text, no markup applied
{noformat}

bq. a single-line block quote

{quote}
a multi-line
block quote
{quote}

||Header 1||Header 2||
|cell a|cell b|
|cell c|cell d|

----                                     horizontal rule
\*not bold\*                             backslash escapes markup
```

## Newlines inside a CSV cell

Lists, headings, and paragraphs all need real line breaks, and those are legal
inside a quoted CSV cell:

```csv
Summary,Description
Add witness storage,"h3. Context

The Cortex-R5 needs ~64 bytes of witness state.

* FRAM over I2C
* existing EEPROM

See [the design doc|https://example.com/doc]."
```

Write these with a real CSV writer. Hand-assembling quoted multi-line cells is how
you get a file that opens fine in a text editor and shifts every column on import.

Excel and Google Sheets round-trip embedded newlines inconsistently — a file that
survives a save in Excel may have had its line breaks flattened. If descriptions
carry structure, generate the CSV programmatically and do not open it in a
spreadsheet on the way to Jira.

## Verify before scaling

Import one issue whose description exercises every construct in play — a heading,
a bullet list, a link, bold text, a code block. Look at it in Jira. Adjust once.
Then generate the rest. This costs two minutes and is the only reliable way to
pin down renderer behaviour on a specific instance and project type, which varies
more than the documentation suggests.

## Authoring in markdown anyway

If the source content is already markdown — a design doc, a plan, meeting notes —
convert rather than retype:

```bash
python3 scripts/md_to_wiki.py notes.md > notes.wiki
python3 scripts/md_to_wiki.py --inline "See **the doc** at [here](https://x.com)"
```

The converter handles headings, emphasis, links, lists, fenced and inline code,
blockquotes, rules, and simple tables. It does not handle nested structures inside
table cells, reference-style links, footnotes, or HTML passthrough — it reports
what it skipped on stderr so those can be fixed by hand.

## If formatting fidelity really matters

Two escape hatches when wiki markup is not enough:

- **Attach the real document** and keep the description short, pointing at it.
  Often the right answer for anything longer than a screen.
- **Use the REST API instead of an importer.** Jira Cloud's v3 API takes ADF
  directly, which is the only way to get the full editor feature set
  programmatically; v2 accepts wiki markup. This gives up the import wizard
  entirely and is a different piece of work, but it is the honest answer when
  someone needs tables inside panels inside expands.
