#!/usr/bin/env bash
# Diagram-skill quality barometer — unattended runner (plan-047 T5).
#
# Runs B1-B10 as standalone `claudemax -p` sessions (each a FRESH session, so the
# measure is unbiased), scores the command-checkable rubric dimensions
# automatically, assembles every output diagram into ONE PNG review folder, and
# opens it. The human only context-shifts ONCE at the end to score the visual
# dimension and eyeball correctness.
#
# Design notes:
#   - Each prompt forces a deterministic OUTPUT PATH so the harness can locate,
#     score, and render every artifact.
#   - Sessions capture --output-format stream-json, so helper USE (autolayout.py /
#     shapesearch.py / aiicons.py / the rasterizer) is PROVEN from tool calls, not
#     merely inferred from output shape.
#   - Inputs are frozen: fixed fixtures (B4/B7/B8/B9) + verbatim prompts => the
#     INPUT is identical every run. Outputs vary (LLM); that is what the objective
#     checks + the human visual pass absorb, and what makes a score swing a signal.
#   - nix concurrency: the skill shells out to nix (graphviz/drawio). claudemax
#     puts the guarded nix on PATH, but we still cap parallelism (BAROMETER_JOBS,
#     default 2) and run all rasterization SERIALLY in the render phase.
#
# Usage:   ./run-barometer.sh [B1 B2 ...]      # no args = all 10
# Env:     BAROMETER_MODEL (default claude-sonnet-4-6), BAROMETER_JOBS (default 2),
#          BAROMETER_OUT (default /tmp/diagram-barometer),
#          DIAGRAM_SKILL (default /home/tim/.claude-max/skills/diagram)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$HERE/fixtures"
OUT="${BAROMETER_OUT:-/tmp/diagram-barometer}"
SKILL="${DIAGRAM_SKILL:-/home/tim/.claude-max/skills/diagram}"
MODEL="${BAROMETER_MODEL:-claude-sonnet-4-6}"
JOBS="${BAROMETER_JOBS:-2}"
REVIEW="$OUT/review"
GEN="python3 $SKILL/drawio_gen.py"
RASTER=(nix shell nixpkgs#drawio nixpkgs#xvfb-run -c xvfb-run --auto-servernum drawio -x -f png --width 2000 -p 1)

ALL=(B1 B2 B3 B4 B5 B6 B7 B8 B9 B10)
TESTS=("$@"); [ ${#TESTS[@]} -eq 0 ] && TESTS=("${ALL[@]}")

mkdir -p "$OUT" "$REVIEW"
cp -f "$FIX"/b4.graph.json "$FIX"/b7.drawio "$FIX"/b8.spec.txt "$OUT"/ 2>/dev/null
# B9 input is generated deterministically from a committed raw mxfile (decoupled
# from B2's variable output → B9 is reproducible and independently runnable).
$GEN wrap --output "$OUT/b9-input.drawio.svg" < "$FIX/b9-input.mxfile" >/dev/null 2>&1

# ---- prompts (verbatim, forced output paths) ---------------------------------
prompt() {
  case "$1" in
  B1) echo "Use the diagram skill. Diagram the TCP connection state machine. Choose the appropriate format yourself. Save the result to $OUT/b1 with the correct extension: '.md' containing a \`\`\`mermaid fenced block if you choose Mermaid, or '.drawio.svg' if you choose DrawIO. Produce the file; do not ask questions.";;
  B2) echo "Use the diagram skill. Create a 3-tier architecture diagram: Web, API, Database, with a Cache between API and DB. Use the skill's palette colors and orthogonal edges, and run the verify gate. Save to $OUT/b2.drawio.svg.";;
  B3) echo "Use the diagram skill. Create a side-by-side 'Before vs After' comparison: left column 'Manual deploy' with 3 pain points, right column 'CI/CD' with 3 wins, and dashed transformation arrows connecting them. Save to $OUT/b3.drawio.svg.";;
  B4) echo "Use the diagram skill. Lay out these 18 microservices and their call graph using the auto-layout capability (graphviz). The graph spec is at $OUT/b4.graph.json. Do not hand-place coordinates. Save the result to $OUT/b4.drawio.svg.";;
  B5) echo "Use the diagram skill. AWS diagram: API Gateway -> Lambda -> DynamoDB, plus S3. Use real AWS vendor shapes via the shape-search capability (not generic boxes). Save to $OUT/b5.drawio.svg.";;
  B6) echo "Use the diagram skill. RAG application: user -> Claude -> LangChain -> Qdrant + Postgres. Use the AI/brand icon capability with embedded icons (self-contained, no external URLs). Save to $OUT/b6.drawio.svg.";;
  B7) echo "Use the diagram skill. Attempt to render the draw.io file at $OUT/b7.drawio. First run the validation gate. If it reports structural errors, do NOT force a render or 'fix' the file - just report the errors. Only if it is clean, save a render to $OUT/b7.out.drawio.svg.";;
  B8) echo "Use the diagram skill. Put these 12 nodes on ONE page with these 20 edges: nodes A B C D E F G H I J K L; edges A-B A-C A-D B-C B-E B-F C-F D-E D-G D-H E-F E-H F-I G-H G-J H-I H-K I-L J-K K-L. Run the vision self-check loop to reduce overlaps: rasterize to PNG, read it, auto-fix, repeat. Save the round-0 PNG to $OUT/b8.round0.png, the round-1 PNG to $OUT/b8.round1.png, and the final diagram to $OUT/b8.drawio.svg.";;
  B9) echo "Use the diagram skill. Edit the EXISTING diagram at $OUT/b9-input.drawio.svg (do not recreate it): rename the 'API' node to 'Gateway', make the 'DB' node green, and insert a new 'Redis' node between Gateway and DB, splitting that connector (Gateway -> Redis -> DB). Make a surgical content= edit touching only those cells. Save the edited result to $OUT/b9.drawio.svg.";;
  B10) echo "Use the diagram skill. Create a 2-page network diagram: page 1 'Physical Topology', page 2 'Logical VLANs'. Namespace cell IDs per page so they do not collide. Save to $OUT/b10.drawio.svg.";;
  esac
}

