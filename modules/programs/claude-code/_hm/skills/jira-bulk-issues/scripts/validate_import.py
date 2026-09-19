#!/usr/bin/env python3
"""
Check a bulk-import CSV against a field inventory derived from an XML export,
before anyone uploads it to Jira.

The import wizard's own validation step catches a lot, but it catches it after a
human has clicked through five screens of mapping, and some classes of error
(wrong month/minute pattern, a select value that does not exist, a Parent ID that
points nowhere) either fail late or succeed with wrong data. Catching them here
is cheaper.

Usage:
  python3 validate_import.py issues.csv --inventory inventory/field-inventory.json
  python3 validate_import.py issues.csv --inventory inv.json --date-format "dd/MMM/yy h:mm a"

Exit status is 1 if any error-level finding is reported, 0 otherwise.
Warnings do not affect exit status.
"""

import argparse
import csv
import json
import re
import sys
from collections import Counter, defaultdict

# Java SimpleDateFormat -> Python strptime, for the patterns people actually use.
JAVA_TO_PY = [
    ("yyyy", "%Y"), ("yy", "%y"),
    ("MMM", "%b"), ("MM", "%m"),
    ("dd", "%d"),
    ("HH", "%H"), ("hh", "%I"), ("h", "%I"),
    ("mm", "%M"), ("ss", "%S"),
    ("a", "%p"),
]

DATE_COLUMNS = {
    "due date", "date created", "date modified", "date resolved",
    "created", "updated", "resolved", "due",
}

MULTI_VALUE_COLUMNS = {
    "component", "components", "fix version", "fix version/s", "affects version",
    "affects version/s", "labels", "comment", "attachment",
}


def java_to_strptime(fmt):
    out, i = [], 0
    while i < len(fmt):
        for j, p in JAVA_TO_PY:
            if fmt.startswith(j, i):
                out.append(p)
                i += len(j)
                break
        else:
            out.append(fmt[i])
            i += 1
    return "".join(out)


def norm(s):
    return re.sub(r"\s+", " ", s.strip().lower())


class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []
        self.notes = []

    def error(self, msg):
        self.errors.append(msg)

    def warn(self, msg):
        self.warnings.append(msg)

    def note(self, msg):
        self.notes.append(msg)

    def emit(self):
        for label, items in (("ERROR", self.errors), ("WARN", self.warnings), ("NOTE", self.notes)):
            for m in items:
                print(f"{label}: {m}")
        print()
        print(f"{len(self.errors)} error(s), {len(self.warnings)} warning(s), {len(self.notes)} note(s)")
        return 1 if self.errors else 0


