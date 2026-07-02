# Plan 047 — Diagram skill review, deploy, and quality-barometer test suite

Status: IN_PROGRESS
Owner: Tim
Worktree: /home/tim/src/nixcfg
Working branch: diagram-skill-integrations  (base: origin/main; do NOT work on main)
Mode: A (human-attended /next-task). NOT burndown-eligible — T3 (hm switch) is
host-specific and T5 is interactive user testing.

## Context (self-contained — a fresh session needs only this + CLAUDE.md + repo)

The `diagram` skill lives at
`modules/programs/claude-code/_hm/skills/diagram/` and is deployed to each
Claude account's `skills/` dir by the activation script in
`modules/programs/claude-code/_hm/skills.nix` (files are ENUMERATED there — any
new file must be added to the `diagram.files` attrset or it will not deploy).

Commit `761a3bb` (this branch) integrated four capabilities adapted from
Agents365-ai/drawio-skill (MIT) — a local clone is at `/home/tim/src/drawio-skill`
for reference:

1. **Structural linter** `validate.py` — deterministic lint (dangling/duplicate/
   reserved IDs, broken parents, bad geometry, sibling overlaps, edge crossing /
   edge-through-vertex for waypointed edges). Reads this skill's `.drawio.svg` by
   decoding the `content=` attr first. `drawio_gen.py verify` delegates to it;
   `_render_and_reinject` runs it as a PRE-RENDER GATE (aborts on errors).
2. **Auto-layout** `autolayout.py` (Graphviz `dot`) + new `drawio_gen.py wrap`
   subcommand. Run under `nix shell nixpkgs#graphviz -c ...`. Palette inlined
   (upstream preset-file dep removed). SKILL.md Section 34.
3. **Vision self-check loop** — SKILL.md Section 15 rewritten: render -> validate
   -> rasterize to PNG (`drawio -x -f png --width 2000`) -> agent reads PNG ->
   auto-fix <=2 rounds -> present.
4. **Shape/AI-icon search** `shapesearch.py` (10k+ vendor shapes, data/
   shape-index.json.gz, Apache-2.0) + `aiicons.py` (lobe-icons, MIT). SKILL.md
   Section 35.

Pipeline invariant: files are `.drawio.svg` (editable mxfile HTML-entity-encoded
in the `content=` attr + rendered SVG body), rendered via
`nix run 'github:timblaktu/drawio-svg-sync' -- FILE`. Verify at each step with
`nix flake check --no-build` and `python3 -m py_compile *.py`.

Eval/switch note (from CLAUDE.md): the REAL host is `tim@pa161878-nixos`,
reached via `nixcfg-work` (`/home/tim/src/nixcfg-work`) with
`--override-input nixcfg /home/tim/src/nixcfg`. Serialize all nix invocations
(no concurrent nix). The pre-commit hook runs a full `nix flake check` (~2-4 min)
— allow time; do not `--no-verify`.

---

## Progress

