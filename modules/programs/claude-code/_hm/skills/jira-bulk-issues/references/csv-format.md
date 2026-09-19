# CSV import reference

Read this before writing a CSV. Most import failures come from a handful of
mechanics that are not guessable from the file format alone.

## Contents

- [Two different CSV importers](#two-different-csv-importers)
- [File-level requirements](#file-level-requirements)
- [Column naming](#column-naming)
- [Multiple values in one field](#multiple-values-in-one-field)
- [Hierarchy: sub-tasks, epics, parents](#hierarchy-sub-tasks-epics-parents)
- [Issue links](#issue-links)
- [Comments](#comments)
- [Attachments](#attachments)
- [Dates](#dates)
- [Users](#users)
- [Status and resolution](#status-and-resolution)
- [Updating existing issues](#updating-existing-issues)
- [Value mapping in the wizard](#value-mapping-in-the-wizard)
- [Failure modes worth naming up front](#failure-modes-worth-naming-up-front)

## Two different CSV importers

They are not the same tool and they do not have the same capabilities.

| | External System Import | Bulk create from CSV |
|---|---|---|
| Path | Settings > System > Import & Export > External System Import > CSV | Issues (or work items) > Import issues from CSV |
| Who | Jira administrators | Create Issue permission + Bulk Change global permission |
| Multi-project in one file | Yes, via Project Name / Project Key columns | Typically no; one project chosen in the wizard |
| Status, Resolution, Created, Reporter | Generally settable | Often restricted or ignored |
| Saved configuration file | Yes, and worth keeping | Limited |
| Creates missing values | Can offer to add new Priority / Resolution / Issue Type values | No |

Which one the person has access to changes what can go in the file. Ask before
generating columns that only the admin path honours. Atlassian recommends the
External System Import path for anything beyond the simplest case, precisely
because the non-admin path silently drops fields it cannot set.

## File-level requirements

- UTF-8, no byte order mark. The wizard has an encoding dropdown; it must match.
- First row is the header row. It drives the field mapping dropdowns.
- A `Summary` column is required. Rows without a summary are rejected.
- Values containing commas, newlines, or double quotes must be quoted. A quote
  inside a quoted value is doubled: `"He said ""no"""`.
- Multi-line descriptions are legal inside quotes and are the normal way to carry
  formatted descriptions. Formatting itself is a separate concern with its own
  traps -- see `rich-text.md`.
- Every row must have exactly as many fields as the header. An unquoted comma
  shifts every subsequent value one column left, which usually imports
  successfully with wrong data rather than failing.

## Column naming

The importer maps by field *name*, not by custom field ID. `customfield_10004`
in a header will not resolve; `Story Points` will. The XML export is the reliable
source for the exact display names, since a renamed field keeps its old ID.

If a field does not appear in the wizard's mapping dropdown, it is almost always
because the field is not on the destination project's create screen or is not in
that project's field configuration. Fix the screen, then use Back/Next in the
wizard to refresh the field list.

## Multiple values in one field

Repeat the column. There is no in-cell delimiter.

```csv
Summary,Component,Component,Labels,Labels,Labels
Fix rollback,storage,swupdate,ota,rollback,p1
```

The number of repeated columns must be at least the maximum number of values any
single row needs. Rows with fewer values leave the extra columns empty. Repeating
a column for a single-value field does not error; the importer keeps one value and
discards the rest silently.

Labels cannot contain spaces. A label cell with a space in it will either be
rejected or mangled depending on version.

## Hierarchy: sub-tasks, epics, parents

Sub-tasks are expressed with two extra columns, conventionally `Issue ID` and
`Parent ID`, mapped to the Jira fields of those names in the wizard.

- Every parent row gets a unique value in `Issue ID`. Any stable unique token
  works; sequential integers are conventional.
- Every parent row leaves `Parent ID` empty.
- Every sub-task row leaves `Issue ID` empty and puts the parent's `Issue ID`
  value in `Parent ID`.

```csv
Issue ID,Parent ID,Issue Type,Summary
1,,Story,Add witness storage abstraction
,1,Sub-task,Wire FRAM driver
,1,Sub-task,Add I2C retry logic
2,,Story,Ceph OSD placement
```

These IDs are file-local. They are consumed during the import and do not persist
as anything the user sees afterwards. They do not resolve against real Jira keys,
which is why a `Parent ID` naming an existing issue like `PLAT-101` fails during a
create import.

Epics are different. In company-managed Jira Software projects, an Epic row needs
an `Epic Name` value, and its children reference it through `Epic Link` — either
the Epic's real key if it already exists, or the Epic's `Issue ID` if it is being
created in the same file. Newer Jira uses a unified `Parent` field for the
epic-child relationship instead of `Epic Link`; which one applies depends on
version and project type, so confirm rather than assuming.

## Issue links

One column per link type, named `Link "<Type>"`, e.g. `Link "Blocks"`. The cell
holds the target's issue key, or the target's `Issue ID` if the target is created
in the same file. Multiple links of the same type mean repeating that column.

The link type name has to match one configured in the instance. The XML export
lists the ones actually in use.

## Comments

One `Comment` column per comment, repeated. Each cell is three
semicolon-separated parts:

```
date;author;body
```

For example: `03/Jun/25 10:15 AM;tsmith;Rebased onto main`

The date must match the date format declared in the wizard. If the cell is just a
body with no semicolons, the comment still imports but is attributed to the
importing user with the import timestamp — which is usually not what anyone
wanted, and is not recoverable afterwards without editing history.

A body containing a semicolon needs care: only the first two semicolons are
treated as separators, so a semicolon in the body text is generally fine, but
verify on a small sample.

## Attachments

An `Attachment` column holds a URL the Jira *server* can reach and fetch. It does
not take a local file path — the import runs server-side. Some versions accept a
`name;date;author;url` form similar to comments. If attachments matter, test with
one issue before generating hundreds.

## Dates

Every date column in the file must use one single format, and that format is typed
into the wizard as a Java `SimpleDateFormat` pattern.

- `MM` is month. `mm` is minute. A lowercase `mm` in the month position does not
  error; it produces wrong dates. This is the single most common silent corruption
  in Jira CSV imports.
- Default and safest choice: `dd/MMM/yy h:mm a`, e.g. `03/Jun/25 10:15 AM`.
- Jira XML exports dates in RFC-822 form (`Tue, 3 Jun 2025 10:15:23 -0700`). That
  is an export format, not an import format. Convert.
- Date-picker custom fields and date-time-picker custom fields can have different
  configured formats in the same instance, and the importer applies one pattern to
  everything. When they conflict, prefer the date-time pattern and confirm the
  date-only fields still parse.

## Users

Whatever the file says has to resolve to an account in the destination.

- Jira Cloud generally wants an Atlassian account ID, sometimes an email address.
  Display names and old usernames will not resolve.
- Jira Data Center generally wants a username.
- If the wizard's "Map field value" checkbox is left unchecked for a user column,
  the importer will attempt an automatic match, which on Data Center means
  lowercasing. On Cloud an unresolvable value typically leaves the field empty
  rather than failing the row.

An XML export shows whichever form the *source* instance used. If source and
destination are the same instance, reuse it. If not, translate.

## Status and resolution

Setting `Status` on import bypasses the workflow — no transition runs, no
post-functions fire, no conditions are checked. That is often desirable for a
migration and rarely desirable for a fresh backlog load. It generally requires the
admin External System Import path.

`Resolution` should be set only on rows whose status is a resolved status.
Resolved-looking issues with an empty resolution are a persistent reporting
annoyance, and unresolved issues carrying a resolution are worse.

## Updating existing issues

Including a column mapped to `Issue Key` turns the import into an update: rows
whose key matches an existing issue update that issue, rows whose key is empty
create new issues.

Two behaviours to warn about:

- Multi-value fields are added to, not replaced. A second import of the same
  labels produces duplicates or accumulation depending on version.
- The literal token `<<!clear!>>` in a cell clears that field.

```csv
Issue Key,Summary,Labels,Labels
PLAT-101,Renamed summary,edge,ha
PLAT-102,,<<!clear!>>,
```

An update import is destructive and has no undo. Say so before generating one.

## Value mapping in the wizard

Values for Issue Type, Priority, Status, Resolution, Component, Version, and
select-type custom fields must exist in the destination project, or be explicitly
mapped in the wizard's value-mapping step, or (for Priority, Resolution, and Issue
Type on the admin path) created through the wizard's "Add new..." affordance.

Components and versions that do not exist are typically created automatically on
the admin path. Select-list options are not — an unknown option value fails.

This is why the inventory's enumerated values matter: they are the ones known to
exist in the source instance, and reusing them exactly avoids an entire class of
mapping work.

## Failure modes worth naming up front

- The wizard's Validate step reports per-row errors and offers a downloadable log.
  Always run it. It is free and it catches value-mapping problems that the file
  itself cannot reveal.
- There is no undo. A bad import of a few hundred issues is cleaned up by bulk
  delete, which is itself a bulk-change permission operation and loses any work
  logged in between.
- Test on a small slice first — three or four rows exercising every distinct field
  and every hierarchy shape. Save the configuration file from that run and reuse
  it for the full load, so the mapping work is done once.
- Import into a test project or test instance if one exists, especially for
  anything setting Status or updating existing issues.