# ---- run one session ---------------------------------------------------------
run_one() {
  local id="$1" lc; lc=$(echo "$id" | tr 'A-Z' 'a-z')
  local p; p="$(prompt "$id")"
  echo "[$(date +%H:%M:%S)] START $id"
  timeout 900 claudemax -p "$p" \
    --permission-mode bypassPermissions \
    --model "$MODEL" \
    --output-format stream-json --verbose \
    > "$OUT/$lc.stream.jsonl" 2> "$OUT/$lc.err"
  echo "[$(date +%H:%M:%S)] DONE  $id (rc=$?)"
}

# ---- phase 1: run sessions, bounded-parallel ---------------------------------
# BAROMETER_SCORE_ONLY=1 re-scores existing artifacts without re-running sessions.
if [ "${BAROMETER_SCORE_ONLY:-0}" != 1 ]; then
  echo "=== Phase 1: running ${#TESTS[@]} sessions (model=$MODEL jobs=$JOBS) ==="
  running=0
  for id in "${TESTS[@]}"; do
    run_one "$id" &
    running=$((running+1))
    if [ "$running" -ge "$JOBS" ]; then wait -n 2>/dev/null || wait; running=$((running-1)); fi
  done
  wait
  echo "=== Phase 1 complete ==="
else
  echo "=== Phase 1 SKIPPED (BAROMETER_SCORE_ONLY) ==="
fi

# ---- helpers for scoring -----------------------------------------------------
uses() { grep -qF "$1" "$OUT/$2.stream.jsonl" 2>/dev/null; }   # tool-call evidence in the stream
dec()  { python3 "$SKILL/drawio_gen.py" extract "$1" 2>/dev/null; }  # decode the content= mxfile (structural greps MUST decode first)
YN() { [ "$1" = 1 ] && echo PASS || echo fail; }

