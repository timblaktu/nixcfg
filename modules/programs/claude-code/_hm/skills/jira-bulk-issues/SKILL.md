---
name: jira-bulk-issues
description: Turn a Jira XML issue export into a validated bulk-import file (CSV or Jira importer JSON) that matches the team's real fields, custom field IDs, and allowed values. Use this whenever someone wants to create, stage, or update Jira issues in bulk, mentions importing issues into Jira, has a Jira XML export they want to build from, asks to turn a backlog or plan or spreadsheet into Jira tickets, or asks what format Jira bulk imports need — including when they only describe the work ("file all these as tickets", "get this epic breakdown into Jira") without naming a file format.
---

# Bulk Jira issues from an XML export

Jira cannot import its own XML. The XML search export is a *schema oracle*, not an
import artifact: it is the only easily obtained document that shows which fields
this particular instance uses, what the custom fields are actually called and
typed, and which values already exist for the select-style fields. Use it to
derive the shape, then emit CSV or the importer's JSON.

Getting a bulk import wrong is expensive in a specific way — there is no undo, and
the most common errors (a lowercase `mm` in a date pattern, a shifted column from
an unquoted comma, a `Parent ID` pointing at a real Jira key) produce a *successful*
import containing wrong data rather than an error. Front-load the checking.

## Workflow

### 1. Get the export

If the person has not supplied one, ask for it. The path is: run a JQL search in
the Issue Navigator that returns a representative slice, then Export > XML. On
Cloud this may be labelled "Export XML" under the export menu.

"Representative" means: covers every issue type they intend to create, has at
least one issue with each custom field populated, and includes a sub-task and a
linked issue if hierarchy or links are in scope. Fifty issues is plenty. The
inventory can only report fields that are non-empty somewhere in the sample, so a
thin export produces a thin inventory — say this rather than letting them assume
the inventory is the schema.

If they cannot produce an export, the skill still works, but every field name and
allowed value becomes an assumption to confirm with them explicitly. Do not invent
custom field names.

### 2. Build the inventory

```bash
python3 scripts/inventory_export.py <export.xml> --out-dir inventory
```

This writes `field-inventory.json` (machine-readable, consumed by the validator),
`field-inventory.md` (for the human), and `template.csv` (a header row with
repeated columns already sized to the observed multi-value maxima).

Read `field-inventory.md` and summarize it back: the custom fields and their
types, the enumerated values, whether sub-tasks and links appear, and the date
situation. This is the moment the person catches "that field is deprecated" or
"Subsystem has forty options, you only sampled three" — cheaply, before anything
is generated.

### 3. Establish the four things the inventory cannot tell you

An XML export describes the *source*. An import targets a *destination*. Ask, do
not infer:

- **Destination project.** Same project as the export, or a different one? A
  different project means every enumerated value has to exist there too.
- **Which importer they can reach.** Admin External System Import, or the
  non-admin bulk-create-from-CSV path? This determines whether Status, Resolution,
  Reporter, and Created are settable at all. See `references/csv-format.md`.
- **Cloud or Data Center.** Changes the user identifier form and which fields
  exist (`Epic Link` vs a unified `Parent`).
- **Create or update.** An `Issue Key` column silently converts a create into an
  update, and updates are destructive with no undo.

Where the answer changes the output materially and they do not know, prefer the
conservative option and flag it in the handoff notes rather than guessing.

### 4. Choose the format

Default to **CSV**. It is the path most people can actually run, it is the one
their colleagues can debug, and it covers ordinary backlog loading completely.

Choose **JSON** only when the data needs something CSV structurally cannot carry:
issue history, worklogs, comments with distinct authors at volume, or structured
custom field values. Note that JSON is admin-only. Read
`references/json-format.md` before writing one.

If the person explicitly asks for XML, explain the situation rather than
producing something unusable: no Jira importer reads issue XML, the XML backup on
Data Center restores whole instances rather than adding issues, and the search
export is one-directional. Offer to transform their XML into CSV or JSON instead.

### 5. Generate

Start from `inventory/template.csv` and cut it down. Include only fields the
person is actually setting — a column full of blanks is a column that still has to
be mapped in the wizard, and every unnecessary mapping is a chance to map
something wrong.

Column count for repeated multi-value columns must cover the worst-case row, not
the typical one.

Write the file with a real CSV writer rather than string-joining, so quoting and
embedded newlines are handled. In Python, `csv.writer` with default settings and
`newline=""` on the file handle.

If any description or comment carries formatting -- headings, bullets, links,
bold, code blocks -- read `references/rich-text.md` before writing them. The
importer writes Jira wiki markup, not Markdown, and the two disagree about
asterisks in a way that imports cleanly and reads wrong. Content already in
Markdown goes through `scripts/md_to_wiki.py`.

