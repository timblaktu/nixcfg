# Curate and prune this session's file-based memory (relevance triage, not byte-golf)

Prune your `MEMORY.md` index AND clean up its topic files, using the method and guardrails below. Curate by RELEVANCE, not by byte count. Do NOT skip the sign-off step.

## Guardrails (read first; these shape every decision below)

- **Relevance, not byte-golf.** Never trim the longest lines just to hit a byte target: entry length often correlates with how load-bearing an entry is. Size is a symptom; relevance is the target.
- **Deleting memory is high-cost and irreversible; over-keeping is low-cost.** When unsure, KEEP or ask. Topic files are recall-on-demand and do NOT cost loaded context, so deleting them is hygiene, not necessity.
- **No silent mass-deletes.** Bulk curation is: analyze, classify, get owner sign-off, then apply. If no human is present (unattended/automated run), produce the classified ledger and STOP; do not delete.
- **Per-plan status never belongs in the index.** Task cursors, `NEXT=`, branch/MR/pipeline state live in the plan file, not `MEMORY.md`. Drop any you find and never add them.
- **Shared store.** A repo's memory store is shared across ALL that repo's git worktrees (keyed by the git common-dir, not cwd). If sibling worktrees may have live sessions, you are editing the same files they are: curate one at a time and do not re-curate what another just did. A different repo has its own separate store.

## Step 0: Confirm the store and the convention

Locate your memory dir (the directory holding `MEMORY.md`; your own instructions name the path). Confirm the convention is: a `MEMORY.md` index of one-line pointers, one fact per topic file with YAML frontmatter (`type:`, `description:`), and `[[slug]]` cross-links. If there is no file-based store, or it uses a different scheme, adapt the ideas below rather than the exact commands, or stop and report. The recipes assume `rg` and `fd` are available.

## Step 1: Measure (run the health report first)

Run the read-only `/memcheck` health report (or inline its checks) to get a measured starting point: `MEMORY.md` size and line count against the hard harness caps - **24.4 KB byte read cap, ~17 KB compaction target, 200-line cap, whichever binds first** (harness-owned, NOT user-tunable) - plus the per-type breakdown, orphan topic-file count, index per-plan-status leakage, likely-stale lines, and broken pointers. Record the GREEN/AMBER/RED verdict; it drives the curation below. Note that the line count usually binds before the byte count, so fewer entries - not shorter ones - is the real lever.

## Step 2: Curate the index itself, in this order

This is the core "prune MEMORY.md" work. Do it in order; do not jump to compression.

- **2a. DROP stale index lines.** Remove or demote pointers to completed/landed/merged/superseded work, resolved one-offs whose reusable lesson already lives in another entry, and any per-plan status. The topic file persists for on-demand recall even after you de-index it.
- **2b. MERGE near-duplicates.** Fold duplicate or near-duplicate bullets into one. Group closely related pointers onto a single line.
- **2c. Compress only what remains.** For still-long ACTIVE entries, move detail into that entry's topic file and leave a one-line pointer that preserves its identity. Never shorten a load-bearing entry just to save bytes.

## Step 3: Topic-file hygiene (orphans + broken links)

Find orphan topic files (neither indexed nor back-linked via `[[slug]]`). Run from the memory dir:

```bash
indexed=$(rg -o '\(([a-z0-9-]+)\.md\)' -r '$1' MEMORY.md | sort -u)
for f in *.md; do
  [ "$f" = MEMORY.md ] && continue
  slug="${f%.md}"
  printf '%s\n' "$indexed" | rg -qx "$slug" && continue
  rg -q "\[\[$slug\]\]" ./*.md 2>/dev/null && continue
  typ=$(rg -m1 '^[[:space:]]*type:[[:space:]]*' "$f" | sed 's/.*type:[[:space:]]*//')
  desc=$(rg -m1 '^description:[[:space:]]*' "$f" | sed 's/^description:[[:space:]]*//' | head -c 150)
  printf '%-10s %-50s %s\n' "${typ:-?}" "$slug" "$desc"
done | sort
```

Classify each orphan by `type` + `description`:

- **DROP** = per-plan status of a completed/merged/superseded plan, and resolved one-offs whose lesson is spent or already captured elsewhere.
- **RESCUE** = durable behavioral `feedback`, reusable `reference`, or a live cross-plan `project` constraint that an earlier compaction over-cut. Re-index as a compact one-liner (group related ones).
- **LEAVE** = real but niche; recallable on demand; no action. This is the default when unsure.

Also fix **broken pointers** (index links to a missing `*.md`) and **duplicate link targets**: both are real dead weight.

## Step 4: Sign-off

Present the full classified ledger (index DROP/MERGE/compress + topic-file DROP/RESCUE/LEAVE, with counts and the DROP list by name). Get explicit approval before deleting anything. If unattended, stop here with the ledger.

## Step 5: Apply, verify, report

On approval: edit `MEMORY.md` (drops, merges, rescues, compressions); delete the DROP topic files with `rm -f`; fix broken/duplicate pointers. Do NOT set an artificially low soft target in the header; curate under the real budget. Then verify all index pointers resolve, there are no duplicates, and the index is under budget. Report before/after size plus counts.

## Finally: capture the meta-lesson

If no memory entry yet states that memory cleanup is relevance curation (drop stale, merge dups, then compress; orphans are recall-on-demand so deletion is hygiene not necessity), create one (type `feedback`) and link it from the `MEMORY.md` working-style section so this is not re-learned.