| Task | Status | Definition of Done (checkable) |
|------|--------|--------------------------------|
| T1 Full review + findings | TASK:COMPLETE (2026-07-01) | Findings table below filled: every seeded risk resolved (confirmed/refuted with evidence) + any new findings, each with severity + recommendation. No code changes in T1 (VALIDATION != FIXING). |
| T2 Apply agreed improvements + commit | TASK:IN_PROGRESS | Agreed T1 fixes applied; `python3 -m py_compile` on all skill `.py` passes; `nix flake check --no-build` passes; committed on this branch; no AI attribution. |
| T3 Deploy (home-manager switch) | TASK:PENDING | `home-manager switch` (via nixcfg-work override-input) succeeds; deployed skill dir contains validate.py/autolayout.py/shapesearch.py/aiicons.py/data/*; `drawio_gen.py verify` runs from the deployed copy. |
| T4 Finalize quality-barometer suite | TASK:PENDING | Test suite + scoring rubric below reviewed/refined; expected outcomes concrete; recorded in this plan; ready for the user to run. |
| T5 Run the barometer (INTERACTIVE) | TASK:PENDING | USER runs the suite in a later session, scores each test against the rubric, records results in the Results section. `Interactive` — needs user judgment/vision. |

---

## T1 — Review dimensions and SEEDED findings

Review `SKILL.md` (3227 lines) + the 5 scripts. Resolve each seeded risk below
(the author already suspects these); add new findings as discovered.

### Seeded risk A (HIGH) — does the vision-loop rasterization actually work here?
Section 15 tells the agent to run `drawio -x -f png --width 2000 -o x.png f.svg`
to get a PNG to read. But the whole render path uses
`nix run 'github:timblaktu/drawio-svg-sync'` — a bare `drawio` binary is likely
NOT on PATH in this WSL env. The flagship HIGH feature is dead if it can't
rasterize. **Verify**: is there a working `.drawio.svg` -> PNG path the agent can
call? Candidates to test, in order:
  - `nix run 'github:timblaktu/drawio-svg-sync'` with a PNG flag (inspect its
    flags: `nix run 'github:timblaktu/drawio-svg-sync' -- --help`);
  - `nix run nixpkgs#drawio -- -x -f png --width 2000 -o x.png f.svg` (needs
    xvfb/headless — mirror the drawio-svg-sync approach);
  - rasterize the SVG body directly: `nix run nixpkgs#resvg -- f.svg x.png` or
    `rsvg-convert` / ImageMagick `convert`.
  **DoD for A**: one command is confirmed to produce a readable PNG from a
  `.drawio.svg`; Section 15 (and the Section 8 raster note) updated to the
  command that actually works. If none work headless, downgrade the loop to
  "ask user for screenshot" as primary and say so explicitly.

### Seeded risk B (MED) — can the agent Read an SVG as an image at all?
If the Read tool renders `.drawio.svg` directly, the PNG step may be unnecessary.
**Verify** whether Read accepts SVG; if yes, document reading the `.drawio.svg`
directly as the cheaper path and keep PNG as fallback.

### Seeded risk C (MED) — SKILL.md size (always-loaded context)
At 3227 lines SKILL.md is large for a skill that loads in full on every
invocation. Identify reference-heavy sections that can move to REFERENCE.md
(loaded on demand): candidates include the long per-topic example dumps
(Sections 17, 18, 32) and the multi-page boilerplate (14). **DoD for C**: a
concrete list of "move to REFERENCE.md" candidates with estimated line savings;
do NOT move in T1 (that is a T2 change if agreed).

### Seeded risk D (LOW) — graphviz invocation ergonomics
`autolayout.py` needs `dot`; docs say `nix shell nixpkgs#graphviz -c`. Confirm
the documented one-liners in Section 34 run verbatim. Consider whether the skill
should wrap this (e.g. a note that the agent must prefix the nix shell) to avoid
"dot not found" on first use.

### Seeded risk E (LOW) — repo's own diagram is non-embedded
`docs/diagrams/nixcfg-structure.drawio.svg` has NO `content=` attr (raw export,
orphaned/view-only) — `validate.py` flags it. Out of scope to fix here, but
record whether to re-export it editable as a follow-up.

### Findings (filled during T1 — 2026-07-01)

**Resolved: the vision loop is REAL.** A portable, drawio-native PNG rasterizer
is confirmed working in this WSL env. The command Section 15 documents today
(`drawio -x -f png ...` with a bare `drawio`) does NOT run — nothing puts
`drawio` on PATH here (everything shells out via `nix run/nix shell`). The
working command mirrors drawio-svg-sync's own render mechanism:

```bash
# CONFIRMED working (produces a faithful, readable PNG):
nix shell nixpkgs#drawio nixpkgs#xvfb-run -c \
  xvfb-run --auto-servernum drawio -x -f png --width 2000 -p 1 \
  -o /tmp/diagram-check.png diagram.drawio.svg
```
Both `--width 2000` and `--scale 2` work (tested). The GLX/EGL/ANGLE stderr
lines are harmless; export still returns exit 0 and a good PNG. Do NOT add
`--no-sandbox`/`--disable-gpu` — they break drawio's CLI arg parser
("input file/directory not found"). Non-drawio rasterizers are NOT viable:
`resvg` renders draw.io's `light-dark()` fills as solid black (illegible);
`convert`/`magick` cannot render label text (draw.io emits text via
`<foreignObject>` + a base64 `<image>` fallback → the literal "Text is not
SVG - cannot display" appears). Only draw.io's own renderer is faithful.

| # | Severity | Finding | Evidence | Recommendation | Agreed fix in T2? |
|---|----------|---------|----------|----------------|-------------------|
| A | HIGH | CONFIRMED. Section 15 (+ Section 8 raster note) prescribe `drawio -x -f png --width 2000` with a bare `drawio`, which is not on PATH here → the flagship vision loop would fail on first use. But a working portable command exists (above). | `command -v drawio` empty; the boxed nix-shell command produced a faithful readable PNG (`/tmp/diagram-barometer/mini.png`, mini-w2000.png 94KB); `resvg`→black fills, `convert`→"Text is not SVG"; drawio-svg-sync internally uses the identical `xvfb-run … drawio -x -f svg` mechanism. | T2: replace the Section 15 code block AND the Section 8 raster note with the nix-shell `drawio -x -f png` command above. Keep Section 33's Windows-`draw.io.exe` path as an alternative (works only if Windows draw.io is installed). The loop is real — do NOT downgrade it. | **YES** |
| B | MED | REFUTED (PNG step stays). The Read tool does NOT render `.drawio.svg` as an image — it returns the SVG XML as text. So the PNG rasterization step is REQUIRED, not skippable. | `Read /tmp/diagram-barometer/mini.svg` returned numbered XML source, not an image (Read's image support is PNG/JPG/PDF, not SVG). | T2 (optional, small): add one line to Section 15 stating Read cannot render `.drawio.svg` directly, so the PNG step is mandatory (prevents a future "just Read the svg" shortcut). | optional |
| C | MED | CONFIRMED. SKILL.md is 3226 lines, loaded in full every invocation. A `REFERENCE.md` (on-demand) already exists (~22KB), so the move target is established. Reference-heavy example sections dominate. | Section line counts: §6 Complete Creation Examples 177, §17 Grouping Pattern 233, §18 Rounded Container Label Positioning 105, §32 Custom Shape Containers/Stencils 73 (=588, ~18%); +§14 Multi-Page 164 → ~752 (~23%). | T2 (author's call on scope): move §6/§17/§18/§32 (and optionally §14) to REFERENCE.md, leaving a one-line pointer in SKILL.md. Do NOT move in T1. | **YES (scope TBD)** |
| D | LOW | REFUTED (docs adequate). Section 34's one-liner runs verbatim; `dot`-not-on-PATH is already handled by the documented `nix shell nixpkgs#graphviz -c` prefix. | `nix shell nixpkgs#graphviz -c bash -c 'python3 autolayout.py graph.json -o model.drawio'` → "wrote … (3 nodes, 2 edges)" exit 0; `py_compile` OK on all 5 scripts; `wrap`/`verify` subcommands and `--render`/`--output` flags exist and match docs. | No fix required. (Note only: `wrap --render` nests a separate `nix run …drawio-svg-sync` — serial, fine.) | no |
| E | LOW | CONFIRMED. `docs/diagrams/nixcfg-structure.drawio.svg` has no `content=` attr → `validate.py` flags it AND drawio PNG export yields no file (orphaned view-only export). | `grep -c content= …nixcfg-structure.drawio.svg` = 0; `drawio -x -f png` on it produced no output file. | Follow-up, OUT OF SCOPE for this plan: re-export it editable (round-trip through draw.io to embed `content=`, or regenerate via the skill). | no (follow-up) |
| F | LOW | NEW. `validate.py` and `autolayout.py` carry no per-file provenance/attribution; `shapesearch.py` (jgraph/drawio-mcp, Apache-2.0) and `aiicons.py` (lobe-icons, MIT) do. SKILL.md changelog credits Agents365-ai/drawio-skill (MIT) at skill level; upstream uses a single repo-level LICENSE. | `head` of each script; upstream `/home/tim/src/drawio-skill/LICENSE` (MIT, repo-level). | T2 (optional hygiene): add a one-line "Adapted from Agents365-ai/drawio-skill (MIT)" comment to `validate.py`/`autolayout.py` headers to match the other two. | optional |

### T2 agreed fix list (user-confirmed 2026-07-01)
- **A (firm):** rewrite Section 15 PNG code block + Section 8 raster note to the
  confirmed nix-shell `drawio -x -f png` command; keep Section 33 Windows path as
  alternative; do NOT downgrade the loop.
- **C (scope = §6/§17/§18/§32, ~588 lines):** move these four example-dump section
  bodies to REFERENCE.md, leaving each SKILL.md heading as a one-line pointer stub
  (no section renumbering → no broken `Section NN` cross-refs). §14 stays inline
  (procedural how-to, not an example dump).
- **B (include):** add a note to Section 15 that Read cannot render `.drawio.svg`
  as an image (returns XML) → PNG step mandatory.
- **F (include):** add "Adapted from Agents365-ai/drawio-skill (MIT)" provenance
  header to validate.py and autolayout.py.

**Other spot-checks:** no dangling `Section NN` references beyond 35; changelog
v1.11.0 matches what shipped (validate/autolayout/vision-loop/shape+icon search);
`verify`/`wrap`/`--render` docs match `drawio_gen.py` behavior. All 5 `.py`
compile.

Also spot-check: cross-references (Section N pointers) resolve; changelog v1.11.0
matches what shipped; `verify`/`wrap`/`--render` docs match `drawio_gen.py`
behavior; provenance headers present in all four vendored scripts.

---

## T4 — Quality-barometer test suite (candidate; refine in T4)

A reusable benchmark: each test is a natural-language request exercising one
capability, with an objective "good" bar. Run by giving the request to a fresh
session with the skill, then scoring the artifact. Keep artifacts under a scratch
dir (e.g. `/tmp/diagram-barometer/`), NOT committed.

| # | Capability | Request | Passes if |
|---|-----------|---------|-----------|
| B1 | Format auto-select (Mermaid) | "Diagram the TCP connection state machine." | Chooses **Mermaid** (simple state graph), not DrawIO. |
| B2 | Hand-placed DrawIO + palette + gate | "3-tier architecture: Web, API, Database, with a Cache between API and DB." | DrawIO `.drawio.svg`; orthogonal edges; palette colors; `verify` clean; renders. |
| B3 | Side-by-side comparison | "Before vs After: manual deploy (3 pains) vs CI/CD (3 wins), with transformation arrows." | Two aligned columns; dashed transform arrows; readable. |
| B4 | Auto-layout (dense) | "Lay out these 18 microservices and their call graph: <give edges>." | Uses `autolayout.py` + graphviz (not hand coords); grouped containers; `verify` warnings show **no** overlaps/crossings. |
| B5 | Vendor shape search | "AWS diagram: API Gateway -> Lambda -> DynamoDB, plus S3." | Uses `shapesearch.py` real AWS shapes (style contains `mxgraph.aws`), not generic boxes. |
| B6 | AI/LLM icons | "RAG app: user -> Claude -> LangChain -> Qdrant + Postgres." | Uses `aiicons.py` with `--embed` (self-contained), real brand logos. |
| B7 | Validate gate (NEGATIVE) | Hand it a model with a dangling edge + a duplicate ID; ask to render. | `verify` reports both as ERROR; `--render` **aborts** (does not render a broken file). |
| B8 | Vision self-check loop | "Put these 12 nodes with these 20 edges on one page" (crowded on purpose). | Skill rasterizes, reads it, does >=1 auto-fix round, and the final has visibly fewer overlaps than round 0. |
| B9 | Edit workflow | On B2's file: "Rename API to Gateway, make DB green, insert Redis between Gateway and DB." | Surgical `content=`-attr edit; connector split A->new->B; `verify` clean; only intended cells changed. |
| B10 | Multi-page | "Network: page 1 physical topology, page 2 logical VLANs." | Two `<diagram>` pages; IDs namespaced per page; both render. |

### Scoring rubric (per test: 0/1 each, 5 = perfect)
1. **Right format/tool** — picked Mermaid vs DrawIO correctly; used the intended helper (autolayout/shapesearch/aiicons) when applicable.
2. **Structural validity** — `drawio_gen.py verify` clean (no ERROR); gate behaved.
3. **Visual quality** — no overlaps/clipping/stacked edges; readable labels; sane spacing (self-check loop actually improved crowded cases).
4. **Editability preserved** — `content=` attr intact and decodes; opens in draw.io.
5. **Faithful to request** — all requested elements/relationships present and correct.

Barometer score = sum across B1–B10 (max 50). Track over time; a regression in
any test after a skill change is a red flag. Record which tests need the
graphviz nix-shell prefix or a working PNG rasterizer (depends on T1/A).

**Confirmed prefixes (from T1):**
- Graphviz (B4): `nix shell nixpkgs#graphviz -c bash -c '...'` (Section 34).
- PNG rasterizer for the vision loop (B8): `nix shell nixpkgs#drawio nixpkgs#xvfb-run -c xvfb-run --auto-servernum drawio -x -f png --width 2000 -p 1 -o /tmp/x.png f.drawio.svg`.
- The Read tool cannot render `.drawio.svg` as an image (returns XML text), so B8 MUST rasterize to PNG first.

---

## Results (fill during T5)
(empty until the user runs the barometer)

---

## Next concrete step
Start T1: resolve seeded risk A first (rasterization) — it gates whether Section
15's vision loop is real. Then B–E, fill the findings table, and agree the T2 fix
list with the user before changing code.
