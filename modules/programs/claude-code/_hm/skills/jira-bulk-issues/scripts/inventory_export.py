#!/usr/bin/env python3
"""
Parse a Jira XML search export (Issue Navigator -> Export -> XML) and derive a
field inventory describing what this Jira instance actually uses.

The XML is a read-only oracle. Jira cannot import it. Its value is that it names
the real fields, the real custom field IDs and types, and the real allowed values
(issue types, statuses, priorities, components, versions, select options) for the
target instance -- which is exactly the information a bulk import must match.

Outputs into --out-dir:
  field-inventory.json   machine-readable inventory
  field-inventory.md     human-readable summary to review with the user
  template.csv           header row only, with repeated columns for multi-value fields

Usage:
  python3 inventory_export.py export.xml --out-dir ./inventory
  python3 inventory_export.py export.xml --out-dir ./inventory --max-values 40
"""

import argparse
import json
import os
import re
import sys
from collections import Counter, OrderedDict, defaultdict
from xml.etree import ElementTree as ET

# Item-level tags that are structural rather than scalar fields.
CONTAINER_TAGS = {
    "customfields",
    "comments",
    "attachments",
    "subtasks",
    "issuelinks",
    "labels",
    "timeoriginalestimate",
    "timeestimate",
    "timespent",
    "aggregatetimeoriginalestimate",
    "aggregatetimeestimate",
    "aggregatetimespent",
}

# Tags whose distinct values are worth enumerating, because a CSV/JSON import
# must map each one onto a value that already exists in the destination project.
ENUM_TAGS = {
    "type": "Issue Type",
    "status": "Status",
    "priority": "Priority",
    "resolution": "Resolution",
    "component": "Component",
    "fixVersion": "Fix Version",
    "version": "Affects Version",
    "project": "Project",
    "security": "Security Level",
}

# Tags that carry a user identity. Imports must reference the account form the
# destination instance expects (accountId on Cloud, username on Data Center).
USER_TAGS = {"assignee", "reporter", "creator"}

CONTAINER_NOTES = {
    "comments": ("Emit one 'Comment' column per comment, each cell formatted "
                 "'date;author;body'. Omitting date and author attributes the comment to "
                 "the importing user at import time."),
    "attachments": ("Emit an 'Attachment' column holding a URL the Jira server can reach. "
                    "The importer fetches by URL; it cannot read local paths."),
    "subtasks": ("Not a column. Express parentage from the child's side using Issue ID and "
                 "Parent ID."),
    "issuelinks": ("Emit one column per link type, named Link \"<Type>\", holding the target "
                   "key or the target's Issue ID within this file."),
    "labels": "Repeat the 'Labels' column once per label. Labels cannot contain spaces.",
}

# Tags Jira's importer will not accept as ordinary columns, or accepts only
# through a specific mechanism. Never emit these as plain CSV columns.
NON_IMPORTABLE_TAGS = {
    "title",
    "link",
    "description",  # channel-level; item-level description IS importable
    "statusCategory",
    "watches",
    "aggregatetimeoriginalestimate",
    "aggregatetimeestimate",
    "aggregatetimespent",
}

# XML item tag -> conventional Jira import column name.
COLUMN_NAMES = {
    "summary": "Summary",
    "description": "Description",
    "environment": "Environment",
    "key": "Issue Key",
    "project": "Project Key",
    "type": "Issue Type",
    "priority": "Priority",
    "status": "Status",
    "resolution": "Resolution",
    "assignee": "Assignee",
    "reporter": "Reporter",
    "creator": "Creator",
    "created": "Date Created",
    "updated": "Date Modified",
    "resolved": "Date Resolved",
    "due": "Due Date",
    "component": "Component",
    "fixVersion": "Fix Version",
    "version": "Affects Version",
    "labels": "Labels",
    "votes": "Votes",
    "security": "Security Level",
    "timeoriginalestimate": "Original Estimate",
    "timeestimate": "Remaining Estimate",
    "timespent": "Time Spent",
    "parent": "Parent ID",
}

