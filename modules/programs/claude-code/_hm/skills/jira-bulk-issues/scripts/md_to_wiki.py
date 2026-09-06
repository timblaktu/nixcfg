#!/usr/bin/env python3
"""
Convert Markdown to Jira wiki markup, for description and comment fields in a
bulk import.

This exists because the two dialects disagree about asterisks -- Markdown's
`**bold**` is Jira's `*bold*`, and Markdown's `*italic*` is Jira's `_italic_` --
so pasting Markdown into an imported description produces italic text wrapped in
stray asterisks that imports cleanly and reads wrong.

Usage:
  python3 md_to_wiki.py notes.md                 # file to stdout
  python3 md_to_wiki.py notes.md -o notes.wiki
  cat notes.md | python3 md_to_wiki.py -
  python3 md_to_wiki.py --inline "See **the doc**"

Anything it could not translate is reported on stderr with a line number, so the
remainder can be fixed by hand rather than silently mangled.
"""

import argparse
import re
import sys

warnings = []


def warn(lineno, msg):
    warnings.append(f"line {lineno}: {msg}")


def convert_inline(text, lineno=0):
    """Inline spans. Code spans are pulled out first so their contents are not
    reinterpreted, then restored at the end."""
    holds = []       # restored verbatim at the end
    def hold(m):
        holds.append("{{" + m.group(1) + "}}")
        return f"\x00{len(holds) - 1}\x00"

    text = re.sub(r"`([^`]+)`", hold, text)

    # Images before links: both use bracket syntax, image wins on the leading !
    text = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)", r"!\2!", text)
    # [label](url) -> [label|url]; bare [url](url) collapses to [url]
    def link(m):
        label, url = m.group(1), m.group(2)
        return f"[{url}]" if label in ("", url) else f"[{label}|{url}]"

    text = re.sub(r"\[([^\]]*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)", link, text)
    text = re.sub(r"<((?:https?|mailto):[^>\s]+)>", r"[\1]", text)

    if re.search(r"\[[^\]]+\]\[[^\]]*\]", text):
        warn(lineno, "reference-style link left as-is")

    # Emphasis. Bold is converted first and its output is parked in a
    # placeholder, because Jira bold is a single asterisk and the italic rule
    # below would otherwise re-match it and turn bold into italic.
    def park(s):
        holds.append(s)
        return f"\x00{len(holds) - 1}\x00"

    text = re.sub(r"\*\*\*(?=\S)(.+?)(?<=\S)\*\*\*",
                  lambda m: park(f"_*{m.group(1)}*_"), text)
    text = re.sub(r"\*\*(?=\S)(.+?)(?<=\S)\*\*",
                  lambda m: park(f"*{m.group(1)}*"), text)
    text = re.sub(r"__(?=\S)(.+?)(?<=\S)__",
                  lambda m: park(f"*{m.group(1)}*"), text)
    # Then single-marker italics -> underscore form.
    text = re.sub(r"(?<![\*\w])\*(?=\S)([^\*]+?)(?<=\S)\*(?![\*\w])", r"_\1_", text)
    text = re.sub(r"(?<![_\w])_(?=\S)([^_]+?)(?<=\S)_(?![_\w])", r"_\1_", text)

    text = re.sub(r"~~(?=\S)(.+?)(?<=\S)~~", r"-\1-", text)

    for i, parked in enumerate(holds):
        text = text.replace(f"\x00{i}\x00", parked)
    return text


def convert(md):
    out = []
    in_fence = False
    fence_marker = None
    table_buf = []

    lines = md.splitlines()

    def flush_table():
        """Markdown table -> Jira table. Header row uses || delimiters."""
        if not table_buf:
            return
        rows = []
        for raw in table_buf:
            cells = [c.strip() for c in raw.strip().strip("|").split("|")]
            rows.append(cells)
        if len(rows) >= 2 and all(re.fullmatch(r":?-{2,}:?", c) for c in rows[1]):
            out.append("||" + "||".join(rows[0]) + "||")
            body = rows[2:]
        else:
            body = rows
        for cells in body:
            out.append("|" + "|".join(c if c else " " for c in cells) + "|")
        table_buf.clear()

    for n, line in enumerate(lines, start=1):
        # fenced code
        fence = re.match(r"^\s*(```|~~~)\s*([\w+-]*)\s*$", line)
        if fence:
            flush_table()
            if not in_fence:
                in_fence, fence_marker = True, fence.group(1)
                lang = fence.group(2)
                out.append("{code:" + lang + "}" if lang else "{code}")
            elif fence.group(1) == fence_marker:
                in_fence, fence_marker = False, None
                out.append("{code}")
            else:
                out.append(line)
            continue
        if in_fence:
            out.append(line)
            continue

        if re.match(r"^\s*\|.*\|\s*$", line):
            table_buf.append(line)
            continue
        flush_table()

        # headings
        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m:
            out.append(f"h{len(m.group(1))}. {convert_inline(m.group(2), n)}")
            continue

        # horizontal rule
        if re.match(r"^\s*([-*_])\s*(?:\1\s*){2,}$", line):
            out.append("----")
            continue

        # blockquote
        m = re.match(r"^\s*>\s?(.*)$", line)
        if m:
            out.append("bq. " + convert_inline(m.group(1), n))
            continue

        # lists; two spaces of indent per nesting level
        m = re.match(r"^(\s*)([-*+])\s+(.*)$", line)
        if m:
            depth = len(m.group(1)) // 2 + 1
            out.append("*" * depth + " " + convert_inline(m.group(3), n))
            continue
        m = re.match(r"^(\s*)(\d+)[.)]\s+(.*)$", line)
        if m:
            depth = len(m.group(1)) // 2 + 1
            out.append("#" * depth + " " + convert_inline(m.group(3), n))
            continue

        # indented code block
        if re.match(r"^ {4,}\S", line) and out and not out[-1].strip():
            warn(n, "indented code block emitted as plain text; use a fenced block")

        converted = convert_inline(line, n)
        if re.search(r"<[a-zA-Z/][^>]*>", converted):
            warn(n, "HTML tag left as-is; Jira will show it literally")
        out.append(converted)

    flush_table()
    if in_fence:
        warn(len(lines), "unclosed code fence; appended a closing {code}")
        out.append("{code}")
    return "\n".join(out)


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("input", nargs="?", help="Markdown file, or - for stdin")
    p.add_argument("-o", "--output", help="Write here instead of stdout")
    p.add_argument("--inline", help="Convert this string instead of a file")
    p.add_argument("--quiet", action="store_true", help="Suppress warnings")
    args = p.parse_args()

    if args.inline is not None:
        src = args.inline
    elif args.input in (None, "-"):
        src = sys.stdin.read()
    else:
        with open(args.input, encoding="utf-8") as f:
            src = f.read()

    result = convert(src)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(result + "\n")
    else:
        print(result)

    if warnings and not args.quiet:
        print(f"\n{len(warnings)} item(s) needing a look:", file=sys.stderr)
        for w in warnings:
            print(f"  {w}", file=sys.stderr)


if __name__ == "__main__":
    main()