**Before writing any description text, read `references/description-conventions.md`.**
Getting the *mechanics* right (wiki markup) is not the same as writing a
description a newcomer can use. The conventions there are mandatory unless the
person says otherwise: open with flowing prose (thesis first, no header), gloss
every term of art inline, link generously and inline (concepts to their doc
sections, repos and paths to their URLs, patterns to real example files), state
the implementation approach transparently since filing is part of solutioning,
and end with a single `h3. Acceptance Criteria` list (H3 max; never "DoD"). A
flat, headed, jargon-dense description is a defect even if it imports cleanly.

For anything nontrivial, write a small generator script alongside the output
rather than emitting the CSV by hand. The person will want to regenerate after
changing one field, and a script makes that a one-line edit instead of a re-read
of two hundred rows.

### 6. Validate before handing over

```bash
python3 scripts/validate_import.py <issues.csv> \
  --inventory inventory/field-inventory.json \
  --date-format "dd/MMM/yy h:mm a"
```

It checks row/header field counts, Summary presence, Issue ID uniqueness, Parent
ID resolution, date parsing against the declared pattern, comment cell structure,
select values against the enumerations, and BOM/encoding. Non-zero exit means at
least one error-level finding.

Fix everything at error level. Warnings are judgment calls — an unknown select
value is fine if the destination project has that option and the sample just did
not show it, and it is a broken import if not. Resolve them with the person rather
than suppressing them.

### 7. Hand over with the operating instructions

The file alone is not the deliverable. Include, briefly:

- Which importer path to use and the exact menu route.
- The date format string to type into the wizard, verbatim.
- Which columns need explicit value mapping, and to what.
- For sub-tasks: map `Issue ID` and `Parent ID` to the Jira fields of those names.
- A reminder to run the wizard's Validate step, and to save the configuration file
  from the run so the mapping work is not repeated.
- A recommendation to import three or four rows first, confirm they look right in
  Jira, then load the rest.

## Judgment calls

**A spreadsheet or a plan instead of an export.** Same workflow, one extra step:
map their columns onto the inventory's field names first, and show the mapping for
confirmation before generating. Their "Owner" is Jira's `Assignee`; their "P1" may
or may not be `Highest`.

**No XML export available.** Say plainly that field names and allowed values are
now assumptions. Generate a minimal CSV — Issue Type, Summary, Description, and
nothing else — since those four are near-universal, and let them add fields once
they can confirm names.

**Issue content that needs writing, not just formatting.** Drafting good summaries
and descriptions is often the actual work. Do it, but keep it separate from the
mechanical step: agree the content first, then convert and run it through this
pipeline. Descriptions containing commas, quotes, or newlines are exactly what the
quoting rules exist for.

**Large loads.** Past a few hundred rows, suggest splitting by issue type or by
epic. Smaller batches fail smaller, and a partial failure at row 900 of 1000 is
much harder to reconcile than the same failure in a 100-row batch.

**Requests to import via API instead.** The REST bulk-create endpoint takes JSON
payloads, not files, and is a different shape from the importer JSON. If they want
automation rather than a wizard, that is a legitimate path — but it is a different
task, and the field inventory from step 2 is still the right input to it.

## Reference files

- `references/csv-format.md` — CSV mechanics: the two importers and what each can
  set, multi-value columns, sub-task and epic hierarchy, links, comments,
  attachments, dates, users, update mode, value mapping. Read before writing a CSV.
- `references/json-format.md` — the importer JSON schema, `externalId` and link
  semantics, custom field value shapes by type, known rough edges. Read before
  writing JSON.
- `references/rich-text.md` — formatted descriptions and comments: the renderer
  requirement, the wiki-markup-versus-Markdown trap, a wiki markup cheat sheet,
  newlines inside CSV cells. Read before writing any formatted body text.
- `references/description-conventions.md` — how to write a description a newcomer
  can actually use: flowing-prose-first shape, one `h3. Acceptance Criteria`
  section, gloss jargon inline, link generously and inline, and state the
  implementation approach (repos/paths/prior-work examples). Read before writing
  any description text; the mechanics in `rich-text.md` are necessary but not
  sufficient.

## Scripts

- `scripts/inventory_export.py` — XML export to field inventory. `--max-values N`
  raises the cap on enumerated values listed per field (default 25);
  `--include-status` adds Status and Resolution to the template header.
- `scripts/validate_import.py` — CSV against inventory. `--strict-values`
  promotes unknown select values from warnings to errors, which is the right
  setting once the destination project's options have been confirmed.
- `scripts/md_to_wiki.py` — Markdown to Jira wiki markup, for description and
  comment bodies. Takes a file, stdin, or `--inline "text"`. Reports anything it
  could not translate on stderr rather than mangling it silently.

Both are standard-library only and run under any Python 3.8+.