CF_TYPE_HINTS = {
    "select": ("select", "Single select. Import value must match an existing option."),
    "multiselect": ("multiselect", "Multi select. Repeat the column once per value."),
    "radiobuttons": ("select", "Radio. Import value must match an existing option."),
    "multicheckboxes": ("multiselect", "Checkboxes. Repeat the column once per value."),
    "cascadingselect": ("cascading", "Cascading select. Use 'Parent -> Child'. Only two levels supported."),
    "textfield": ("text", "Single-line text."),
    "textarea": ("text", "Multi-line text. Quote the cell; embedded newlines are allowed inside quotes."),
    "url": ("text", "URL field."),
    "float": ("number", "Numeric. Use a plain decimal, no thousands separators."),
    "datepicker": ("date", "Date only. Must match the wizard's date format."),
    "datetime": ("datetime", "Date and time. Must match the wizard's date format exactly."),
    "userpicker": ("user", "Single user. Use the identifier form the destination expects."),
    "multiuserpicker": ("multiuser", "Multiple users. Repeat the column once per user."),
    "grouppicker": ("group", "Single group."),
    "multigrouppicker": ("multigroup", "Multiple groups. Repeat the column."),
    "labels": ("multiselect", "Labels-style. Repeat the column once per label."),
    "version": ("select", "Version picker. Value must be an existing version name."),
    "multiversion": ("multiselect", "Multi version picker. Repeat the column."),
    "project": ("select", "Project picker."),
    "importid": ("number", "Import ID field, usually created by a previous import."),
    "readonlyfield": ("text", "Read-only. Likely rejected on import."),
}


def text_of(el):
    if el is None:
        return None
    t = "".join(el.itertext()).strip()
    return t or None


def sample_of(el):
    """A one-line, whitespace-collapsed sample. Container tags concatenate their
    children's text, so collapsing keeps the inventory table readable."""
    t = text_of(el)
    if not t:
        return None
    return re.sub(r"\s+", " ", t)


def classify_custom_field(key):
    """Map a custom field type key like
    'com.atlassian.jira.plugin.system.customfieldtypes:multiselect'
    onto a coarse kind plus an import note."""
    if not key:
        return "unknown", "Type not declared in the export. Confirm before importing."
    tail = key.rsplit(":", 1)[-1].lower()
    # Longest needle first: 'cascadingselect' must win over 'select',
    # 'multiuserpicker' over 'userpicker', and so on.
    for needle in sorted(CF_TYPE_HINTS, key=len, reverse=True):
        if needle in tail:
            return CF_TYPE_HINTS[needle]
    if "greenhopper" in key.lower():
        if "epic-label" in tail:
            return "text", "Epic Name. Required on Epic rows in company-managed projects."
        if "epic-link" in tail:
            return "text", "Epic Link. Reference the Epic's key, or its Issue ID within the same file."
        if "sprint" in tail:
            return "multiselect", "Sprint. Import support is unreliable; prefer setting sprints after import."
        if "rank" in tail:
            return "rank", "Rank. Not importable; Jira assigns it."
        return "unknown", "Jira Software field. Verify import support before relying on it."
    return "unknown", f"Unrecognized type '{tail}'. Verify import support before relying on it."


