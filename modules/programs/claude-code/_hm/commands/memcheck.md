# Report file-based memory health (READ-ONLY) - sizes, caps, orphans, stale/leak signals, GREEN/AMBER/RED verdict

Produce a scannable health report for THIS repo's file-based memory store (the `MEMORY.md`
index and its topic files). Answer one question: "is my memory healthy, or should I run
`/cleanmemory`?" - without changing anything.

This command is READ-ONLY. Do NOT edit `MEMORY.md`, do NOT delete or rewrite any topic file,
do NOT run `/cleanmemory`'s apply step. Measure and report only. If you are tempted to fix
something you find, STOP and recommend `/cleanmemory` instead.

Optional argument (a memory dir to inspect instead of auto-resolving): $ARGUMENTS

## Thresholds (match the harness; do not invent new ones)

The harness loads `MEMORY.md` in full every session and warns as it nears a hard read cap.
These are harness-owned and NOT user-tunable - align to them, never override. Report against
all three, whichever binds first:
- **Byte read cap: 24.4 KB** (hard). Harness compaction target: **~17 KB** (= ~70% of cap).
- **Line cap: 200 lines** (co-equal hard cap; usually binds FIRST - so fewer entries, not
  shorter ones, is the real lever).

## Step 1: Locate the store

Find the memory dir (the directory holding `MEMORY.md`; your own session instructions name the
path - it is keyed by the repo's git common-dir and SHARED across all this repo's worktrees). If
there is no `MEMORY.md`, report "no file-based store" and stop. Run the rest from that dir.
Recipes assume `rg` and `fd`.

## Step 2: Index size vs caps

```bash
wc -l -c MEMORY.md     # lines, bytes
```
Convert bytes to KB. Report % of the 24.4 KB cap and % of the 200-line cap.

## Step 3: Per-type breakdown

Count index entries by the `metadata.type` of the topic files they point to
(user | feedback | project | reference). Flag any one section that has grown oversized.

## Step 4: Orphan topic files (no index link AND no inbound [[link]])

```bash
indexed=$(rg -o '\(([a-z0-9-]+)\.md\)' -r '$1' MEMORY.md | sort -u)
linked=$(rg -oIN '\[\[([a-z0-9-]+)\]\]' -r '$1' ./*.md 2>/dev/null | sort -u)
reachable=$(printf '%s\n%s\n' "$indexed" "$linked" | sort -u)
total=0; orphans=0
for f in *.md; do
  [ "$f" = MEMORY.md ] && continue
  total=$((total+1)); slug="${f%.md}"
  printf '%s\n' "$reachable" | rg -qx "$slug" || orphans=$((orphans+1))
done
printf 'topic files: %s   orphans (unreachable): %s\n' "$total" "$orphans"
```
Report the count and the orphan ratio. Do NOT list all orphan names unless asked (can be
hundreds); summarize and offer to enumerate.

## Step 5: Leak + stale signals (report, do NOT fix)

- **Per-plan-status leakage IN THE INDEX** (which must never live in `MEMORY.md`):
  `rg -n 'plan-[0-9]|NEXT=|TASK:(PENDING|IN_PROGRESS|COMPLETE)|pipeline #|MR !' MEMORY.md`
- **Likely-stale index lines**: hooks containing DONE/LANDED/MERGED/RESOLVED/FIXED with no
  forward action, or a bare past date: `rg -ni 'DONE|LANDED|MERGED|RESOLVED|FIXED' MEMORY.md`
- **Broken index pointers**: index `(slug.md)` links whose file is missing on disk.
Report counts + a few examples each. These are SIGNALS for a later sweep, not actions now.

## Step 6: Verdict

Emit a single GREEN / AMBER / RED verdict (use the compact fixed-field block style, not prose):
- **GREEN** = under ~17 KB AND under ~160 lines AND 0 index leakage AND few orphans.
- **AMBER** = 17-24.4 KB OR 160-200 lines OR some orphans/stale lines - clean soon.
- **RED** = at/over 24.4 KB OR at/over 200 lines OR index leakage present OR broken pointers
  - clean now.

End with the recommendation: if GREEN, "no action - memory is healthy." If AMBER/RED, name the
single biggest lever (usually fewer entries - DROP stale/merge dupes - not shorter lines) and
say: "run `/cleanmemory` to curate (it is mutating + sign-off-gated)." Do NOT run it yourself.