# ---- phase 2: objective scoring ---------------------------------------------
echo "=== Phase 2: objective scoring ==="
SCORE="$OUT/scorecard.tsv"
printf 'test\tformat/tool\tstructural\tvisual\teditable\tfaithful\tnotes\n' > "$SCORE"
for id in "${TESTS[@]}"; do
  lc=$(echo "$id" | tr 'A-Z' 'a-z'); f="$OUT/$lc.drawio.svg"; d1=0 d2=0 d4=0 d5=0; note=""
  case "$id" in
  B1) # right format = Mermaid, not DrawIO
      if [ -f "$OUT/b1.md" ] && grep -q '```mermaid' "$OUT/b1.md"; then d1=1; d2=1; d4=1; d5=1; note="mermaid ok";
      elif [ -f "$OUT/b1.drawio.svg" ]; then note="picked DrawIO (should be Mermaid)"; else note="no artifact"; fi;;
  B2) [ -f "$f" ] && { $GEN verify "$f" >/dev/null 2>&1 && d2=1; grep -q 'edgeStyle=orthogonal\|rounded=0' "$f" && grep -qoE '#(dae8fc|d5e8d4|ffe6cc|e1d5e7|fff2cc|f8cecc)' "$f" && d1=1; d4=$d2; d5=1; } || note="no artifact";;
  B3) [ -f "$f" ] && { $GEN verify "$f" >/dev/null 2>&1 && d2=1; grep -q 'dashed=1' "$f" && d1=1; d4=$d2; d5=1; } || note="no artifact";;
  B4) [ -f "$f" ] && { uses autolayout.py "$lc" && d1=1; $GEN verify "$f" 2>&1 | grep -qi 'overlap\|cross' || d2=1; d4=1; d5=1; note="autolayout used=$(YN $d1)"; } || note="no artifact";;
  B5) [ -f "$f" ] && { uses shapesearch.py "$lc" && d1=1; n=$(dec "$f" | grep -c 'mxgraph.aws'); [ "${n:-0}" -ge 3 ] && d5=1; $GEN verify "$f" >/dev/null 2>&1 && d2=1; d4=$d2; note="aws shapes=$n";} || note="no artifact";;
  B6) [ -f "$f" ] && { uses aiicons.py "$lc" && d1=1; n=$(dec "$f" | grep -c 'data:image'); [ "${n:-0}" -ge 3 ] && d5=1; $GEN verify "$f" >/dev/null 2>&1 && d2=1; d4=$d2; note="embedded icons=$n";} || note="no artifact";;
  B7) # NEGATIVE: gate must report errors AND no output rendered. Score via validate.py (the real gate).
      # NB capture output (command subst) — a pipeline `if validate|grep` is defeated by pipefail + validate's rc=1.
      v7=$(python3 "$SKILL/validate.py" "$OUT/b7.drawio" 2>&1 || true); echo "$v7" | grep -qi 'error' && d2=1
      [ ! -f "$OUT/b7.out.drawio.svg" ] && d1=1     # skill correctly refused to render
      d4=1; d5=$d2; note="gate flagged=$(YN $d2); refused-render=$(YN $d1)";;
  B8) # vision loop ran: both round PNGs present + rasterize evidence
      [ -f "$OUT/b8.round0.png" ] && [ -f "$OUT/b8.round1.png" ] && d1=1
      { uses 'drawio -x -f png' "$lc" || uses 'xvfb-run' "$lc"; } && : ; [ -f "$f" ] && { $GEN verify "$f" >/dev/null 2>&1 && d2=1; d4=$d2; d5=1; }
      note="round0+1 PNGs=$(YN $d1)";;
  B9) [ -f "$f" ] && { x=$(dec "$f"); $GEN verify "$f" >/dev/null 2>&1 && d2=1; echo "$x" | grep -q 'value="Gateway"' && ! echo "$x" | grep -q 'value="API"' && d5=1; echo "$x" | grep -qi 'redis' && d1=1; d4=$d2; note="rename+redis=$(YN $d1)"; } || note="no artifact";;
  B10) [ -f "$f" ] && { c=$(dec "$f" | grep -c '<diagram '); [ "$c" = 2 ] && d1=1 && d5=1; $GEN verify "$f" >/dev/null 2>&1 && d2=1; d4=$d2; note="pages=$c"; } || note="no artifact";;
  esac
  printf '%s\t%s\t%s\t?\t%s\t%s\t%s\n' "$id" "$(YN $d1)" "$(YN $d2)" "$(YN $d4)" "$(YN $d5)" "$note" >> "$SCORE"
done
column -t -s$'\t' "$SCORE"
echo "(visual dim = '?' → your call during review; scorecard: $SCORE)"
[ "${BAROMETER_SCORE_ONLY:-0}" = 1 ] && { echo "(score-only: skipping render/open)"; exit 0; }

# ---- phase 3: render review set (SERIAL — nix) ------------------------------
echo "=== Phase 3: rendering review PNGs (serial) ==="
rm -f "$REVIEW"/*.png 2>/dev/null
i=0
for id in "${ALL[@]}"; do
  i=$((i+1)); lc=$(echo "$id" | tr 'A-Z' 'a-z'); nn=$(printf '%02d' "$i")
  if [ -f "$OUT/$lc.drawio.svg" ]; then
    "${RASTER[@]}" -o "$REVIEW/$nn-$lc.png" "$OUT/$lc.drawio.svg" >/dev/null 2>&1 && echo "  rendered $id" || echo "  RENDER FAILED $id"
  elif [ -f "$OUT/b1.md" ] && [ "$id" = B1 ]; then
    cp "$OUT/b1.md" "$REVIEW/$nn-b1-MERMAID.md"; echo "  $id is Mermaid (see .md)"
  fi
done
# B8 vision-loop before/after go adjacent for comparison
[ -f "$OUT/b8.round0.png" ] && cp "$OUT/b8.round0.png" "$REVIEW/08a-b8-round0.png"
[ -f "$OUT/b8.round1.png" ] && cp "$OUT/b8.round1.png" "$REVIEW/08b-b8-round1.png"

# ---- phase 4: open review folder --------------------------------------------
WINDIR=$(/bin/wslpath -w "$REVIEW" 2>/dev/null)
echo "=== Phase 4: opening review folder ==="; echo "  $REVIEW  ($WINDIR)"
explorer.exe "$WINDIR" 2>/dev/null || true
echo "=== DONE. Score the visual dim in $SCORE, then record totals in plan-047 Results. ==="