def parse(path, max_values):
    tree = ET.parse(path)
    root = tree.getroot()
    channel = root.find("channel")
    if channel is None:
        sys.exit("No <channel> element found. Is this a Jira XML search export?")

    items = channel.findall("item")
    if not items:
        sys.exit("No <item> elements found. The export contains no issues.")

    inv = OrderedDict()
    inv["source_file"] = os.path.basename(path)
    inv["issues_in_export"] = len(items)

    build = channel.find("build-info")
    if build is not None:
        inv["jira_build"] = {
            (c.tag): text_of(c) for c in build if text_of(c) is not None
        }

    issue_el = channel.find("issue")
    if issue_el is not None and issue_el.get("total"):
        inv["issues_matching_query"] = issue_el.get("total")

    # --- system fields -------------------------------------------------
    tag_counts = Counter()
    tag_max_per_item = Counter()
    tag_samples = defaultdict(list)
    enum_values = defaultdict(Counter)
    users = defaultdict(Counter)

    max_comments = 0
    max_attachments = 0
    link_types = defaultdict(set)
    has_subtasks = False
    has_parent = False

    for item in items:
        per_item = Counter()
        for child in item:
            tag = child.tag
            per_item[tag] += 1
            tag_counts[tag] += 1

            val = text_of(child)
            if tag == "project":
                pkey = child.get("key")
                if pkey:
                    enum_values["project_key"][pkey] += 1
                    val = pkey
            sval = (child.get("key") if tag == "project" else None) or sample_of(child)
            if sval and len(tag_samples[tag]) < 3 and sval not in tag_samples[tag]:
                tag_samples[tag].append(sval[:120])

            if tag in ENUM_TAGS and val:
                enum_values[tag][val] += 1
            if tag in USER_TAGS:
                ident = child.get("accountid") or child.get("username") or val
                if ident:
                    users[tag][ident] += 1
            if tag == "labels":
                for lab in child.findall("label"):
                    lv = text_of(lab)
                    if lv:
                        enum_values["labels"][lv] += 1
                per_item["labels"] = max(per_item["labels"], len(child.findall("label")))
            if tag == "comments":
                max_comments = max(max_comments, len(child.findall("comment")))
            if tag == "attachments":
                max_attachments = max(max_attachments, len(child.findall("attachment")))
            if tag == "subtasks" and child.findall("subtask"):
                has_subtasks = True
            if tag == "parent":
                has_parent = True
            if tag == "issuelinks":
                for lt in child.findall("issuelinktype"):
                    name = text_of(lt.find("name")) or "?"
                    for direction in ("outwardlinks", "inwardlinks"):
                        d = lt.find(direction)
                        if d is not None and d.findall("issuelink"):
                            link_types[name].add(d.get("description") or direction)

        for tag, n in per_item.items():
            if n > tag_max_per_item[tag]:
                tag_max_per_item[tag] = n

    system_fields = []
    for tag, count in tag_counts.most_common():
        if tag == "customfields":
            continue
        entry = OrderedDict()
        entry["xml_tag"] = tag
        entry["import_column"] = COLUMN_NAMES.get(tag)
        entry["present_on_issues"] = count
        entry["max_values_per_issue"] = tag_max_per_item[tag]
        entry["samples"] = tag_samples.get(tag, [])
        if tag in NON_IMPORTABLE_TAGS and tag != "description":
            entry["importable"] = False
            entry["note"] = "Derived or display-only. Do not emit as an import column."
        elif tag in CONTAINER_NOTES:
            entry["importable"] = "special"
            entry["note"] = CONTAINER_NOTES[tag]
        elif tag == "key":
            entry["importable"] = "update-only"
            entry["note"] = ("Issue Key. Including it turns the import into an update of "
                             "existing issues. Omit it when creating new ones.")
        elif entry["import_column"] is None:
            entry["importable"] = "unknown"
            entry["note"] = "No conventional column name. Confirm with the user before including."
        else:
            entry["importable"] = True
        system_fields.append(entry)
    inv["system_fields"] = system_fields

    # --- custom fields --------------------------------------------------
    cf = OrderedDict()
    cf_max_values = Counter()
    for item in items:
        holder = item.find("customfields")
        if holder is None:
            continue
        for field in holder.findall("customfield"):
            cid = field.get("id") or "unknown"
            name = text_of(field.find("customfieldname")) or cid
            key = field.get("key")
            rec = cf.setdefault(
                cid,
                OrderedDict(
                    id=cid,
                    name=name,
                    type_key=key,
                    kind=None,
                    note=None,
                    present_on_issues=0,
                    max_values_per_issue=0,
                    distinct_values=Counter(),
                ),
            )
            rec["present_on_issues"] += 1
            values = []
            holder_vals = field.find("customfieldvalues")
            if holder_vals is not None:
                for v in holder_vals.findall("customfieldvalue"):
                    tv = text_of(v)
                    if tv:
                        parent_key = v.get("key")
                        values.append(f"{parent_key} -> {tv}" if parent_key else tv)
            cf_max_values[cid] = max(cf_max_values[cid], len(values))
            for v in values:
                rec["distinct_values"][v] += 1

    custom_fields = []
    for cid, rec in cf.items():
        kind, note = classify_custom_field(rec["type_key"])
        vals = rec["distinct_values"]
        enumerate_values = kind in {"select", "multiselect", "cascading", "group", "multigroup"}
        out = OrderedDict()
        out["id"] = cid
        out["name"] = rec["name"]
        out["import_column"] = rec["name"]  # importers map by field name, not ID
        out["type_key"] = rec["type_key"]
        out["kind"] = kind
        out["note"] = note
        out["present_on_issues"] = rec["present_on_issues"]
        out["max_values_per_issue"] = cf_max_values[cid]
        out["distinct_value_count"] = len(vals)
        if enumerate_values:
            out["allowed_values_seen"] = [v for v, _ in vals.most_common(max_values)]
            out["values_truncated"] = len(vals) > max_values
        else:
            out["samples"] = [v for v, _ in vals.most_common(3)]
        custom_fields.append(out)
    custom_fields.sort(key=lambda r: (-r["present_on_issues"], r["name"]))
    inv["custom_fields"] = custom_fields

    # --- enumerations ---------------------------------------------------
    enums = OrderedDict()
    for tag, counter in enum_values.items():
        label = ENUM_TAGS.get(tag, "Labels" if tag == "labels" else tag)
        enums[label] = OrderedDict(
            xml_tag=tag,
            values=[v for v, _ in counter.most_common(max_values)],
            truncated=len(counter) > max_values,
            distinct_count=len(counter),
        )
    inv["enumerations"] = enums

    inv["users_seen"] = {
        tag: [u for u, _ in c.most_common(max_values)] for tag, c in users.items()
    }

    inv["structure"] = OrderedDict(
        max_comments_per_issue=max_comments,
        max_attachments_per_issue=max_attachments,
        subtasks_present=has_subtasks,
        parent_field_present=has_parent,
        issue_link_types={k: sorted(v) for k, v in link_types.items()},
    )

    # --- date format detection -----------------------------------------
    date_samples = []
    for tag in ("created", "updated", "resolved", "due"):
        date_samples.extend(tag_samples.get(tag, [])[:1])
    inv["dates"] = OrderedDict(
        samples_from_export=date_samples,
        export_format_note=(
            "Jira XML exports dates in RFC-822 form (e.g. 'Tue, 3 Jun 2025 10:15:23 -0700'). "
            "That is NOT an import format. Convert to a single consistent format and declare "
            "the matching pattern in the import wizard's Date format box."
        ),
        recommended_import_format="dd/MMM/yy h:mm a",
        recommended_example="03/Jun/25 10:15 AM",
        warning=(
            "In Java's SimpleDateFormat, MM is month and mm is minute. A lowercase mm in the "
            "month position silently produces wrong dates rather than an error."
        ),
    )

    return inv


