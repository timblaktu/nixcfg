#!/usr/bin/env python3
"""DrawIO diagram generator — converts compact JSON specs to .drawio.svg files.

Subcommands:
    generate  — Create .drawio.svg from JSON spec (stdin or --input)
    extract   — Decode content attribute from .drawio.svg to raw mxFile XML
    inject    — Re-inject content attribute into .drawio.svg from mxFile XML (stdin)
    verify    — Check .drawio.svg for common issues (orphan, missing cells)
    encode    — HTML-encode mxFile XML (stdin) for content attribute
    presets   — List available style presets

Usage:
    echo '{"page":...,"cells":[...]}' | drawio_gen.py generate --output diagram.drawio.svg
    drawio_gen.py extract diagram.drawio.svg
    drawio_gen.py verify diagram.drawio.svg
    drawio_gen.py presets
"""

import argparse
import html
import json
import os
import re
import subprocess
import sys
from datetime import datetime

# ── Style Presets ──────────────────────────────────────────────────────────────

BOX_PRESETS = {
    "green":       {"fillColor": "#d5e8d4", "strokeColor": "#82b366"},
    "dark-green":  {"fillColor": "#2d5016", "strokeColor": "#82b366", "fontColor": "#e0e0e0"},
    "red":         {"fillColor": "#f8cecc", "strokeColor": "#b85450"},
    "dark-red":    {"fillColor": "#4a1a1a", "strokeColor": "#b85450", "fontColor": "#e0e0e0"},
    "blue":        {"fillColor": "#dae8fc", "strokeColor": "#6c8ebf"},
    "dark-blue":   {"fillColor": "#1a3a5c", "strokeColor": "#6c8ebf", "fontColor": "#e0e0e0"},
    "purple":      {"fillColor": "#e1d5e7", "strokeColor": "#9673a6"},
    "dark-purple": {"fillColor": "#2e1a3a", "strokeColor": "#9673a6", "fontColor": "#e0e0e0"},
    "yellow":      {"fillColor": "#fff2cc", "strokeColor": "#d6b656"},
    "dark-yellow": {"fillColor": "#3d3d1a", "strokeColor": "#d6b656", "fontColor": "#e0e0e0"},
    "orange":      {"fillColor": "#ffe6cc", "strokeColor": "#d79b00"},
    "dark-bg":     {"fillColor": "#1a1a2e", "strokeColor": "#4a86c8", "fontColor": "#e0e0e0"},
    "dark-fg":     {"fillColor": "#1a1a2e", "strokeColor": "#4a86c8", "fontColor": "#e0e0e0"},
    "white":       {"fillColor": "#ffffff", "strokeColor": "#666666"},
    "none":        {"fillColor": "none", "strokeColor": "none"},
}

EDGE_PRESETS = {
    "blue-arrow":    {"strokeColor": "#6c8ebf", "endArrow": "classic"},
    "purple-arrow":  {"strokeColor": "#9673a6", "endArrow": "classic"},
    "green-arrow":   {"strokeColor": "#82b366", "endArrow": "classic"},
    "green-dashed":  {"strokeColor": "#82b366", "endArrow": "classic", "dashed": "1"},
    "red-arrow":     {"strokeColor": "#b85450", "endArrow": "classic"},
    "orange-arrow":  {"strokeColor": "#d79b00", "endArrow": "classic"},
    "no-arrow":      {"strokeColor": "#666666", "endArrow": "none"},
    "dashed":        {"strokeColor": "#666666", "endArrow": "classic", "dashed": "1"},
}

# ── XML Generation ─────────────────────────────────────────────────────────────

def _attr(key, val):
    """Format a single XML attribute."""
    return f'{key}="{html.escape(str(val), quote=True)}"'


def _style_str(parts):
    """Build a DrawIO style string from a dict."""
    return ";".join(f"{k}={v}" for k, v in parts.items()) + ";"


def _build_box_style(cell):
    """Build style for a box cell (rounded rect by default)."""
    base = {
        "rounded": "1",
        "whiteSpace": "wrap",
        "html": "1",
    }
    # Apply preset
    preset_name = cell.get("preset")
    if preset_name and preset_name in BOX_PRESETS:
        base.update(BOX_PRESETS[preset_name])
    # Apply explicit overrides
    if "style" in cell:
        base.update({k: str(v) for k, v in cell["style"].items()})
    return _style_str(base)


def _build_container_style(cell):
    """Build style for a container cell."""
    base = {
        "rounded": "1",
        "whiteSpace": "wrap",
        "html": "1",
        "container": "1",
        "collapsible": "0",
        "verticalAlign": "top",
        "fontStyle": "1",
    }
    preset_name = cell.get("preset")
    if preset_name and preset_name in BOX_PRESETS:
        base.update(BOX_PRESETS[preset_name])
    if "style" in cell:
        base.update({k: str(v) for k, v in cell["style"].items()})
    return _style_str(base)


