# Writing issue descriptions people can actually use

A bulk import is only as good as the descriptions in it. A terse, jargon-dense
description that assumes the reader already knows the system is worse than no
ticket - it looks complete while teaching nobody. These conventions exist so a
teammate who is *new to the domain* can open any issue you generate and quickly
understand what the work is, why it matters, and how it is expected to be done -
learning the concepts and the implementation as they read.

Apply these to every description you author (bulk-created or single). They are
opinionated on purpose; follow them unless the person tells you otherwise.

## Shape: flowing prose first, one section at the end

Do **not** structure a description as a stack of headed sections
(`Repo` / `Context` / `Goal` / `Deliverables` / `DoD`). That reads as a form,
buries the point, and repeats itself. Instead:

1. **Open with flowing prose and no header.** The first sentence is the thesis:
   plainly, *what this is and why it matters*. Then glide from the high level down
   into the context a newcomer needs. This unheaded intro replaces separate
   "Context" and "Goal" sections - the goal is simply stated up front, in prose.

2. **Then a "how we plan to build it" paragraph** (unheaded, or introduced with a
   short italic label like `_How we plan to build it._`). See "Be a solutioning
   artifact" below.

3. **End with exactly one section: `h3. Acceptance Criteria`.** H3 is the largest
   heading you may use - `h1`/`h2` render far too large in a Jira issue. Name it
   "Acceptance Criteria", never "DoD"/"Definition of Done". Merge what you would
   have called "Deliverables" into it: each bullet is a deliverable phrased as a
   checkable done-condition.

That is the whole structure: two-to-three short prose paragraphs, a light pointer
line, and one `h3. Acceptance Criteria` list. Less scaffolding, more signal.

## Voice: write for a newcomer, gloss every term of art

- Lead with plain language. Assume the reader is competent but new to *this*
  system.
- The first time you use a term of art, gloss it in one clause - inline, in
  parentheses. (e.g. "a *place* is labgrid's term for one registered device slot").
- Prefer concrete verbs and short sentences over insider shorthand. If a sentence
  only parses for someone already on the team, rewrite it.

## Link generously, and link inline where the term first appears

Hyperlink anything that helps the reader. This is the highest-leverage part of the
convention and the easiest to under-do.

- **Attach the link to the concept, right where it is introduced** - not in a
  single dump at the end. Link the concept to the doc section that explains it, the
  repo name to the repo, the pattern to the example file, the tool to its docs.
- **Never name a repo, path, doc, concept, or tool without linking it when a link
  exists.** "It goes in nixcfg-work" should be "[nixcfg-work|<url>]".
- Prefer **specific** targets: a blob URL with a heading anchor
  (`.../design.md#the-nixcfg-hand-off`), a file, a directory - not just the repo
  root or a doc's top.
- **Anchor caveat:** GitLab/GitHub derive heading anchors by lowercasing and
  hyphenating. Anchors for headings containing `&` or `->` are unreliable (extra
  hyphens) - link to a nearby clean-titled heading instead, or verify the anchor.
- Verify link targets exist on the branch you point at (usually `main`) before
  shipping - `git cat-file -e origin/main:<path>` for in-repo files.
- A light closing pointer ("For the whole picture, see the [README|...] and the
  [architecture diagram|...]") is fine for the entry point and the big picture.

## Be a solutioning artifact: state the implementation approach

Filing the ticket *is* part of designing the work. If you have ideas about how it
should be done - especially from prior work - put them in the description, clearly
and transparently, so the description teaches the *implementation*, not only the
concept:

- **Which repo(s)** the work lands in - linked. If the repos are unfamiliar to the
  team, that is more reason to link and explain them.
- **Where within the repo** - the prescriptive path/module/file the change belongs
  in.
- **The prior-work pattern to copy** - link a real example (a file or directory)
  that already does the thing, and say "follow this shape rather than inventing a
  new one".
- **Contrast with the current state** - link the file that exists today so the
  reader sees the before/after.

Be transparent that these are the current design ideas, not immutable law - but do
not omit them. A reader should finish the description knowing roughly how to start.

## Lead with the visual: surface the map early

A wall of text loses a newcomer before the first link. If a diagram or overview
exists - or can be made - put it where the reader sees it *first*.

- **Open with one concise reference line, above the prose.** A single plain first
  line pointing at the overview diagram and the most useful doc section, e.g.
  `Refer to the [architecture diagram|...] and [README|...#authoritative-design] for context.`
  Keep it quiet and helpful - do NOT use a `{panel}`/callout box or "Start here" /
  "New here?" language, and do not bury the diagram link at the end. Anchor the
  doc link to its most useful section, not just the file top.
- **Prefer a real embedded image where it renders reliably.** Jira renders
  `!attachment.png!` (an image attached to the issue) dependably; an external
  `!https://.../img.svg!` usually does NOT (private-repo auth, SVG sanitization,
  host allowlist). Attach a PNG render rather than linking a repo SVG.
- **Embed once on the parent, link from the children.** For a set of stories under
  an epic/feature, embed the canonical diagram on the parent (its natural home) and
  give each child the top callout linking it - do not duplicate a large image N
  times.
- **Make the diagram exist if it doesn't, and specialize it per story.** A feature
  usually has (or deserves) one system / block / interaction diagram. Beyond the
  static whole-system view on the parent, the strongest aid is a per-story variant
  that overlays a highlight/callout on the exact area that story implements - so the
  reader sees the whole system AND how the work decomposes onto it. Create these
  when the payoff warrants (prior art: the aircraft-data-simulator feature's
  per-story diagram overlays). This is an enhancement - do not block shipping the
  text on it.

## Jira wiki markup quick reference

Descriptions render as **Jira wiki markup** (the importer and the REST v2
`description` field both take wiki markup, not Markdown). If your source is
Markdown, convert it with `scripts/md_to_wiki.py`. Key tokens:

| Intent | Wiki markup |
|---|---|
| Heading (largest allowed) | `h3. Acceptance Criteria` |
| Bold | `*bold*` |
| Italic | `_italic_` |
| Monospace / code span | `{{code}}` |
| Link | `[label|https://url]` |
| Bullet | `* item` |

A bare `https://...` URL auto-links; use `[label|url]` when you want a label.
Embedded newlines inside a quoted CSV cell are preserved as line breaks.

## Worked example

`CONVSW-7055` ("labDevices Nix source of truth and generators", a child of the
CONVSW-4165 HIL feature) is the canonical example of this convention: an unheaded
thesis + context intro with concept links inline, a "how we plan to build it"
paragraph linking both repos, the prescriptive path, two prior-work pattern
examples and the current-state file, a README + diagram pointer, and a single
`h3. Acceptance Criteria` list of done-conditions. Mirror its shape.
