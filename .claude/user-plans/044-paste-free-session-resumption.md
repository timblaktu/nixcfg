# 044 - Paste-Free Session Resumption (Checkpoint → Fresh Session → Rehydrate)

Status: PLANNED (no implementation yet)
Created: 2026-06-19
Owner: nixcfg Claude Code config (`modules/programs/claude-code/`)
Related memory: `/home/tim/src/nixcfg/claude-runtime/.claude-max/projects/-home-tim-src-n3x/memory/session-handoff-concurrency-fragility.md`
Related plans: `014-per-worktree-config-isolation.md`, `017-git-safety-hooks.md`, `040-claude-memory-system-analysis.md`, `041-claude-memory-system-fix.md`

---

## 1. Problem statement

The current cross-session handoff protocol (in the global `.claude-max/CLAUDE.md` "Continuation Prompt Protocol") delivers a continuation prompt to the **Windows clipboard via `clip.exe`** (or to `/tmp/continuation.md` for large prompts), and the next session resumes by the user **manually pasting** it.

This is **fundamentally unreliable on this machine** because many Claude Code sessions run **concurrently on one Linux node**. Both the clipboard (a shared ~15-entry Win+V ring) and `/tmp/continuation.md` (a single shared file) are **global single slots** that any concurrent session overwrites.

### Confirmed incident (2026-06-19)
While reconstructing "the last session", `/tmp/continuation.md` (timestamp 09:04) contained a **Plan 173 / `n3x-origin` worktree** handoff, but the actual last session in the **`n3x-airbus-ng` worktree** was **Plan 172 Phase 2**. At that moment ~6 sessions were live simultaneously (timestamps 17:54-17:55): `n3x-origin`, two `adr-converix`, `nixcfg-work`, and two `n3x-airbus-ng`. Trusting the `/tmp` file would have resumed the wrong work in the wrong worktree.

**Root cause:** the handoff travels through a shared global slot, not a per-worktree/per-session-lineage channel.

**Reliable reconstruction source (discovered):** Claude Code stores transcripts **per-cwd** at
`$CLAUDE_CONFIG_DIR/projects/<cwd-slug>/<session-uuid>.jsonl`
(slug = cwd with `/` replaced by `-`). Sorting these by mtime and reading the final assistant message recovers the true last session **for that specific worktree**, immune to clipboard/`/tmp` contamination.
Gotcha: `fd` skips `claude-runtime` because it is git-ignored — use `fd -I` (no-ignore) to find these `.jsonl` files.

---

## 2. Goal (the user's actual mental model)

NOT "continue the same session". The desired loop is **checkpoint → fresh session → rehydrate**:

1. End a session. Its transcript is preserved as its own `.jsonl` (history intact).
2. Start a **brand-new** `claude` session (clean context — the benefit of `/clear`, but without `/clear` and without losing the old transcript).
3. The new session **automatically rehydrates** the working context, primarily by reference to a **persistent plan document that tracks progress against a goal** (the `.claude/user-plans/NNN-*.md` files), with **zero clipboard paste and zero manual labor**.

Explicitly rejected alternatives and why:
- `claude --continue` / `-c` / `--resume`: resumes the **same** session with full transcript reloaded — keeps the old heavy context; not a clean slate. Not wanted.
- `/clear`: clears context in place; user wants a genuinely new session with the prior transcript preserved as a separate file.
- Clipboard / `/tmp` handoff: proven cross-contaminated under concurrency (see §1).

Key property that makes this work: **launching a fresh `claude` writes a NEW transcript file and leaves the old one untouched** — so "end and relaunch" already gives clean context + preserved history. The only missing piece is **auto-injecting the distilled resume context into the fresh session**.

---

## 3. Mechanism: the SessionStart hook

A `SessionStart` hook is a command Claude Code runs **before the first turn** of a session; its output can be injected into the model's context with no user action. This is the rehydration channel.

