# Plan 049 - Fix the project-level PreToolUse hook antipattern (spurious "non-blocking status code" prompt on every edit)

**Owner:** Tim
**Status:** MERGED INTO plan 056 P9 (2026-09-14). Root cause CONFIRMED + fix VERIFIED (2026-08-12). Resolution
(Tim, 2026-09-14, via 056 P9): the durable secret-block is already the nixcfg `hooks.security` module category
(correct jq-stdin/`exit 2`/stderr pattern) — the project-level hooks are redundant AND broken (illusory
protection, only noise). **T3 decision = option (b) REMOVE** the project PreToolUse/PostToolUse hooks (keep
SessionStart). The corp `iaas/hsw` copy is **closed out with NO corp MR** (mirrors 056 P8: opening a
personal-convention MR on a shared team repo is inappropriate; the removal is recorded as a recommendation).
The stale nixcfg-tracked relic `claude-runtime/.claude/settings.json` was stripped of its dead hook blocks in
056 P9. See plan 056 "P9 analysis" + its [DECISION] block for full detail.
**Mode:** human-attended `/next-task`. NOT burndown (touches many git-tracked repos + a cross-cutting decision).

---

## 1. Symptom

On (nearly) every `Edit`/`Write` to a file, Claude Code shows a prompt plus:

```
● Update(<file>)
  ⎿  PreToolUse:Edit hook error
  ⎿  Failed with non-blocking status code: No stderr output
```

Seen "all over the place" - on `.claude/HANDOFF.md`, `.claude/user-plans/*.md`, ordinary source files - not just secret files.

## 2. Root cause (CONFIRMED empirically 2026-08-12)

The **project-level** `.claude/settings.json` (git-tracked, in the n3x/hsw repo and inherited by every worktree) defines a `PreToolUse` hook like:

```json
"PreToolUse": [{
  "matcher": "Edit|Write",
  "matchPaths": ["secrets/.*", "\\.sops\\.yaml", ".*\\.age"],
  "hooks": [{ "type": "command", "command": "echo 'BLOCKED: Secret files must be edited via sops. Run: sops <file>' && exit 1" }]
}]
```

Three compounding bugs:

1. **`matchPaths` is NOT a supported hook key.** Claude Code scopes hooks by `matcher` (which matches the **tool name**, e.g. `Edit|Write`) and expects the hook **script itself** to filter by path (read the path from stdin JSON). Because `matchPaths` is silently ignored, the hook runs on **every** `Edit`/`Write`, regardless of path. (The already-correct GLOBAL hooks in `modules/programs/claude-code/_hm/hooks.nix` do it right: `jq -r '.tool_input.file_path'` from stdin + a `case`, no `matchPaths`.)
2. **`exit 1` is the wrong exit code.** CC exit-code convention for `PreToolUse`: `0` = proceed silently; `2` = **block** the tool and feed **stderr** back to the model; **any other non-zero (incl. `1`)** = "**non-blocking error**" -> CC surfaces a notice/prompt but lets the tool through. So `exit 1` on every edit = a prompt on every edit.
3. **Message goes to stdout, not stderr.** CC reads **stderr** for the error detail; the hook `echo`'d to stdout, so CC reports *"No stderr output."* -> that whole line is CC *describing* the failed hook, a **symptom**, not the cause. The cause is `exit 1`.

Proof: piping `{"tool_input":{"file_path":".claude/HANDOFF.md"}}` into the hook command still prints BLOCKED and exits 1 (it never inspects the path).

## 3. The verified fix (applied + tested in `n3x-vte-seccomp-bench` worktree 2026-08-12)

Rewrite BOTH project hooks to the proven in-script-filter pattern (mirrors the global `hooks.nix`). Full corrected `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/SessionStart" } ] } ],
    "PostToolUse": [ { "matcher": "Edit|Write|MultiEdit", "hooks": [ { "type": "command",
      "command": "file_path=\"$(jq -r '.tool_input.file_path // empty' 2>/dev/null)\"; case \"$file_path\" in *.nix) nixpkgs-fmt \"$file_path\" 2>/dev/null || true ;; esac; exit 0" } ] } ],
    "PreToolUse": [ { "matcher": "Edit|Write|MultiEdit", "hooks": [ { "type": "command",
      "command": "file_path=\"$(jq -r '.tool_input.file_path // empty' 2>/dev/null)\"; case \"$file_path\" in */secrets/*|secrets/*|*.sops.yaml|*.age) echo 'BLOCKED: edit secrets via sops (run: sops <file>)' >&2; exit 2 ;; esac; exit 0" } ] } ]
  }
}
```

Behavior verified: normal file -> `exit 0`, silent; `secrets/x.sops.yaml` -> `exit 2` + stderr message (properly blocks). JSON valid. This also fixes a latent `PostToolUse` bug (the old `nixpkgs-fmt "$FILE_PATH"` used an env var CC never sets + the ignored `matchPaths`, so it ran `nixpkgs-fmt` on an empty arg on every edit).

