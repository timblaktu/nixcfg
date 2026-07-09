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
| T2 Apply agreed improvements + commit | TASK:COMPLETE (2026-07-01) | Agreed T1 fixes applied; `python3 -m py_compile` on all skill `.py` passes; `nix flake check --no-build` passes; committed on this branch; no AI attribution. |
| T3 Deploy (home-manager switch) | TASK:COMPLETE (2026-07-02) | `home-manager switch` (via nixcfg-work override-input) succeeds; deployed skill dir contains validate.py/autolayout.py/shapesearch.py/aiicons.py/data/*; `drawio_gen.py verify` runs from the deployed copy. |
| T4 Finalize quality-barometer suite | TASK:COMPLETE (2026-07-02) | Test suite + scoring rubric reviewed/refined: B1–B10 "Passes if" each backed by an objective command; the 3 placeholder inputs (B4/B7/B8) replaced with concrete reproducible fixtures; helper-script invocation syntax verified against deployed scripts; palette hexes + confirmed prefixes recorded. Ready for the user to run (T5). |
| T5 Run the barometer (INTERACTIVE) | TASK:IN_PROGRESS | PAUSED 2026-07-09 by user to ship the skill. Automated runner built (`barometer/run-barometer.sh`) + run once on sonnet-4-6: **all 10 pass the 4 objective dims (40/50)**; the visual dim ③ (10 pts) awaits the user's one-pass review of `/tmp/diagram-barometer/review/`. Resume = eyeball those PNGs, fill ③ + totals below, then COMPLETE. `Interactive` — needs user vision. |

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

**T2 done (2026-07-01):**
- **A:** Section 15 visual-pass step rewritten to the nix-shell
  `xvfb-run … drawio -x -f png --width 2000` command; added the "harmless
  GLX/EGL stderr / no --no-sandbox" caveats; Section 33 Windows `draw.io.exe`
  kept as the alternative; the "cannot rasterize" fallback reworded to reference
  the nix shell. (No separate Section 8 raster note existed — the only bare
  `drawio -x -f png` was Section 15; Section 33's is the Windows alternative.)
- **B:** Section 15 now states the Read tool does NOT render `.drawio.svg` as an
  image (returns XML) so the PNG step is mandatory.
- **C:** §6/§17/§18/§32 bodies moved to REFERENCE.md under "Extended Examples
  (moved from SKILL.md)"; each SKILL.md heading left as a one-line pointer stub
  (no renumbering → `Section NN` cross-refs still resolve). SKILL.md 3226→2675
  lines (-551, ~17%); REFERENCE.md 712→1307.
- **F:** NO-OP — validate.py (L31-34) and autolayout.py (L26-29) already carry
  "Vendored and adapted from Agents365-ai/drawio-skill (MIT)" headers since
  761a3bb. T1's finding F was a `head -3` false positive (headers sit just after
  the docstring). No change needed.
- DoD: `py_compile` clean on all 5 `.py`; `nix flake check --no-build` → all
  checks passed.

**Other spot-checks:** no dangling `Section NN` references beyond 35; changelog
v1.11.0 matches what shipped (validate/autolayout/vision-loop/shape+icon search);
`verify`/`wrap`/`--render` docs match `drawio_gen.py` behavior. All 5 `.py`
compile.

Also spot-check: cross-references (Section N pointers) resolve; changelog v1.11.0
matches what shipped; `verify`/`wrap`/`--render` docs match `drawio_gen.py`
behavior; provenance headers present in all four vendored scripts.

---

## T3 — Deploy (home-manager switch)  [DONE 2026-07-02]

Host verified: `tim@pa161878-nixos` (WSL_DISTRO=nixos), `nixcfg-work` present.
All 10 skill source files (incl. the four new scripts + `data/*`) are enumerated
in `skills.nix` (lines 54-67) and committed on the branch. Ran:

```bash
cd /home/tim/src/nixcfg-work
home-manager switch --flake '.#tim@pa161878-nixos' \
  --override-input nixcfg /home/tim/src/nixcfg
```

- **Switch succeeded.** Override-input pinned nixcfg → this branch
  (`git+file://…/nixcfg?ref=refs/heads/diagram-skill-integrations&rev=287e2f1`,
  2026-07-02), superseding the flake.lock pin (327be40, 2026-06-30). Activation
  ran to completion (`claudeSkillsDeployment` + all later gens).
- **Deployed dir DoD met** (`/home/tim/.claude-max/skills/diagram/`, all files
  dated Jul 2 09:27): `validate.py autolayout.py shapesearch.py aiicons.py`
  present; `data/{shape-index.json.gz,lobe-icons.json,SHAPE-INDEX-NOTICE.md}`
  present; `SKILL.md` = 2675 lines (the T2 trimmed version, was 3251 pre-switch);
  `REFERENCE.md` = 44KB (grew per T2 move).
- **`verify` runs from the deployed copy:** generated a minimal valid diagram via
  the deployed `drawio_gen.py generate`, then `drawio_gen.py verify` → exit 0,
  "OK: no structural errors" (delegates to the deployed `validate.py`, confirming
  the new script loads/runs). (Skipped `--render` — it shells out to
  `nix run …drawio-svg-sync`, not needed for the DoD.)

**Note (out of scope, cosmetic):** stale orphans `drawio_analyze.py` and
`drawio_edit.py` (Mar 1, no longer enumerated) remain in the deployed dir. The
activation script prunes stale *skill directories*, not stale *files within* a
declared skill, so per-file cp leaves them. Harmless (nothing references them);
a future cleanup could switch the per-skill deploy to a mirror/rsync-delete.

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
| B4 | Auto-layout (dense) | "Lay out these 18 microservices and their call graph" + the **B4 fixture** below (18 nodes / 22 edges). | Uses `autolayout.py` + graphviz (not hand coords); grouped containers; `verify` warnings show **no** overlaps/crossings. |
| B5 | Vendor shape search | "AWS diagram: API Gateway -> Lambda -> DynamoDB, plus S3." | Uses `shapesearch.py` real AWS shapes (style contains `mxgraph.aws`), not generic boxes. |
| B6 | AI/LLM icons | "RAG app: user -> Claude -> LangChain -> Qdrant + Postgres." | Uses `aiicons.py` with `--embed` (self-contained), real brand logos. |
| B7 | Validate gate (NEGATIVE) | "Render the **B7 fixture** below" (a `.drawio` with a dangling edge + a duplicate ID). | `verify` reports both as ERROR; `--render` **aborts** (does not render a broken file). |
| B8 | Vision self-check loop | "Put these 12 nodes with these 20 edges on one page" — the **B8 fixture** below (crowded on purpose). | Skill rasterizes, reads it, does >=1 auto-fix round, and the final has visibly fewer overlaps than round 0. |
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

### Finalized reproducible inputs & objective checks (T4 — 2026-07-02)

Run everything under a scratch dir (NOT committed):
`mkdir -p /tmp/diagram-barometer && cd /tmp/diagram-barometer`. Below, "SKILL"
means the deployed skill dir `/home/tim/.claude-max/skills/diagram/`. Helper
invocation syntax verified against the deployed scripts:
`autolayout.py graph.json [-o out.drawio]` (input schema:
`{"direction":"TB|LR","nodes":[{"id","label","style?","width?","height?"}],"edges":[{"source","target","label?"}]}`,
ids unique and never `"0"`/`"1"`); `shapesearch.py <query> [--limit N] [--json]`;
`aiicons.py <query> [--variant color|mono|text] [--embed] [--json]`;
`drawio_gen.py verify FILE` (delegates to `validate.py`, which accepts BOTH raw
`.drawio` XML and this skill's `.drawio.svg`).

**Per-test objective check (make each "Passes if" a command, not a judgment):**
- **B1** — grep the produced artifact/response: a Mermaid fenced block (```` ```mermaid ````), NOT a `.drawio.svg`. FAIL if it emitted DrawIO.
- **B2** — `drawio_gen.py verify b2.drawio.svg` exits 0; `grep -c 'edgeStyle=orthogonal\|rounded=0' b2.drawio.svg` > 0; palette hexes present (`grep -oE '#(dae8fc|d5e8d4|ffe6cc|e1d5e7|fff2cc|f8cecc)' b2.drawio.svg` non-empty); file renders via `nix run 'github:timblaktu/drawio-svg-sync' -- b2.drawio.svg`.
- **B3** — visual (rubric #3): two vertically-aligned columns, dashed transform arrows (`grep -c 'dashed=1' b3.drawio.svg` > 0). `verify` clean.
- **B4** — the model was produced by `autolayout.py` (node geometry is dot-derived, not round hand coords); `nix shell nixpkgs#graphviz -c bash -c 'python3 SKILL/autolayout.py /tmp/diagram-barometer/b4.graph.json -o b4.drawio'` then `drawio_gen.py verify b4.drawio.svg` → **no** overlap/crossing warnings.
- **B5** — `grep -c 'mxgraph.aws' b5.drawio.svg` >= 3 (API Gateway, Lambda, DynamoDB, S3 as real AWS shapes, not `rounded=1` boxes).
- **B6** — `aiicons.py` used with `--embed`: `grep -c 'data:image' b6.drawio.svg` >= 3 (inlined brand SVGs, self-contained — no CDN `image=https://` refs).
- **B7** (NEGATIVE) — `drawio_gen.py verify b7.drawio` prints an ERROR line for the dangling edge AND for the duplicate ID (exit != 0); an attempted `--render`/generate-with-gate **aborts** and writes NO output SVG.
- **B8** — evidence of >=1 loop iteration: a round-0 PNG and a round-1 PNG both exist under the scratch dir (rasterized with the confirmed `xvfb-run … drawio -x -f png` prefix); final `drawio_gen.py verify` shows fewer overlap warnings than round 0. Visual confirm (rubric #3).
- **B9** — `diff <(git-style before) after` touches only the intended cells; `grep -c 'value="Gateway"' b2.drawio.svg` == 1 and no `value="API"` remains; Redis cell inserted with a split connector; `verify` clean; `content=` still decodes (`drawio_gen.py verify` succeeds ⇒ mxfile decoded).
- **B10** — `grep -c '<diagram ' b10.drawio.svg` == 2; per-page id namespacing (no id collisions across pages — `verify` clean); both pages render.

**B4 fixture** — write to `/tmp/diagram-barometer/b4.graph.json`:
```json
{
  "direction": "TB",
  "nodes": [
    {"id": "gateway", "label": "API Gateway"}, {"id": "auth", "label": "Auth"},
    {"id": "users", "label": "Users"}, {"id": "catalog", "label": "Catalog"},
    {"id": "search", "label": "Search"}, {"id": "cart", "label": "Cart"},
    {"id": "orders", "label": "Orders"}, {"id": "payments", "label": "Payments"},
    {"id": "inventory", "label": "Inventory"}, {"id": "shipping", "label": "Shipping"},
    {"id": "notify", "label": "Notifications"}, {"id": "email", "label": "Email"},
    {"id": "sms", "label": "SMS"}, {"id": "recs", "label": "Recommendations"},
    {"id": "reviews", "label": "Reviews"}, {"id": "analytics", "label": "Analytics"},
    {"id": "warehouse", "label": "Warehouse"}, {"id": "ledger", "label": "Ledger"}
  ],
  "edges": [
    {"source": "gateway", "target": "auth"}, {"source": "gateway", "target": "catalog"},
    {"source": "gateway", "target": "search"}, {"source": "gateway", "target": "cart"},
    {"source": "gateway", "target": "orders"}, {"source": "auth", "target": "users"},
    {"source": "catalog", "target": "inventory"}, {"source": "search", "target": "catalog"},
    {"source": "cart", "target": "catalog"}, {"source": "cart", "target": "inventory"},
    {"source": "orders", "target": "payments"}, {"source": "orders", "target": "inventory"},
    {"source": "orders", "target": "shipping"}, {"source": "orders", "target": "notify"},
    {"source": "payments", "target": "ledger"}, {"source": "shipping", "target": "warehouse"},
    {"source": "notify", "target": "email"}, {"source": "notify", "target": "sms"},
    {"source": "catalog", "target": "reviews"}, {"source": "recs", "target": "catalog"},
    {"source": "reviews", "target": "analytics"}, {"source": "orders", "target": "analytics"}
  ]
}
```
(18 nodes, 22 edges.) Objective: `verify` on the resulting `.drawio(.svg)` reports
no overlaps/crossings; node coordinates are dot-derived, not hand-typed.

**B7 fixture** — write to `/tmp/diagram-barometer/b7.drawio` (raw `.drawio`; a
dangling edge → target `nope` that doesn't exist, AND two cells sharing id `dup`):
```xml
<mxfile><diagram name="Broken"><mxGraphModel><root>
  <mxCell id="0"/><mxCell id="1" parent="0"/>
  <mxCell id="dup" value="Box A" vertex="1" parent="1"><mxGeometry x="40" y="40" width="120" height="60" as="geometry"/></mxCell>
  <mxCell id="dup" value="Box B" vertex="1" parent="1"><mxGeometry x="240" y="40" width="120" height="60" as="geometry"/></mxCell>
  <mxCell id="e1" edge="1" parent="1" source="dup" target="nope"><mxGeometry relative="1" as="geometry"/></mxCell>
</root></mxGraphModel></diagram></mxfile>
```
Objective: `python3 SKILL/drawio_gen.py verify b7.drawio` emits an ERROR for the
duplicate id `dup` AND for the edge `e1` whose target `nope` is dangling, and
exits non-zero; the render gate must refuse to produce an SVG.

**B8 fixture** — 12 nodes `A B C D E F G H I J K L`, 20 edges (dense, deliberately
crowded if placed naively): `A-B, A-C, A-D, B-C, B-E, B-F, C-F, D-E, D-G, D-H,
E-F, E-H, F-I, G-H, G-J, H-I, H-K, I-L, J-K, K-L`. Hand these to the skill as
"put all 12 on one page with these 20 connections." Objective: the skill runs the
vision loop (round-0 + round-1 PNGs both present under the scratch dir; final has
visibly fewer overlaps).

---

## T4 done (2026-07-02)
Review pass only (no code changes — the suite was already authored; T4 hardened
it for verbatim execution):
- Verified the deployed helper-script invocation syntax (`autolayout.py` graph.json
  schema, `shapesearch.py`/`aiicons.py` flags, `validate.py` accepts raw `.drawio`
  AND `.drawio.svg`) — the fixtures/commands below match reality.
- Replaced the three placeholder inputs with concrete, committed-to-plan fixtures:
  **B4** graph.json (18 nodes/22 edges), **B7** broken `.drawio` (dangling edge +
  duplicate id), **B8** 12-node/20-edge crowded set.
- Turned each "Passes if" into an **objective check** (grep/`verify`/file-exists),
  so scoring is command-driven, not judgment-driven, except the inherently-visual
  rubric #3 items (B3/B8).
- Confirmed palette hexes (`#dae8fc/#d5e8d4/#ffe6cc/#e1d5e7/#fff2cc/#f8cecc`) exist
  in SKILL.md Section 4 (B2 grep is valid); confirmed prefixes (graphviz for B4;
  `xvfb-run … drawio -x -f png` for B8; Read cannot render `.drawio.svg`) recorded.
- Suite is ready for the user to run in T5 (interactive — needs a fresh session +
  human vision judgment).

## T5 — automated runner (2026-07-05)
The barometer is now hands-off:
`modules/programs/claude-code/_hm/skills/diagram/barometer/run-barometer.sh` runs
B1-B10 as standalone `claudemax -p` sessions (fresh → unbiased; bounded-parallel),
auto-scores rubric dims ①②④⑤, assembles all outputs into one PNG folder, and opens
it. The human scores only the visual dim ③, once. Full per-test analysis +
determinism model in `barometer/README.md`.

Suite refinements folded in (improving what T4 authored):
- **B9 decoupled from B2** — committed fixed input `fixtures/b9-input.mxfile`
  (wrapped to `.drawio.svg` at setup) → deterministic, independently runnable.
- **B7 scores the GATE** (`validate.py`), not `drawio_gen.py verify` — the latter
  wrongly rejects a raw `.drawio` ("No content attribute found").
- **B4/B5/B6/B8 prove helper usage** from the session tool-call stream
  (`--output-format stream-json`), not just output shape.
- All prompts force deterministic output paths.

Skill finding (follow-up, not fixed here): `drawio_gen.py verify` rejects a raw
`.drawio` while `validate.py` lints it fine — `verify` should fall back to
raw-`.drawio` when there is no `content=` attr.

Pilot (B1, sonnet-4-6): format auto-select → **Mermaid ✓**, 49s; full plumbing
(prompt → fresh session → skill → forced path → tool-call capture) validated.

## Results (fill during T5)
(run `barometer/run-barometer.sh`; auto-scored dims land in
`/tmp/diagram-barometer/scorecard.tsv`, then record the visual dim + totals here)

Objective dims (①②④⑤) auto-scored 2026-07-09 (sonnet-4-6, `scorecard.tsv`); ③
pending user visual review of `/tmp/diagram-barometer/review/`.

| test | ①fmt | ②struct | ③visual | ④edit | ⑤faithful | /5 | note |
|------|------|---------|---------|-------|-----------|----|------|
| B1  | ✓ | ✓ | ? | ✓ | ✓ | 4+? | Mermaid auto-selected |
| B2  | ✓ | ✓ | ? | ✓ | ✓ | 4+? | palette + orthogonal + verify clean |
| B3  | ✓ | ✓ | ? | ✓ | ✓ | 4+? | dashed transform arrows |
| B4  | ✓ | ✓ | ? | ✓ | ✓ | 4+? | autolayout.py proven used |
| B5  | ✓ | ✓ | ? | ✓ | ✓ | 4+? | 4 real AWS shapes |
| B6  | ✓ | ✓ | ? | ✓ | ✓ | 4+? | 4 embedded icons |
| B7  | ✓ | ✓ | ? | ✓ | ✓ | 4+? | gate flagged both errors, refused render |
| B8  | ✓ | ✓ | ? | ✓ | ✓ | 4+? | vision loop ran (round0+1 PNGs) |
| B9  | ✓ | ✓ | ? | ✓ | ✓ | 4+? | API→Gateway, Redis inserted |
| B10 | ✓ | ✓ | ? | ✓ | ✓ | 4+? | 2 pages |

**Objective subtotal: 40/50. Visual ③ (max +10) pending → final score = 40 + Σ③.**

---

## Next concrete step
Start T1: resolve seeded risk A first (rasterization) — it gates whether Section
15's vision loop is real. Then B–E, fill the findings table, and agree the T2 fix
list with the user before changing code.