Reliable, load-bearing facts (treat anything beyond these as TO-VERIFY against the installed CC version in T1):
- **Matchers**: `startup` (fresh `claude`), `resume` (`-c`/`-r`), `clear` (`/clear`), `compact`. Target `startup` (and likely `clear`).
- **Context injection**: print JSON to stdout, exit 0:
  ```json
  {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"…resume text…"}}
  ```
  `additionalContext` is appended as context the model sees on turn one. **(T1-verified on 2.1.158: the JSON form injects — model quoted the sentinel. NOTE the earlier assumption was wrong — plain stdout ALSO enters context in print mode, it is not merely displayed. Use the JSON field for the payload and emit no stray plain text. See §8.)**
- **Env available to the hook** (T1-verified present): `$CLAUDE_PROJECT_DIR` (worktree root) and `$CLAUDE_CONFIG_DIR`; plus the stdin JSON carries `cwd` + `transcript_path` directly (no slug re-derivation needed for source C). Because worktrees have independent working trees, `$CLAUDE_PROJECT_DIR/.claude/…` is a **distinct file per worktree** → no shared-slot clobber across concurrent sessions in *different* worktrees.
- **RESOLVED (T1)**: `initialUserMessage` is **NOT supported** on 2.1.158 — it does not auto-send a first turn (empty `-p` still errors; PTY-interactive never auto-fires). Do NOT rely on it; T6 must instead use an explicit launch-time prompt argument (`claude "…"`). Other reported fields (`sessionTitle`, `watchPaths`, `reloadSkills`) remain unconfirmed and unused — do not depend on them.

### Where this is configured in nixcfg (nix-managed — do NOT hand-edit the deployed files)
The Claude config is generated by the home-manager module `modules/programs/claude-code/`:
- `modules/programs/claude-code/_hm/hooks.nix` — defines `hookEvents` (includes `"SessionStart"`) and the option `programs.claude-code.hooks.custom.<Event>` (an attrs keyed by event name; `SessionStart` slot already scaffolded). This is the **primary extension point**. `mkHook { matcher; command|script; env; timeout; continueOnError; }` builds entries.
- `modules/programs/claude-code/claude-code.nix` — `mkSettingsTemplate` serializes `cfg._internal.hooks` (null/empty slots filtered) into the per-account `settings.json`.
- Deployed artifacts (generated, read-only outputs): `claude-runtime/.claude-max/settings.json` and the per-project `.claude/SessionStart` scripts. **Edit the nix source, rebuild, never the runtime files.**
- ~~Existing `SessionStart` precedent to extend, not replace~~ **(T1-corrected)**: there is NO local SessionStart hook — deployed `.claude-max/settings.json` has only `PreToolUse`/`PostToolUse`. The orphan/low-disk warning text belongs to the **web-only** `.claude/SessionStart` nix-install script, a separate channel. T3 therefore ADDS a fresh SessionStart hook to the (currently empty) slot; nothing local to coexist with.

---

## 4. Design decision: source of the resume content

Three candidate sources, least → most aligned with the "plan document is the persistent tracker" goal. **Recommended: B (primary) + A (optional nuance) + C (fallback).**

- **A. Distilled `HANDOFF.md`** — at session end, the assistant writes the continuation prompt to a gitignored, per-worktree `$CLAUDE_PROJECT_DIR/.claude/HANDOFF.md` *instead of* `clip.exe`; the hook injects it. Same content as today, but reliable and paste-free. Cost: still requires the end-of-session "write the handoff" step.
- **B. Plan-doc-as-source-of-truth (RECOMMENDED)** — the handoff already lives in the plan file (`TASK:PENDING`/`COMPLETE` + Definition of Done). The hook reads a one-line per-worktree pointer `$CLAUDE_PROJECT_DIR/.claude/active-plan` (naming the current plan file path), opens that plan, and injects: plan path + the first `IN_PROGRESS`/`PENDING` task block. Discipline shifts from "write a continuation prompt each time" to "keep the plan's status current as you work" — which is already required. **This eliminates the clipboard ritual entirely.**
- **C. Transcript auto-reconstruction (fallback, zero discipline)** — the hook (or a `/resume` slash command) finds the latest `.jsonl` for the cwd and extracts the last assistant summary (exactly the manual recovery done in §1). No file to maintain, but fuzzier — depends on the last session ending with a clean summary.

These compose: **B for the durable thread, a short A for nuance the plan doesn't capture, C as the safety net when neither was updated.**

