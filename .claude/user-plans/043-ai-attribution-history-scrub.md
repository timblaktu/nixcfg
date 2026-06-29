# Plan 043: AI-Attribution Public History Scrub

**Status: DEFERRED** (user decision 2026-06-14 — skip for now; do NOT execute without explicit go-ahead)

## Why this exists

10 commits on `github.com/timblaktu/nixcfg` `origin/main` carry AI-attribution
trailers (`Co-Authored-By: Claude ...`), violating the #1 critical
no-AI-attribution rule. They leaked AI identity to a public remote and listed
Claude as a repo contributor. This plan rewrites those messages out of history.

**This is a public-history rewrite + force-push.** It is intentionally deferred.
Execute ONLY when the user explicitly says go.

## Scope of the leak (verified 2026-06-14)

10 affected commits (not 11 — memory's `ad71afc` entry was a false positive; its
only "claude/anthropic" hits are GitHub issue URLs, no trailer):

| Date | Commits |
|------|---------|
| 2026-01-12 | `cc71386` (earliest) |
| 2026-01-19 | `69a033b`, `68e0450`, `bce0935` |
| 2026-06-13 | `3260043`, `beee0f0`, `3a99c9d`, `3111fe4`, `59e54df`, `a897541` |

- **Clean boundary:** `d1c6855` (2026-06-14) and everything after is clean.
- **Rewrite span:** rewriting from `cc71386` changes the SHA of all descendants
  → **234 commits** (`cc71386..d9b3a70`) get new hashes. Only 10 messages change;
  the rest are rehashed because parent pointers shift. Unavoidable.

## Blast radius

1. **Local nixcfg repo** — `main` re-pointed. Trivial.
2. **4 stale local branches** containing `cc71386` — diverge from rewritten main:
   `fix/claude-memory-nix-managed`, `fix/nixpkgs-update-compat`,
   `fix/remove-claude-browse`, `fix/remove-claude-code-overlay`. Verify merged,
   then delete (do NOT silently rewrite them).
3. **Stale remote branch** `origin/fix/nixpkgs-update-compat` also contains
   `cc71386` — delete on remote or it keeps old trailer history reachable.
4. **nixcfg-work flake.lock** — pins `nixcfg` input at `d1c6855` (SHA changes).
   Must re-lock + push to git.panasonic.aero after the scrub (see Step 5).
5. **Colleagues' nixcfg-work clones** — zero impact until someone runs
   `nix flake update`; the lock pin keeps resolving the old (now-unreachable
   after GC) commit. Near-solo usage → effectively no one affected.
6. **Direct nixcfg clones** — just the user; `git fetch && git reset --hard
   origin/main` fixes them.

## Execution steps (when un-deferred)

### Step 0 — Preconditions
- Get explicit user go-ahead.
- Ensure working tree clean, all wanted work pushed.
- Note current `origin/main` HEAD for rollback: record it before rewrite.
- Create a safety tag/branch: `git branch backup/pre-scrub-YYYYMMDD origin/main`
  and push it to a PRIVATE location (or keep local only) so rollback is possible.
  Do NOT push backup to the public remote.

### Step 1 — Rewrite messages
Prefer `git filter-repo` (cleaner than interactive rebase for message-only edits).
Strip any line matching the AI-attribution markers from every commit message.

```bash
# from a fresh clone or with filter-repo installed (nix run nixpkgs#git-filter-repo)
git filter-repo --force --message-callback '
import re
msg = message.decode("utf-8")
# drop trailer lines and any blank lines they leave behind
lines = [l for l in msg.splitlines()
         if not re.search(r"(?i)co-authored-by:.*claude", l)
         and not re.search(r"(?i)generated with \[?claude", l)
         and not re.search(r"(?i)noreply@anthropic", l)
         and "\U0001F916 Generated" not in l]
out = "\n".join(lines).rstrip() + "\n"
return out.encode("utf-8")
'
```
NOTE: `git filter-repo` removes the `origin` remote by design. Re-add it
afterward (`git remote add origin git@github.com:timblaktu/nixcfg.git`).

ALTERNATIVE (no filter-repo): `git rebase -i cc71386~1` and `reword` each of the
10 commits. Interactive rebase is NOT supported in the Claude Bash environment —
the user must run this manually, OR use the non-interactive filter-repo path.

### Step 2 — Verify
```bash
git log cc71386~1..HEAD --format='%H %B' | rg -i 'co-authored-by:.*claude|generated with \[?claude|noreply@anthropic' && echo "STILL DIRTY" || echo "CLEAN"
```
Expect CLEAN. Confirm the 10 subjects/dates/diffs are otherwise unchanged
(`git log --format='%h %ci %s'` should match the old list minus trailers).

### Step 3 — Force-push public main
```bash
git push --force-with-lease origin main
```
`--force-with-lease` (not `--force`) so a concurrent push aborts rather than clobbers.

### Step 4 — Clean stale branches
```bash
# confirm merged first
for b in fix/claude-memory-nix-managed fix/nixpkgs-update-compat fix/remove-claude-browse fix/remove-claude-code-overlay; do
  git branch --merged main | rg -q "$b" && echo "$b merged" || echo "$b NOT merged - review"
done
# delete local (after confirming) and the stale remote branch
git push origin --delete fix/nixpkgs-update-compat
```

### Step 5 — Re-lock nixcfg-work
```bash
cd ~/src/nixcfg-work   # or wherever the work worktree lives
nix flake update nixcfg    # repins nixcfg input to new HEAD SHA
git add flake.lock
git commit -m "chore: repin nixcfg input after upstream history rewrite"
git push   # to git.panasonic.aero
```

### Step 6 — Local clones / worktrees
For any other local nixcfg clone: `git fetch origin && git reset --hard origin/main`.

### Step 7 — Update memory
Delete or rewrite `project_ai_attribution_leak.md` to reflect resolution; remove
its MEMORY.md index line.

## Residual risk after completion
- Old SHAs persist in GitHub's reflog, cached views, and any open PR refs for a
  while; GitHub GCs eventually. Nothing actionable, just not instantaneous.
- Anyone who pulled the old history keeps it until they reset.

## Definition of Done
- `origin/main` history contains zero AI-attribution markers (Step 2 CLEAN on the
  pushed remote).
- nixcfg-work flake.lock repinned and pushed; `nix flake check` clean there.
- Stale branches (local + `origin/fix/nixpkgs-update-compat`) removed.
- Memory updated.