def build_template_header(inv, include_status=False):
    """Header row for a create-mode CSV. Multi-value fields repeat."""
    cols = ["Issue ID", "Parent ID", "Project Key", "Issue Type", "Summary", "Description"]
    struct = inv["structure"]
    present = {f["xml_tag"]: f for f in inv["system_fields"]}

    def rep(tag, name, cap=None):
        f = present.get(tag)
        if not f:
            return
        n = max(1, f["max_values_per_issue"])
        if cap:
            n = min(n, cap)
        cols.extend([name] * n)

    for tag, name in (
        ("priority", "Priority"),
        ("assignee", "Assignee"),
        ("reporter", "Reporter"),
        ("due", "Due Date"),
    ):
        if tag in present:
            cols.append(name)

    rep("component", "Component")
    rep("fixVersion", "Fix Version")
    rep("version", "Affects Version")
    rep("labels", "Labels")

    for f in inv["custom_fields"]:
        n = max(1, f["max_values_per_issue"])
        cols.extend([f["import_column"]] * n)

    if struct["max_comments_per_issue"]:
        cols.extend(["Comment"] * struct["max_comments_per_issue"])

    if include_status:
        cols.extend(["Status", "Resolution"])

    for name in sorted(struct["issue_link_types"]):
        cols.append(f'Link "{name}"')

    return cols