def load_inventory(path):
    if not path:
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def allowed_value_map(inv):
    """column name (normalized) -> set of values that exist in the instance."""
    m = {}
    if not inv:
        return m
    for label, e in inv.get("enumerations", {}).items():
        if not e.get("truncated"):
            m[norm(label)] = set(e["values"])
    # common aliases
    for src, dsts in (
        ("issue type", ["type", "issuetype"]),
        ("fix version", ["fix version/s", "fixversion"]),
        ("affects version", ["affects version/s", "affectsversion", "version"]),
        ("component", ["components", "component/s"]),
    ):
        if norm(src) in m:
            for d in dsts:
                m.setdefault(norm(d), m[norm(src)])
    for f in inv.get("custom_fields", []):
        if "allowed_values_seen" in f and not f.get("values_truncated"):
            m[norm(f["name"])] = set(f["allowed_values_seen"])
    return m


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("csvfile")
    p.add_argument("--inventory", help="field-inventory.json from inventory_export.py")
    p.add_argument("--date-format", default="dd/MMM/yy h:mm a",
                   help="Java date pattern you will type into the import wizard")
    p.add_argument("--strict-values", action="store_true",
                   help="Treat unknown select values as errors rather than warnings")
    args = p.parse_args()

    r = Report()
    inv = load_inventory(args.inventory)
    allowed = allowed_value_map(inv)

    with open(args.csvfile, "rb") as f:
        raw = f.read()
    if raw.startswith(b"\xef\xbb\xbf"):
        r.warn("File starts with a UTF-8 BOM. Some importer versions read the first header "
               "cell with the BOM attached and then fail to match it. Save without a BOM.")
        raw = raw[3:]
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        r.error("File is not valid UTF-8. Re-save as UTF-8; the wizard's encoding dropdown "
                "must match whatever you choose.")
        return r.emit()
    if "\r\n" not in text and "\n" in text:
        r.note("Line endings are LF. That is fine.")

    rows = list(csv.reader(text.splitlines(True)))
    if not rows:
        r.error("File is empty.")
        return r.emit()

    header = rows[0]
    data = rows[1:]
    if not data:
        r.error("No data rows.")
        return r.emit()

    r.note(f"{len(data)} data row(s), {len(header)} column(s).")

    # --- header checks --------------------------------------------------
    if not any(norm(h) == "summary" for h in header):
        r.error("No Summary column. Every import row needs a summary; the importer will "
                "reject rows without one.")

    counts = Counter(norm(h) for h in header)
    for name, n in counts.items():
        if n > 1 and name not in MULTI_VALUE_COLUMNS and not (inv and _is_multi_cf(inv, name)):
            r.warn(f"Column '{name}' repeats {n} times. Repeats are only meaningful for fields "
                   f"that accept multiple values; for single-value fields the importer keeps "
                   f"one and silently drops the rest.")

    has_key = any(norm(h) in ("issue key", "key", "issuekey") for h in header)
    if has_key:
        r.warn("An Issue Key column is present. This makes the import an UPDATE of existing "
               "issues, not a create. Confirm that is intended, and note that updates replace "
               "rather than merge some fields.")

    id_idx = [i for i, h in enumerate(header) if norm(h) in ("issue id", "issueid")]
    parent_idx = [i for i, h in enumerate(header) if norm(h) in ("parent id", "parentid")]
    if parent_idx and not id_idx:
        r.error("Parent ID column present without an Issue ID column. Parent references resolve "
                "against Issue ID values within the same file, so both are required.")

    unknown_cols = []
    if inv:
        known = {norm(f["import_column"]) for f in inv["system_fields"] if f.get("import_column")}
        known |= {norm(f["import_column"]) for f in inv["custom_fields"]}
        known |= {"issue id", "parent id", "project key", "project name", "comment",
                  "attachment", "epic link", "epic name", "summary", "description"}
        for h in header:
            n = norm(h)
            if n and n not in known and not n.startswith('link "') and not n.startswith("link '"):
                unknown_cols.append(h)
    if unknown_cols:
        r.warn("Columns not seen anywhere in the XML export: "
               + ", ".join(sorted(set(unknown_cols)))
               + ". They may still exist in the instance but be empty on every sampled issue. "
                 "Confirm each one is on the destination project's create screen, or the "
                 "wizard will not offer it in the field mapping dropdown.")

    # --- row checks -----------------------------------------------------
    py_fmt = java_to_strptime(args.date_format)
    from datetime import datetime

    seen_ids, dup_ids = set(), set()
    parent_refs = []
    summary_idx = next((i for i, h in enumerate(header) if norm(h) == "summary"), None)
    bad_values = defaultdict(set)

    for rn, row in enumerate(data, start=2):
        if len(row) != len(header):
            r.error(f"Row {rn}: {len(row)} field(s) but the header has {len(header)}. "
                    f"Usually an unquoted comma or an unescaped quote.")
            continue

        if summary_idx is not None and not row[summary_idx].strip():
            is_sub = parent_idx and row[parent_idx[0]].strip()
            if not is_sub:
                r.error(f"Row {rn}: empty Summary.")

        for i in id_idx:
            v = row[i].strip()
            if v:
                if v in seen_ids:
                    dup_ids.add(v)
                seen_ids.add(v)
        for i in parent_idx:
            v = row[i].strip()
            if v:
                parent_refs.append((rn, v))
                for j in id_idx:
                    if row[j].strip():
                        r.error(f"Row {rn}: has both an Issue ID and a Parent ID. A child row "
                                f"should leave Issue ID blank.")
                        break

        for i, h in enumerate(header):
            n = norm(h)
            v = row[i].strip()
            if not v:
                continue
            if n in DATE_COLUMNS:
                try:
                    datetime.strptime(v, py_fmt)
                except ValueError:
                    r.error(f"Row {rn}: '{h}' value {v!r} does not parse as "
                            f"'{args.date_format}' (strptime '{py_fmt}').")
            if n == "comment":
                parts = v.split(";", 2)
                if len(parts) < 3:
                    r.warn(f"Row {rn}: Comment value does not look like "
                           f"'date;author;body'. Jira will attribute it to the importing "
                           f"user with the import timestamp.")
                else:
                    try:
                        datetime.strptime(parts[0].strip(), py_fmt)
                    except ValueError:
                        r.warn(f"Row {rn}: Comment date {parts[0].strip()!r} does not match "
                               f"the declared date format.")
            if n in allowed and v not in allowed[n] and v != "<<!clear!>>":
                bad_values[h].add(v)

    if dup_ids:
        r.error("Duplicate Issue ID values: " + ", ".join(sorted(dup_ids))
                + ". Each Issue ID must be unique within the file.")
    missing = sorted({v for _, v in parent_refs if v not in seen_ids})
    if missing:
        r.error("Parent ID values with no matching Issue ID in this file: "
                + ", ".join(missing)
                + ". Parent references do not resolve against real Jira keys during a create "
                  "import; they resolve against Issue ID values in the same file.")

    for col, vals in bad_values.items():
        msg = (f"Column '{col}' contains value(s) not seen in the export: "
               + ", ".join(sorted(repr(v) for v in vals))
               + ". If they do not exist in the destination project, the wizard will need an "
                 "explicit value mapping, or the import will fail on those rows.")
        (r.error if args.strict_values else r.warn)(msg)

    return r.emit()


def _is_multi_cf(inv, normalized_name):
    for f in inv.get("custom_fields", []):
        if norm(f["name"]) == normalized_name:
            return f["kind"] in ("multiselect", "multiuser", "multigroup")
    return False


if __name__ == "__main__":
    sys.exit(main())