def _build_text_style(cell):
    """Build style for a text-only cell."""
    base = {
        "text": "",
        "html": "1",
        "align": "center",
        "verticalAlign": "middle",
        "whiteSpace": "wrap",
        "rounded": "0",
    }
    preset_name = cell.get("preset")
    if preset_name and preset_name in BOX_PRESETS:
        # Only apply font/stroke colors for text, not fill
        p = BOX_PRESETS[preset_name]
        if "fontColor" in p:
            base["fontColor"] = p["fontColor"]
    if "style" in cell:
        base.update({k: str(v) for k, v in cell["style"].items()})
    return _style_str(base)


def _build_edge_style(cell):
    """Build style for an edge cell."""
    base = {
        "edgeStyle": "orthogonalEdgeStyle",
        "rounded": "0",
        "orthogonalLoop": "1",
        "jettySize": "auto",
        "html": "1",
        "endArrow": "classic",
    }
    preset_name = cell.get("preset")
    if preset_name and preset_name in EDGE_PRESETS:
        base.update(EDGE_PRESETS[preset_name])
    # Anchor points
    if "exit" in cell:
        base["exitX"] = str(cell["exit"][0])
        base["exitY"] = str(cell["exit"][1])
        base["exitDx"] = "0"
        base["exitDy"] = "0"
    if "entry" in cell:
        base["entryX"] = str(cell["entry"][0])
        base["entryY"] = str(cell["entry"][1])
        base["entryDx"] = "0"
        base["entryDy"] = "0"
    if "style" in cell:
        base.update({k: str(v) for k, v in cell["style"].items()})
    return _style_str(base)


def _xml_escape_value(text):
    """Escape text for use as an XML attribute value (the value= attribute)."""
    # DrawIO uses html=1, so labels can contain HTML. We only need to escape
    # XML-special chars that would break the attribute boundary.
    return (text
            .replace("&", "&amp;")
            .replace('"', "&quot;")
            .replace("<", "&lt;")
            .replace(">", "&gt;"))


def _build_cell_xml(cell, indent="        "):
    """Generate mxCell XML for a single cell spec."""
    ctype = cell.get("type", "box")
    cid = cell["id"]
    label = cell.get("label", "")
    parent = cell.get("parent", "1")

    if ctype == "edge":
        style = _build_edge_style(cell)
        attrs = [
            _attr("id", cid),
            _attr("value", label),
            _attr("style", style),
            'edge="1"',
            _attr("parent", parent),
        ]
        if "source" in cell:
            attrs.append(_attr("source", cell["source"]))
        if "target" in cell:
            attrs.append(_attr("target", cell["target"]))
        lines = [f'{indent}<mxCell {" ".join(attrs)}>']
        lines.append(f'{indent}  <mxGeometry relative="1" as="geometry"/>')
        lines.append(f'{indent}</mxCell>')
    else:
        if ctype == "container":
            style = _build_container_style(cell)
        elif ctype == "text":
            style = _build_text_style(cell)
        else:  # "box" or default
            style = _build_box_style(cell)

        attrs = [
            _attr("id", cid),
            _attr("value", label),
            _attr("style", style),
            'vertex="1"',
            _attr("parent", parent),
        ]
        x = cell.get("x", 0)
        y = cell.get("y", 0)
        w = cell.get("w", 120)
        h = cell.get("h", 60)
        lines = [f'{indent}<mxCell {" ".join(attrs)}>']
        lines.append(
            f'{indent}  <mxGeometry x="{x}" y="{y}" '
            f'width="{w}" height="{h}" as="geometry"/>'
        )
        lines.append(f'{indent}</mxCell>')

    return "\n".join(lines)


def build_mxfile(spec):
    """Build complete mxFile XML from a JSON spec dict."""
    page = spec.get("page", {})
    pw = page.get("width", 850)
    ph = page.get("height", 600)
    name = page.get("name", "Page-1")
    bg = page.get("background", "#ffffff")
    today = datetime.now().strftime("%Y-%m-%d")

    cells_xml = []
    for cell in spec.get("cells", []):
        cells_xml.append(_build_cell_xml(cell))

    mxfile = f'''<mxfile host="Claude" modified="{today}">
  <diagram name="{html.escape(name)}" id="diagram-1">
    <mxGraphModel dx="{pw}" dy="{ph}" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="{pw}" pageHeight="{ph}" background="{bg}">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
{chr(10).join(cells_xml)}
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>'''
    return mxfile