### Pull-based companion (already partially present)
A `/resume` (or reuse of the existing `next-task` skill) slash command is the **pull** variant: one keystroke reads the plan and resumes the next task. Strongest setup = **both**: the hook *passively surfaces* the pointer every session (never lose the thread), and `/next-task` (or, if confirmed, the hook's `initialUserMessage`) *acts* on it when ready. Slash commands in nixcfg are defined in `modules/programs/claude-code/_hm/slash-commands.nix`.

---

## 5. Concurrency-safety rules (non-negotiable constraints)

- **Never** route a handoff through a shared single slot (clipboard, `/tmp`) on a multi-session node — proven cross-contaminated (§1).
- Keep handoff/pointer state under `$CLAUDE_PROJECT_DIR/.claude/` and **gitignore it**. Rationale: in some repos `.claude/` is tracked, and plan/task references must not reach git (n3x rule). Files: `.claude/HANDOFF.md`, `.claude/active-plan`.
- **Do NOT** put per-worktree state in `.claude/user-plans` when that path is a **symlink to a shared dir** (true in n3x: `.claude/user-plans` → `~/src/n3x`, shared across all worktrees). In nixcfg, `.claude/user-plans/` is a real tracked directory (plans are committed here) — different convention; this plan file itself lives there.
- **One lean session per worktree at a time.** Two sessions in the *same* worktree still share `HANDOFF.md`/`active-plan`. Parallel work belongs in **separate worktrees** (already the user's practice) — that is the correct isolation granularity.
- The transcript-reconstruction fallback (C) is the only source that is keyed to true session lineage and is therefore the safest disambiguator when same-worktree concurrency is suspected.

---

## 6. Implementation tasks

Progress markers: `TASK:PENDING` / `TASK:IN_PROGRESS` / `TASK:COMPLETE`. A test/verify task is COMPLETE only when it passes.

### T1 - Verify the SessionStart hook output contract against the installed CC `TASK:COMPLETE`
Confirm, on the installed Claude Code version, the exact behavior of: (a) `SessionStart` matchers `startup`/`resume`/`clear`/`compact`; (b) that JSON `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"…"}}` on stdout exit-0 is injected into model context; (c) whether plain stdout is also injected or only displayed; (d) whether `initialUserMessage` is supported. Use a throwaway hook that emits a sentinel string and observe whether the model can quote it on turn one.
**DoD:** a short findings note appended to this plan's "§8 Verified facts" recording exactly which fields/matchers work on the installed version; the design in §3-§4 reconciled with reality (mark any TO-VERIFY items resolved).

### T2 - Per-worktree handoff plumbing (paths + gitignore) `TASK:PENDING`
Decide and document the canonical per-worktree paths (`$CLAUDE_PROJECT_DIR/.claude/active-plan`, `$CLAUDE_PROJECT_DIR/.claude/HANDOFF.md`). Provide a reusable `.gitignore` snippet (or a home-manager-managed `.gitignore` fragment) so these are never tracked in any repo where the loop is used.
**DoD:** documented paths + a copy-pasteable gitignore block; confirmation (`git check-ignore`) that both files are ignored in a sample repo.

### T3 - SessionStart rehydration hook (nix-managed) `TASK:PENDING`
Add a SessionStart hook entry via `programs.claude-code.hooks.custom.SessionStart` (in `_hm/hooks.nix`, or a small new categorized option `hooks.resume`), implemented as a `pkgs.writeShellScript`. Logic: if `$CLAUDE_PROJECT_DIR/.claude/active-plan` exists → read the named plan, extract the first `IN_PROGRESS`/`PENDING` task block + DoD; else if `.claude/HANDOFF.md` exists → use it; else fall back to the latest per-cwd transcript summary (source C). Emit as `additionalContext` JSON, exit 0, <2s, robust to missing files. Must COEXIST with the existing orphan/disk-warning SessionStart hook (additional entry, not replacement).
**DoD:** `nix build`/eval of the home-manager config succeeds; generated `settings.json` contains the new SessionStart hook alongside the existing one; a fresh session in a worktree with a populated `active-plan` shows the model rehydrated with the correct plan + next task.

### T4 - `/resume` (or `next-task`) pull-command parity `TASK:PENDING`
Provide a slash command (new `/resume` in `_hm/slash-commands.nix`, or confirm the existing `next-task` skill covers it) that performs the same plan-pointer read on demand, so resumption works even if the hook is disabled.
**DoD:** invoking the command in a worktree with an `active-plan` resumes the correct next task; documented in the module README/help.

### T5 - End-of-session checkpoint behavior (assistant protocol, not a hook) `TASK:PENDING`
Update the global `.claude-max/CLAUDE.md` "Continuation Prompt Protocol" to: keep the plan doc's task status current as the primary tracker; write the distilled handoff to `$CLAUDE_PROJECT_DIR/.claude/HANDOFF.md` and update `.claude/active-plan` **instead of** `clip.exe`; stop using `/tmp/continuation.md`. (Note: a `Stop`/`SessionEnd` hook cannot *compose* a semantic summary, so this remains an assistant-discipline step — the hook only *surfaces* what was written.)
**DoD:** CLAUDE.md protocol section rewritten; clipboard/`/tmp` path removed or demoted to "last resort, single-session machines only"; cross-reference to this plan + the memory file.

### T6 - Optional fully-hands-free start (REDESIGNED per T1) `TASK:PENDING`
T1 disproved `initialUserMessage` (no hook field auto-fires a turn on 2.1.158). The only hands-free path
is an explicit launch-time prompt argument. If pursued, implement as an opt-in wrapper/alias that runs
`claude "resume the active plan's next pending task"` (the prompt the SessionStart hook would otherwise
have surfaced), behind an explicit flag/marker since auto-starting work is not always desired. Likely
lower priority than the `/resume` pull-command (T4); consider dropping in favor of T4.
**DoD:** opt-in mechanism documented; default OFF; when ON, the wrapper self-resumes the next task without any typing. (Hook-field auto-start is ruled out — see §8.)

### T7 - Validate end-to-end across two worktrees concurrently `TASK:PENDING`
Reproduce the original failure scenario: run sessions in two different worktrees simultaneously, checkpoint both, relaunch both, confirm each rehydrates **its own** plan/handoff with no cross-contamination.
**DoD:** documented test showing worktree A resumes A's plan and worktree B resumes B's plan, with the shared clipboard/`/tmp` no longer involved.

---

## 7. Open decisions (resolve during implementation)
- Hook source precedence when multiple are present: confirm B → A → C ordering (plan pointer wins; HANDOFF.md augments; transcript only as fallback). Or should HANDOFF.md override the plan when both exist (freshest nuance)?
- Should `active-plan` be auto-derived (e.g. most-recently-modified plan in `.claude/user-plans/`) instead of an explicit pointer file, to remove even the one-line write? Trade-off: auto-derivation is wrong when several plans are touched in a session.
- Whether to also handle the `clear` matcher (rehydrate after `/clear`) or only `startup`.
- Whether T6's auto-start belongs in this config at all, or stays a manual `/resume`.

## 8. Verified facts (append T1 findings here)

### T1 findings — installed CC `2.1.158`, verified 2026-06-19

Method: throwaway SessionStart hook layered via `--settings <file>` on the real binary
(`/nix/store/adxi8k34iwjvy9kdmdpi087cmcpywi30-claude-code-2.1.158/bin/claude`), reusing the
`.claude-max` config dir only for auth. No nix-managed files were edited. Sentinels: `ZARQON-7781`
(JSON `additionalContext`), `PLAINWORD-4242` (plain stdout), `BLORP-99` (initialUserMessage probe).

- **(a) Matchers — CONFIRMED.** A fresh headless `claude -p` fires SessionStart with `source: "startup"`.
  Per docs the matcher set is `startup` / `resume` / `clear` / `compact`; the active value is delivered
  to the hook as the stdin `source` field (see stdin contract below). `startup` is the one we target;
  `clear` is the open question in §6 (rehydrate-after-/clear), not blocking.
- **(b) JSON `additionalContext` injection — CONFIRMED.** Stdout
  `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"…"}}` + exit 0 lands in
  model context: the model quoted `ZARQON-7781` on turn one. This is the load-bearing channel for T3.
- **(c) Plain stdout — ALSO INJECTED (corrects plan §3 hedge).** Plain (non-JSON) stdout from a
  SessionStart hook is NOT merely displayed — the model also quoted `PLAINWORD-4242`. So in print mode
  both plain stdout and JSON `additionalContext` enter context. Implication for T3: keep the rehydration
  payload in the JSON `additionalContext` field (documented + structured), and DO NOT emit stray plain
  text we don't want in context. The existing web-only nix-install SessionStart prints plain text that
  WOULD enter context if it ran in a normal session — keep install noise out of the resume hook.
- **(d) `initialUserMessage` — NOT SUPPORTED. T6 is blocked via this mechanism.** Two probes failed:
  empty `claude -p` with the field set still errors `Input must be provided…`; PTY-interactive launch
  with the field set sat at the prompt and never auto-fired a turn (no `BLORP-99`). The field does not
  drive a hands-free first turn on 2.1.158. Docs corroborate the field does not exist.
  → **T6 redesign:** hands-free auto-start cannot come from a hook field. The viable path is launching
  with an explicit first-turn argument (`claude "resume the active plan's next pending task"`) from a
  wrapper/alias/opt-in marker. Reframe T6 around that, or drop it in favor of the `/resume` pull-command (T4).
- **stdin contract — CONFIRMED.** The hook receives JSON on stdin:
  `{"session_id","transcript_path","cwd","hook_event_name":"SessionStart","source":"startup"}`.
  `transcript_path` was `…/.claude-max/projects/-home-tim-src-nixcfg/<uuid>.jsonl` — directly validates
  the §9 per-cwd transcript store and the `-`-for-`/` slug, so source-C reconstruction can read
  `transcript_path`/`cwd` straight from stdin instead of re-deriving the slug.
- **env — CONFIRMED.** `CLAUDE_PROJECT_DIR=/home/tim/src/nixcfg` and `CLAUDE_CONFIG_DIR` are both set
  in the hook environment (per-worktree isolation for T2/T3 holds). Also observed: `CLAUDE_EFFORT=high`,
  `CLAUDE_PLUGIN_ROOT` empty (non-plugin context).
- **Reported-but-unverified fields:** docs list `sessionTitle`, `watchPaths`, `reloadSkills`,
  `suppressOutput`, `systemMessage` as SessionStart output fields. None are load-bearing for this plan
  and none were exercised — treat as unverified, do not depend on them.

### Plan premise correction (discovered during T1)
The plan (§3 last bullet, §6 T3, §9) assumes an EXISTING local SessionStart hook printing
orphan/low-disk warnings that T3 must "extend, not replace." That is inaccurate for local sessions:
the deployed `claude-runtime/.claude-max/settings.json` defines only `PostToolUse` and `PreToolUse`
hooks — there is NO `SessionStart` hook. The orphan/disk warning text is the **web-only**
`.claude/SessionStart` nix-install script (a different, web-session channel). **T3 therefore ADDS a
fresh SessionStart hook**, with nothing local to coexist with; the only coexistence concern is the
web `.claude/SessionStart`, which is a separate file and unaffected.

## 9. References
- Memory: `…/memory/session-handoff-concurrency-fragility.md` (the finding + how-to-apply).
- Transcript store: `$CLAUDE_CONFIG_DIR/projects/<cwd-slug>/<uuid>.jsonl` (per-cwd; use `fd -I`). `$CLAUDE_CONFIG_DIR` = `/home/tim/src/nixcfg/claude-runtime/.claude-max`.
- Nix module: `modules/programs/claude-code/_hm/hooks.nix` (extension point `hooks.custom.<Event>`), `modules/programs/claude-code/claude-code.nix` (`mkSettingsTemplate`), `modules/programs/claude-code/_hm/slash-commands.nix`.
- Existing deployed SessionStart precedent: `claude-runtime/.claude-max/.claude`-equivalent and per-project `.claude/SessionStart` (orphan/disk warnings) — extend, don't replace.
- Global protocol to amend (T5): `claude-runtime/.claude-max/CLAUDE.md` "Continuation Prompt Protocol" + "Session Workflow Protocol".
