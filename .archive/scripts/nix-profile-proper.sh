#!/usr/bin/env bash
# Proper Nix profiling using official tools
set -euo pipefail

PROFILE_DIR="nix-profiles/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$PROFILE_DIR"

echo "🔍 Starting proper Nix profiling in $PROFILE_DIR"
echo

# 1. NIX_SHOW_STATS for JSON performance data
echo "📊 Collecting Nix evaluation statistics..."
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$PROFILE_DIR/nix-stats.json" \
  time home-manager build --flake '.#tim@tblack-t14-nixos' --no-out-link --show-trace \
  2>&1 | tee "$PROFILE_DIR/build-output.log"

echo "📊 Collecting function call statistics..."
NIX_COUNT_CALLS=1 \
  nix eval '.#homeConfigurations."tim@tblack-t14-nixos"' --apply 'cfg: {}' \
  2>&1 | tee "$PROFILE_DIR/function-calls.log"

# 2. Evaluation profiler for flamegraph
echo "📊 Generating evaluation flamegraph..."
nix eval --eval-profiler flamegraph \
  '.#homeConfigurations."tim@tblack-t14-nixos"' \
  --apply 'cfg: {}' \
  --eval-profile-file "$PROFILE_DIR/eval.profile" \
  2>/dev/null || echo "  (Flamegraph generation may have failed)"

# Generate SVG if flamegraph.pl is available
if command -v flamegraph.pl >/dev/null 2>&1 && [[ -f "$PROFILE_DIR/eval.profile" ]]; then
  flamegraph.pl "$PROFILE_DIR/eval.profile" > "$PROFILE_DIR/evaluation-flamegraph.svg"
  echo "  ✅ Flamegraph saved: $PROFILE_DIR/evaluation-flamegraph.svg"
else
  echo "  ⚠️  flamegraph.pl not available or profile not generated"
fi

# 3. Build performance with cgroups stats (if available)
echo "📊 Testing build with JSON stats..."
if nix build --json '.#homeConfigurations."tim@tblack-t14-nixos".activationPackage' --no-link \
   > "$PROFILE_DIR/build-stats.json" 2>/dev/null; then
  echo "  ✅ Build stats saved"
else
  echo "  ⚠️  Build stats not available"
fi

# 4. Generate report
echo "📈 Generating analysis report..."
cat > "$PROFILE_DIR/ANALYSIS.md" << EOF
# Nix Performance Analysis - $(date)

## Build Timing
\`\`\`
$(grep "real\|user\|sys" "$PROFILE_DIR/build-output.log" | tail -3)
\`\`\`

## Nix Statistics (JSON)
\`\`\`json
$(cat "$PROFILE_DIR/nix-stats.json" 2>/dev/null || echo "No stats generated")
\`\`\`

## Function Call Summary
\`\`\`
$(head -20 "$PROFILE_DIR/function-calls.log" 2>/dev/null || echo "No function call data")
\`\`\`

## Build Stats
\`\`\`json
$(cat "$PROFILE_DIR/build-stats.json" 2>/dev/null || echo "No build stats available")
\`\`\`

## Available Files
- \`build-output.log\`: Full build output with timing
- \`nix-stats.json\`: Nix evaluator performance statistics  
- \`function-calls.log\`: Function call counts and performance
- \`eval.profile\`: Raw evaluation profile data
- \`evaluation-flamegraph.svg\`: Visual performance analysis (if generated)
- \`build-stats.json\`: Build-time statistics with derivation info

## Analysis
The real bottleneck is likely in:
1. **Evaluation time**: Check nix-stats.json for gcTime and cpuTime
2. **Function calls**: Look for expensive functions in function-calls.log
3. **Build dependencies**: Check build-stats.json for derivation complexity

## Next Steps
1. Compare nix-stats.json between runs for performance regression
2. Open evaluation-flamegraph.svg in browser to identify hot paths
3. Focus optimization on functions with highest call counts
EOF

echo "✅ Proper Nix profiling complete! Results in $PROFILE_DIR"
echo "📋 View analysis: cat $PROFILE_DIR/ANALYSIS.md"
echo "🔥 View flamegraph: open $PROFILE_DIR/evaluation-flamegraph.svg"