## 4. Scope of affected files (scanned `~/src` 2026-08-12)

The n3x repo's `.claude/settings.json` is git-tracked, so **all ~34 n3x-* worktrees + hsw-* worktrees carry it** (each at its branch's version - all have the bug). `~/src/*/.claude/settings.json` matching the antipattern: every n3x-*/hsw-* worktree. (Separately: `nixcfg*/claude-runtime/.claude/settings.json` matched the grep too - VERIFY those independently; they are generated runtime, likely a different/benign match, NOT the same tracked project hook.)

Because worktrees share ONE repo, the durable fix is: land the fix on the n3x **default branch**, then each worktree inherits it as it merges/rebases the default branch. For immediate relief in an active worktree before it merges, apply the Section-3 edit locally (uncommitted is fine - CC reads settings live).

## 5. Task cursor

### T1 - Land the settings.json fix on the n3x default branch `TASK:RESOLVED via 056 P9 (2026-09-14)`
RESOLUTION: superseded by the T3 remove decision + P8 corp-repo precedent — NO corp MR is opened (the fix
below is retained only as the historical spec). The recorded team recommendation is to remove the redundant
broken project hooks. Original task text preserved below for reference.

Create a small dedicated branch off the n3x default branch, apply the Section-3 corrected `.claude/settings.json`, open an MR. Keep it isolated (hooks-only change; no plan/task refs in the tracked commit per repo rules).
**DoD:** MR open; the corrected file passes `jq -e .`; the three hook self-tests from Section 3 pass (normal->exit0 silent, secret->exit2+stderr); a reviewer/owner note that merging propagates to all worktrees on subsequent merge. Reference the technical root cause in the commit body, NOT this plan number.

### T2 - Immediate relief for currently-active worktrees `TASK:SUPERSEDED (2026-09-14) by the T3 remove/no-MR decision`
SUPERSEDED: T2 was the stopgap for T1's durable fix. With T3 = option (b) remove and the corp copy closed out
with NO corp MR (per 056 P9 / P8 precedent), there is no Section-3 edit to apply locally. The noisy corp hook
is a recorded remove-recommendation, not an active migration. No per-worktree action pursued. Original below.
For each worktree the owner is actively using (not all 34), apply the Section-3 edit locally so the prompt stops now without waiting for a default-branch merge. Idempotent: skip a worktree whose `.claude/settings.json` already lacks `matchPaths`/`exit 1`.
**DoD:** `rg -l 'matchPaths|exit 1' <active-worktrees>/.claude/settings.json` returns empty for the active set. Depends on: none (independent of T1; T1 is the durable fix, T2 is the stopgap).

### T3 (optional, owner decision) - Should project hooks exist at all, or defer to global? `TASK:DECIDED (2026-09-14) = option (b) REMOVE` Interactive
DECISION (Tim, via 056 P9): **option (b)** — the global nixcfg `hooks.security` category already blocks
secrets correctly, so the project hooks are redundant; the project PreToolUse/PostToolUse blocks should be
REMOVED (keep SessionStart). For the corp `iaas/hsw` repo this is recorded as a recommendation only (no MR,
per the P8 precedent). Original option text below.
The GLOBAL nixcfg hooks (`_hm/hooks.nix`) ALREADY do secret-blocking + auto-format correctly. The project hooks duplicate that (badly). Options: (a) fix-in-place (Section 3) so the protection is portable for non-Tim contributors who lack the global hooks; (b) remove the project hooks entirely and rely on global (simpler, but drops protection for other contributors/CI). Owner decides. If (a) stays, the fixed project hook and the global hook both run (harmless - both no-op on non-secrets).
**DoD:** owner records the decision; if (b), a follow-up removes the project PreToolUse/PostToolUse blocks (keep SessionStart).

### T4 (optional) - Build detection into the user-global context `TASK:CLOSED (2026-09-14) — optional, not pursued`
CLOSED: with 056 P9 the antipattern is eliminated at the source (project hooks removed/redundant; the module
`hooks.security` is already the correct pattern), so the auto-detection gotcha is marginal. Left unpursued to
keep plan 049 fully non-actionable (determinism). The antipattern is documented in this plan (§2) + 056 P9 if
a future session needs the reference; may be re-opened as a fresh small task if desired. Original text below.
Add a concise gotcha to the user-global CLAUDE.md source (in `modules/programs/claude-code/_hm/`) so future sessions auto-recognize + fix this antipattern: "A project `.claude/settings.json` hook using `matchPaths` and/or `exit 1` is buggy - `matchPaths` is ignored (filter path in-script via `jq -r '.tool_input.file_path'`) and `exit 1` triggers a spurious non-blocking-error prompt on every edit; block with `exit 2`+stderr, else `exit 0`." Keep it one gotcha, not a narrative.
**DoD:** the gotcha is in the CLAUDE.md SoT, rebuilt via home-manager, visible in `claude-runtime/.claude-max/CLAUDE.md`.
