# JSON import reference

Jira's JSON importer is a separate, admin-only importer reached the same way as
the admin CSV path: Settings > System > Import & Export > External System Import >
JSON. It is not the REST API. Its schema is a deliberately simplified shape that
does not resemble what `GET /rest/api/3/issue` returns, so do not build a file by
adapting REST output.

Reach for it when CSV's flat shape is fighting the data:

- comments with distinct authors and timestamps at any volume
- issue history / changelog, which CSV cannot express at all
- worklogs
- cascading selects and structured custom field values
- creating projects, components, and versions as part of the same load

Stay with CSV for a plain backlog load. JSON is admin-only, less commonly
exercised, and has fewer people who can debug it when it misbehaves.

## Shape

```json
{
  "users": [
    { "name": "alice", "fullname": "Alice Foo", "email": "alice@example.com" }
  ],
  "links": [
    { "name": "sub-task-link", "sourceId": "2", "destinationId": "1" },
    { "name": "Duplicate",     "sourceId": "3", "destinationId": "2" }
  ],
  "projects": [
    {
      "name": "Platform",
      "key": "PLAT",
      "type": "software",
      "description": "Imported backlog",
      "components": ["chassis-manager", "swupdate"],
      "versions": [
        { "name": "2026.3", "released": false },
        { "name": "2026.2", "released": true,
          "releaseDate": "2026-02-14T00:00:00.000-0800" }
      ],
      "issues": [
        {
          "externalId": "1",
          "issueType": "Story",
          "summary": "Add witness storage abstraction",
          "description": "Body text.\nSupports *wiki markup*.",
          "priority": "Medium",
          "status": "In Progress",
          "reporter": "alice",
          "assignee": "bob",
          "labels": ["edge", "ha"],
          "watchers": ["carol"],
          "components": ["chassis-manager"],
          "affectedVersions": ["2026.2"],
          "fixedVersions": ["2026.3"],
          "created": "2026-06-03T10:15:23.000-0700",
          "updated": "P-1D",
          "duedate": "2026-06-27T00:00:00.000-0700",
          "originalEstimate": "1d",
          "comments": [
            { "body": "First pass looks fine.",
              "author": "alice",
              "created": "2026-06-03T11:00:00.000-0700" }
          ],
          "attachments": [
            { "name": "trace.log", "attacher": "bob",
              "created": "2026-06-03T11:30:00.000-0700",
              "uri": "https://files.example.com/trace.log" }
          ],
          "customFieldValues": [
            { "fieldName": "Story Points",
              "fieldType": "com.atlassian.jira.plugin.system.customfieldtypes:float",
              "value": "5" },
            { "fieldName": "Target Platform",
              "fieldType": "com.atlassian.jira.plugin.system.customfieldtypes:multicheckboxes",
              "value": ["arm64", "amd64"] },
            { "fieldName": "Area",
              "fieldType": "com.atlassian.jira.plugin.system.customfieldtypes:cascadingselect",
              "value": { "": "Runtime", "1": "Scheduler" } }
          ]
        }
      ]
    }
  ]
}
```

## Rules that matter

**`externalId` is the file-local identity.** It plays the role `Issue ID` plays in
CSV. Links and parentage reference it. Give every issue one.

**Parentage is a link, not a field.** A sub-task relationship is an entry in the
top-level `links` array with `"name": "sub-task-link"`, where `sourceId` is the
child's `externalId` and `destinationId` is the parent's. Getting the direction
backwards produces a valid import with inverted hierarchy.

**Links are top-level, which forces scope decisions.** Because `links` sits
outside `projects`, cross-project links require both projects to be in the same
file. If issues in project A link to issues in project B, either combine them into
one import or accept patching the links up afterwards.

**Dates are ISO-8601 with an offset**, matching `yyyy-MM-dd'T'HH:mm:ss.SSSZ`, e.g.
`2026-06-03T10:15:23.000-0700`. Relative forms like `P-1D` (one day ago) are also
accepted, which is occasionally handy for synthetic test data and a bad idea for
anything real.

**`fieldType` on custom fields is the type key, not a guess.** It is exactly the
`key` attribute of the `<customfield>` element in an XML export, which is why the
inventory captures it. A mismatched `fieldType` fails or writes garbage.

**Custom field value shape follows the type.** Single-value types take a scalar.
Multi-value types take an array. Cascading selects take an object keyed by depth,
with `""` for the parent level and `"1"` for the child.

**The importer creates missing structure.** Projects, components, and versions
named in the file are created if absent. That is convenient and it is also how
people accidentally create a project named `Platfrom`.

## Before running one

- Back up, or import into a test instance. Same as CSV: no undo.
- Disable security levels on the destination project first; they can block issue
  creation partway through.
- Validate the file is well-formed JSON before uploading. The importer's parse
  errors are not always precise about location.
- Test with two or three issues covering every custom field type and one link,
  then scale up.

## Known rough edges

The JSON importer is less exercised than the CSV one and has accumulated
long-lived bugs, including reports of the first entry in an issue's `history`
array being dropped on import. If history fidelity is the reason for choosing
JSON, verify it on a small sample before committing to a large load, and search
Atlassian's issue tracker for current status rather than assuming a given bug is
fixed.