def encode_content(mxfile_xml):
    """HTML-entity-encode mxFile XML for the SVG content attribute."""
    return (mxfile_xml
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
            .replace("\n", "&#10;"))


def decode_content(encoded):
    """Decode HTML-entity-encoded content attribute back to XML."""
    return html.unescape(encoded)


def build_svg(mxfile_xml, page_spec):
    """Build a complete .drawio.svg file with content attribute."""
    pw = page_spec.get("width", 850)
    ph = page_spec.get("height", 600)
    bg = page_spec.get("background", "#ffffff")
    encoded = encode_content(mxfile_xml)

    return f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
     version="1.1" width="{pw}px" height="{ph}px"
     viewBox="-0.5 -0.5 {pw} {ph}"
     content="{encoded}"
     style="background-color: {bg};">
  <defs/>
  <g>
    <text x="{pw // 2}" y="{ph // 2}" text-anchor="middle" font-size="14" fill="#999">
      Run drawio-svg-sync to render this diagram
    </text>
  </g>
</svg>
'''

# ── File Operations ────────────────────────────────────────────────────────────

def extract_content_attr(filepath):
    """Extract and decode the content attribute from a .drawio.svg file."""
    with open(filepath, "r", encoding="utf-8") as f:
        data = f.read()
    m = re.search(r'content="([^"]*)"', data)
    if not m:
        return None
    return decode_content(m.group(1))


def inject_content_attr(filepath, mxfile_xml):
    """Replace or add the content attribute in a .drawio.svg file."""
    with open(filepath, "r", encoding="utf-8") as f:
        data = f.read()
    encoded = encode_content(mxfile_xml)
    if re.search(r'content="[^"]*"', data):
        data = re.sub(r'content="[^"]*"', f'content="{encoded}"', data)
    else:
        # Insert content attribute into the <svg> tag
        data = re.sub(r'(<svg\b[^>]*?)(>)', rf'\1 content="{encoded}"\2', data, count=1)
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(data)


def verify_file(filepath):
    """Verify a .drawio.svg file for common issues. Returns (ok, messages)."""
    messages = []
    with open(filepath, "r", encoding="utf-8") as f:
        data = f.read()

    # Check content attribute exists
    m = re.search(r'content="([^"]*)"', data)
    if not m:
        messages.append("ERROR: No content attribute found — file is orphaned/view-only")
        return False, messages

    decoded = decode_content(m.group(1))

    # Check required cells
    if '<mxCell id="0"' not in decoded:
        messages.append("ERROR: Missing root cell (id=0)")
    if '<mxCell id="1"' not in decoded:
        messages.append("ERROR: Missing default parent cell (id=1)")

    # Check mxfile structure
    if "<mxfile" not in decoded:
        messages.append("ERROR: No <mxfile> element in content")
    if "<mxGraphModel" not in decoded:
        messages.append("ERROR: No <mxGraphModel> element in content")

    # Check for SVG body (rendered content)
    svg_body = re.sub(r'content="[^"]*"', '', data)
    has_rendered = bool(re.search(r'<(rect|path|ellipse|line|polygon|image)\b', svg_body))
    if not has_rendered:
        messages.append("WARNING: SVG body has no graphical elements — needs drawio-svg-sync render")

    # Collect all cell IDs and check for source/target references
    cell_ids = set(re.findall(r'id="([^"]+)"', decoded))
    sources = set(re.findall(r'source="([^"]+)"', decoded))
    targets = set(re.findall(r'target="([^"]+)"', decoded))
    dangling = (sources | targets) - cell_ids
    if dangling:
        messages.append(f"WARNING: Dangling edge references: {', '.join(sorted(dangling))}")

    if not messages:
        messages.append("OK: File is valid")
        return True, messages

    has_errors = any(msg.startswith("ERROR") for msg in messages)
    return not has_errors, messages


# ── CLI ────────────────────────────────────────────────────────────────────────

def cmd_generate(args):
    """Generate a .drawio.svg from JSON spec."""
    if args.input:
        with open(args.input, "r", encoding="utf-8") as f:
            spec = json.load(f)
    else:
        spec = json.load(sys.stdin)

    page = spec.get("page", {})
    mxfile = build_mxfile(spec)
    svg = build_svg(mxfile, page)

    outpath = args.output
    if not outpath:
        outpath = "/dev/stdout"

    if outpath == "/dev/stdout":
        sys.stdout.write(svg)
    else:
        with open(outpath, "w", encoding="utf-8") as f:
            f.write(svg)
        print(f"Generated: {outpath}", file=sys.stderr)

        if args.render:
            _render_and_reinject(outpath)


def _render_and_reinject(filepath):
    """Run drawio-svg-sync, then re-inject content attribute."""
    # Save content before render (drawio-svg-sync preserves it, but be safe)
    mxfile_xml = extract_content_attr(filepath)
    if not mxfile_xml:
        print("ERROR: No content attribute to preserve", file=sys.stderr)
        sys.exit(1)

    print(f"Rendering with drawio-svg-sync...", file=sys.stderr)
    result = subprocess.run(
        ["nix", "run", "github:timblaktu/drawio-svg-sync", "--", filepath],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"drawio-svg-sync failed:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    print(result.stderr, file=sys.stderr, end="")

    # Verify content survived rendering; re-inject if stripped
    current = extract_content_attr(filepath)
    if not current:
        print("Re-injecting content attribute (stripped by renderer)...", file=sys.stderr)
        inject_content_attr(filepath, mxfile_xml)

    # Final verification
    ok, msgs = verify_file(filepath)
    for msg in msgs:
        print(f"  {msg}", file=sys.stderr)
    if not ok:
        sys.exit(1)


def cmd_extract(args):
    """Extract and print decoded mxFile XML from a .drawio.svg."""
    xml = extract_content_attr(args.file)
    if xml is None:
        print("ERROR: No content attribute found", file=sys.stderr)
        sys.exit(1)
    print(xml)


def cmd_inject(args):
    """Read mxFile XML from stdin and inject into .drawio.svg."""
    mxfile_xml = sys.stdin.read()
    inject_content_attr(args.file, mxfile_xml)
    print(f"Injected content attribute into: {args.file}", file=sys.stderr)


def cmd_verify(args):
    """Verify a .drawio.svg file."""
    ok, msgs = verify_file(args.file)
    for msg in msgs:
        print(msg)
    sys.exit(0 if ok else 1)


def cmd_encode(args):
    """Read mxFile XML from stdin and print HTML-encoded version."""
    xml = sys.stdin.read()
    print(encode_content(xml))


def cmd_presets(args):
    """List available style presets."""
    fmt = args.format
    if fmt == "json":
        print(json.dumps({"box": BOX_PRESETS, "edge": EDGE_PRESETS}, indent=2))
    else:
        print("Box/Container presets:")
        for name, styles in sorted(BOX_PRESETS.items()):
            fill = styles.get("fillColor", "-")
            stroke = styles.get("strokeColor", "-")
            fc = styles.get("fontColor", "")
            extra = f"  fontColor={fc}" if fc else ""
            print(f"  {name:15s}  fill={fill}  stroke={stroke}{extra}")
        print("\nEdge presets:")
        for name, styles in sorted(EDGE_PRESETS.items()):
            stroke = styles.get("strokeColor", "-")
            arrow = styles.get("endArrow", "-")
            dashed = "dashed" if styles.get("dashed") else "solid"
            print(f"  {name:15s}  stroke={stroke}  arrow={arrow}  {dashed}")


def main():
    parser = argparse.ArgumentParser(
        prog="drawio_gen",
        description="Generate DrawIO .drawio.svg files from compact JSON specs",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # generate
    p_gen = sub.add_parser("generate", help="Create .drawio.svg from JSON spec")
    p_gen.add_argument("--input", "-i", help="JSON spec file (default: stdin)")
    p_gen.add_argument("--output", "-o", help="Output .drawio.svg file (default: stdout)")
    p_gen.add_argument("--render", "-r", action="store_true",
                       help="Run drawio-svg-sync after generating")
    p_gen.set_defaults(func=cmd_generate)

    # extract
    p_ext = sub.add_parser("extract", help="Decode content attr from .drawio.svg")
    p_ext.add_argument("file", help="Path to .drawio.svg file")
    p_ext.set_defaults(func=cmd_extract)

    # inject
    p_inj = sub.add_parser("inject", help="Inject content attr into .drawio.svg from stdin")
    p_inj.add_argument("file", help="Path to .drawio.svg file")
    p_inj.set_defaults(func=cmd_inject)

    # verify
    p_ver = sub.add_parser("verify", help="Verify .drawio.svg for common issues")
    p_ver.add_argument("file", help="Path to .drawio.svg file")
    p_ver.set_defaults(func=cmd_verify)

    # encode
    p_enc = sub.add_parser("encode", help="HTML-encode mxFile XML from stdin")
    p_enc.set_defaults(func=cmd_encode)

    # presets
    p_pre = sub.add_parser("presets", help="List available style presets")
    p_pre.add_argument("--format", choices=["text", "json"], default="text",
                       help="Output format (default: text)")
    p_pre.set_defaults(func=cmd_presets)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
