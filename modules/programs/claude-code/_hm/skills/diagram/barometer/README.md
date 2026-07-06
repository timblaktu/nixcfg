# Diagram-skill quality barometer

Automated runner for plan-047's B1-B10 benchmark. It exists so the human spends
**minimal time**: the machine runs every test in a fresh standalone session,
scores everything command-checkable, collects all output diagrams into one PNG
folder, and opens it. You context-shift **once** to score the visual dimension
and eyeball correctness, then record totals.

## Run it

```bash
./run-barometer.sh                 # all 10, unattended
./run-barometer.sh B2 B4 B8        # a subset
BAROMETER_MODEL=claude-opus-4-8 ./run-barometer.sh   # heavier model
BAROMETER_JOBS=3 ./run-barometer.sh                  # more parallelism (see nix caveat)
```

Outputs land in `/tmp/diagram-barometer/` (NOT committed): per-test
`bN.drawio.svg`/`b1.md`, `bN.stream.jsonl` (full tool-call trace), `scorecard.tsv`,
and `review/` (the PNG set that auto-opens in Explorer).

**How it works.** Each test is a `claudemax -p` session (fresh → unbiased). Every
prompt forces a deterministic output path so artifacts are locatable. Sessions
capture `--output-format stream-json`, so *helper usage* is **proven** from tool
calls (grep the stream for `autolayout.py`/`shapesearch.py`/`aiicons.py`/the
rasterizer), not merely inferred from output shape. Rubric dims 1/2/4/5 are
scored automatically; dim 3 (visual) is the human's, done in one pass over
`review/`.

**nix caveat.** The skill shells out to nix (graphviz, drawio). `claudemax` puts
the *guarded* nix on PATH, but we still cap parallelism (`BAROMETER_JOBS`, default
2) and run all rasterization serially, per the repo's no-concurrent-nix rule.

## Determinism: are inputs identical every run?

**Inputs: yes, frozen.** Two input classes:
- *Fixed fixtures* (`fixtures/`): B4 graph, B7 broken file, B8 spec, B9 input
  (generated at setup from `b9-input.mxfile` via `drawio_gen.py wrap`). Byte-identical every run.
- *Verbatim prompts* (embedded in `run-barometer.sh`): the natural-language request
  string is the input for B1/B2/B3/B5/B6/B10, and it never changes.

**Outputs: no, and that is expected.** The skill is an LLM; the same prompt yields
different diagrams run-to-run. That is *why* scoring is (a) objective command
checks tolerant of layout variation and (b) a human visual pass — and why the
barometer total is tracked over time: a large swing on frozen inputs is the
regression signal. (`claude -p` exposes no temperature knob, so output variance is
irreducible here; the objective checks are deliberately structural, not pixel-exact.)

## Per-test analysis

| # | Capability under test | Input (frozen) | Output | Objective check | How it could test the feature *better* |
|---|---|---|---|---|---|
| B1 | Format auto-select → **Mermaid** for a simple state graph | prompt | `b1.md` | `.md` with ` ```mermaid `, not DrawIO | Pair with a "should be DrawIO" twin so the *decision boundary* is tested both ways, not just the Mermaid side. |
| B2 | Hand-placed DrawIO: palette + orthogonal edges + verify gate | prompt | `b2.drawio.svg` | `verify` clean; orthogonal; palette hexes present | Assert an actual edge-routing metric (no overlaps) via `validate.py` warnings, not just the style string. |
| B3 | Side-by-side comparison layout | prompt | `b3.drawio.svg` | `dashed=1` arrows present; `verify` clean | Column alignment is only human-checkable today; could add a geometry check that the two column x-bands are disjoint and row y's align. |
| B4 | Auto-layout of a dense graph (graphviz) | `b4.graph.json` (18n/22e) | `b4.drawio.svg` | **tool-call proof** `autolayout.py` used + no overlap/cross warnings | Strong. Could also assert node coords are non-round (dot-derived) to catch a model that hand-places despite being told not to. |
| B5 | Vendor shape search (AWS) | prompt | `b5.drawio.svg` | **tool-call proof** `shapesearch.py` + `mxgraph.aws` ≥3 | Check the *specific* shapes (apigateway/lambda/dynamodb/s3) resolved, not just any 3 aws shapes. |
| B6 | AI/brand icons, embedded | prompt | `b6.drawio.svg` | **tool-call proof** `aiicons.py` + `data:image` ≥3 (self-contained) | Assert no `image=https://` CDN refs remain (fully offline), and that the *right* brands matched. |
| B7 | **Negative**: validate gate rejects a broken file | `b7.drawio` (dup id + dangling edge) | (none — must refuse) | `validate.py` reports errors **and** no `b7.out` written | Fixed here: score the **gate** (`validate.py`), not `drawio_gen.py verify`, which wrongly rejects *raw* `.drawio` as "no content attr" (see Findings). Also add a valid-file twin to ensure the gate does not over-reject. |
| B8 | Vision self-check loop (render→read→fix) | B8 spec (12n/20e) | `b8.round0.png`, `b8.round1.png`, `b8.drawio.svg` | both round PNGs exist; final `verify` clean | Objectively compare overlap count round0 vs round1 (parse `validate.py` warnings on each round's model) to prove the loop *improved* it, not just ran. |
| B9 | Surgical edit workflow | `b9-input.drawio.svg` (**decoupled** fixed input) | `b9.drawio.svg` | `verify` clean; `Gateway` present & `API` gone; `Redis` inserted | Decoupled here from B2. Could diff cell-sets to assert *only* intended cells changed (no collateral edits). |
| B10 | Multi-page | prompt | `b10.drawio.svg` | exactly 2 `<diagram>`; `verify` clean (no cross-page id collisions) | Assert page names ("Physical"/"Logical") and that each page's ids carry a per-page prefix. |

## Cross-cutting improvements applied

1. **B9 decoupled from B2.** B9 used to edit B2's (variable) output — a test-order
   dependency that also made B9 non-deterministic. It now edits a committed fixed
   input, so it is reproducible and independently runnable/parallelizable.
2. **B7 scores the gate, not a CLI quirk.** The authored check (`drawio_gen.py
   verify b7.drawio`) tests the wrong thing (see Findings). Scoring now uses
   `validate.py` — the same linter the render gate runs — which correctly flags
   both errors on raw `.drawio`.
3. **Helper usage is proven, not inferred.** B4/B5/B6/B8 grep the session's
   tool-call stream for the actual helper invocation, closing the "produced
   similar output without using the helper" gap.
4. **Forced output paths** make every artifact locatable for scoring + rendering
   with zero human bookkeeping.

## Skill findings surfaced (candidate follow-ups, not fixed here)

- **`drawio_gen.py verify` ⧸ `validate.py` inconsistency.** `verify` assumes the
  `.drawio.svg` form and rejects a raw `.drawio` with "No content attribute found",
  while `validate.py` lints raw `.drawio` correctly. The `verify` wrapper should
  fall back to raw-`.drawio` when there is no `content=` attr (match `validate.py`).
- **Stale deployed orphans.** `drawio_analyze.py`/`drawio_edit.py` remain in the
  deployed skill dir (per-file cp never prunes them). Cosmetic; noted in plan T3.