def render_markdown(inv, header):
    L = []
    a = L.append
    a(f"# Jira field inventory - {inv['source_file']}")
    a("")
    a(f"Derived from {inv['issues_in_export']} issue(s) in the XML export.")
    if inv.get("issues_matching_query"):
        a(f"The originating query matched {inv['issues_matching_query']} issue(s) in total.")
    if inv.get("jira_build"):
        bits = ", ".join(f"{k}={v}" for k, v in inv["jira_build"].items())
        a(f"Instance build info: {bits}")
    a("")
    a("An inventory reflects only what appears in the sampled issues. A field that")
    a("exists in the instance but is empty across every sampled issue will be absent")
    a("here. Treat this as evidence, not as a complete schema.")
    a("")

    a("## System fields observed")
    a("")
    a("| XML tag | Import column | On issues | Max/issue | Sample |")
    a("|---|---|---|---|---|")
    special = []
    for f in inv["system_fields"]:
        if f["importable"] is False:
            col = "_not importable_"
        elif f["import_column"]:
            col = f["import_column"]
        elif f.get("note"):
            col = "_see note below_"
        else:
            col = "_(none)_"
        if f.get("note") and f["importable"] is not False:
            special.append(f)
        sample = (f["samples"][0][:40].replace("|", "\\|") if f["samples"] else "")
        a(f"| `{f['xml_tag']}` | {col} | {f['present_on_issues']} | {f['max_values_per_issue']} | {sample} |")
    a("")
    if special:
        a("### Fields needing special handling")
        a("")
        for f in special:
            a(f"- `{f['xml_tag']}`: {f['note']}")
        a("")

    a("## Custom fields observed")
    a("")
    if not inv["custom_fields"]:
        a("_None._")
    for f in inv["custom_fields"]:
        a(f"### {f['name']}  (`{f['id']}`)")
        a("")
        a(f"- Type: `{f['type_key']}` -> **{f['kind']}**")
        a(f"- {f['note']}")
        a(f"- Present on {f['present_on_issues']} issue(s); up to {f['max_values_per_issue']} value(s) per issue")
        if "allowed_values_seen" in f:
            shown = ", ".join(f"`{v}`" for v in f["allowed_values_seen"]) or "_none seen_"
            a(f"- Values seen ({f['distinct_value_count']} distinct): {shown}")
            if f.get("values_truncated"):
                a("  - _list truncated; rerun with a higher --max-values to see all_")
        elif f.get("samples"):
            a(f"- Samples: {', '.join('`' + s[:60] + '`' for s in f['samples'])}")
        a("")

    a("## Values that must match the destination")
    a("")
    a("Every value below already exists in the source instance. If the destination")
    a("project is the same one, reuse these verbatim. If it is a different project,")
    a("each value still has to exist there or the import wizard will need an explicit")
    a("value mapping.")
    a("")
    for label, e in inv["enumerations"].items():
        vals = ", ".join(f"`{v}`" for v in e["values"]) or "_none_"
        suffix = " _(truncated)_" if e["truncated"] else ""
        a(f"- **{label}** ({e['distinct_count']} distinct): {vals}{suffix}")
    a("")

    a("## Structure")
    a("")
    s = inv["structure"]
    a(f"- Max comments on one issue: {s['max_comments_per_issue']}")
    a(f"- Max attachments on one issue: {s['max_attachments_per_issue']}")
    a(f"- Sub-tasks present: {s['subtasks_present']}")
    a(f"- Parent field present: {s['parent_field_present']}")
    if s["issue_link_types"]:
        for name, dirs in s["issue_link_types"].items():
            a(f"- Link type `{name}`: {', '.join(dirs)}")
    else:
        a("- No issue links observed")
    a("")

    a("## Dates")
    a("")
    d = inv["dates"]
    if d["samples_from_export"]:
        a(f"- Export samples: {', '.join('`' + x + '`' for x in d['samples_from_export'])}")
    a(f"- {d['export_format_note']}")
    a(f"- Suggested import format: `{d['recommended_import_format']}` e.g. `{d['recommended_example']}`")
    a(f"- {d['warning']}")
    a("")

    a("## Users")
    a("")
    for tag, names in inv["users_seen"].items():
        a(f"- `{tag}`: {', '.join('`' + n + '`' for n in names) or '_none_'}")
    a("")
    a("User identifiers in an export are whatever the source instance uses. Jira Cloud")
    a("imports generally need an Atlassian account ID or an email address; Data Center")
    a("generally needs a username. Confirm which before writing an Assignee column.")
    a("")

    a("## Suggested CSV header")
    a("")
    a("Repeated column names are intentional: that is how Jira's CSV importer accepts")
    a("multiple values for one field. Trim this to the fields actually being set.")
    a("")
    a("```")
    a(",".join(header))
    a("```")
    return "\n".join(L)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("xml", help="Path to the Jira XML search export")
    p.add_argument("--out-dir", default="inventory", help="Directory to write outputs into")
    p.add_argument("--max-values", type=int, default=25, help="Cap on enumerated values listed per field")
    p.add_argument("--include-status", action="store_true",
                   help="Include Status/Resolution in the template header (admin External System Import only)")
    args = p.parse_args()

    inv = parse(args.xml, args.max_values)
    header = build_template_header(inv, include_status=args.include_status)

    os.makedirs(args.out_dir, exist_ok=True)
    with open(os.path.join(args.out_dir, "field-inventory.json"), "w", encoding="utf-8") as f:
        json.dump(inv, f, indent=2, ensure_ascii=False)
    with open(os.path.join(args.out_dir, "field-inventory.md"), "w", encoding="utf-8") as f:
        f.write(render_markdown(inv, header) + "\n")
    with open(os.path.join(args.out_dir, "template.csv"), "w", encoding="utf-8") as f:
        f.write(",".join(header) + "\n")

    print(f"Parsed {inv['issues_in_export']} issue(s) from {inv['source_file']}")
    print(f"  system fields:  {len(inv['system_fields'])}")
    print(f"  custom fields:  {len(inv['custom_fields'])}")
    print(f"  wrote {args.out_dir}/field-inventory.json, field-inventory.md, template.csv")


if __name__ == "__main__":
    main()
