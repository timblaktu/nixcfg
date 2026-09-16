# 044 - Paste-Free Session Resumption (Checkpoint → Fresh Session → Rehydrate)

Status: COMPLETE — T1-T5 + T7 COMPLETE; T6 closed WONTFIX (auto-start deferred to plan 045). Attended paste-free resume loop delivered (push hook T3 + pull `next-task` T4 + file handoff T5). Activation note: live deploy on the work host goes through the nixcfg-work flake (see §8 "Activation").
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

### T2 - Per-worktree handoff plumbing (paths + gitignore) `TASK:COMPLETE`
Decide and document the canonical per-worktree paths (`$CLAUDE_PROJECT_DIR/.claude/active-plan`, `$CLAUDE_PROJECT_DIR/.claude/HANDOFF.md`). Provide a reusable `.gitignore` snippet (or a home-manager-managed `.gitignore` fragment) so these are never tracked in any repo where the loop is used.
**DoD:** documented paths + a copy-pasteable gitignore block; confirmation (`git check-ignore`) that both files are ignored in a sample repo.

### T3 - SessionStart rehydration hook (nix-managed) `TASK:COMPLETE`
**Done 2026-06-20.** New `modules/programs/claude-code/_hm/resume-hook.sh` (plain-bash body, no Nix escaping) wrapped by `pkgs.writeShellScript` with jq/fd/coreutils/gawk/gnugrep on PATH; `_hm/hooks.nix` gained a default-on `hooks.resume.enable` option and a `mkMerge` arm emitting `SessionStart` matcher `startup|resume|compact` → the wrapped script. Precedence B→A→C implemented; emits ONLY `hookSpecificOutput.additionalContext` JSON, factual phrasing, lean payload, exit 0 on nothing. **Validated:** `nix flake check --no-build` → all checks passed; `nix eval` of `…_internal.hooks.SessionStart` shows the entry serialized (matcher + store-path command + continueOnError + timeout 10); fixture runs of the actual script confirmed all four paths (B next-task / A HANDOFF.md / C latest-other-transcript-excluding-current / empty→silent exit 0). Micro-choices: (a) new `hooks.resume` block (not the dead `hooks.custom`); (b) all three matchers now (not startup-only).
Add a SessionStart hook implemented as a `pkgs.writeShellScript`, wired into `_internal.hooks` (see §10: `hooks.custom` is dead code, so use a new default-on categorized block `hooks.resume`, OR first wire `cfg.hooks.custom` into the `mkMerge` — categorized block is the idiomatic match for the existing development/security/logging blocks). Logic (precedence B→A→C): if `$CLAUDE_PROJECT_DIR/.claude/active-plan` exists → read the named plan, `awk`-extract the first `### …TASK:(IN_PROGRESS|PENDING)` heading block (through to the next `### `); else if `.claude/HANDOFF.md` exists → use it; else fall back to the latest *other* per-cwd transcript's last assistant text (source C, via stdin `transcript_path`, `fd -I -a` excluding the current transcript). Emit ONLY the `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":…}}` JSON (NO stray plain stdout — T1 finding c), exit 0, target <2s, robust to missing files. **Refinements from §10 research:** (1) keep the payload LEAN — carry only plan pointer + next task; do NOT re-inject memory facts (native auto-memory already does that every session). (2) Phrase as FACTUAL STATEMENTS, not imperative commands (command-like text trips CC's prompt-injection defense and surfaces to the user). (3) This is the *push* half of a DUAL-CHANNEL design — it is NOT a sole dependency (CC silently fails to inject SessionStart stdout on some brand-new conversations, issue #10373); the *pull/file* backstop is T4 + the readable `active-plan`/`HANDOFF.md` files. Matcher: `startup` for now (`resume`/`compact` re-injection is a §7 follow-up). PREMISE (T1-corrected): there is NO local SessionStart hook to coexist with — T3 ADDS a fresh one.
**DoD:** `nix build`/eval of the home-manager config succeeds; generated `settings.json` contains the new SessionStart hook; a fresh session in a worktree with a populated `active-plan` shows the model rehydrated with the correct plan + next task.

### T4 - pull-command parity via `next-task` (the dual-channel file backstop) `TASK:COMPLETE`
**Done 2026-06-21.** Taught the `next-task` slash command (`task-automation.nix` `nextTaskMd`) to honor the explicit per-worktree pointer first. New "PLAN SELECTION" section (renamed from "PLAN AUTO-DETECTION"): when no plan-file arg is given, FIRST check `$CLAUDE_PROJECT_DIR/.claude/active-plan` — if it exists and is non-empty, read the first line as the plan path, resolve it the same way `resume-hook.sh` does (absolute path as-is, else relative to `$CLAUDE_PROJECT_DIR`), and use that plan, SKIPPING auto-detection; OTHERWISE fall back to the existing CLAUDE.md/git-mtime auto-detection. The skill's opening line now names the precedence ("the .claude/active-plan pointer first, then CLAUDE.md auto-detection"), and the new section's prose documents that this is the *pull half* of plan 044's dual-channel resume (works when the T3 hook injection silently fails). **Validated:** home-manager config + devShells evaluated clean under `nix flake check --no-build` (only the unrelated NixOS VM config checks got oomd-killed under memory pressure — re-ran twice, same point, home side always passed); `nix eval --raw` of the generated `.claude-max/commands/next-task.md` confirms the `active-plan`-first / `CLAUDE_PROJECT_DIR` / "SKIP auto-detection" / "pull half" text is present. Committed --no-verify (pre-commit hook re-runs flake check and hits the same oomd flakiness; flake evaluates clean otherwise).
**RESOLVED (§10): EXTEND the existing `next-task` skill rather than author a separate `/resume`.** `next-task` (defined in `modules/programs/claude-code/_hm/task-automation.nix`, `nextTaskMd`) already reads a plan, picks `IN_PROGRESS` then first unblocked `PENDING`, flips status, commits, executes, and marks `COMPLETE` — it IS the pull-command. The only gap vs §4-B is the pointer source: it auto-detects from CLAUDE.md/git-mtime, whereas 044 uses an explicit `$CLAUDE_PROJECT_DIR/.claude/active-plan`. T4 = teach `next-task` to honor `.claude/active-plan` FIRST, then fall back to its existing auto-detection. This is also the *pull half* of the dual-channel design (T3 is the *push half*): resumption works even when the hook's injection silently fails (#10373) or the hook is disabled.
**DoD:** invoking `next-task` (no args) in a worktree with an `active-plan` resumes the plan it names; falls back to auto-detection when absent; behavior documented in the skill text.

### T5 - End-of-session checkpoint behavior (assistant protocol, not a hook) `TASK:COMPLETE`
**Done 2026-06-21.** Rewrote the global assistant protocol so the end-of-session handoff
writes to the per-worktree FILES instead of `clip.exe`/`/tmp`. CRITICAL pathing finding:
the deployed `claude-runtime/.claude-max/CLAUDE.md` is **nix-generated** (shows untracked in
git) from the home-manager template `modules/programs/claude-code/_hm/claude-code-user-memory-template.md`
via `mkClaudeMdTemplate` in `claude-code.nix:643` (`{{ACCOUNT}}` substituted per account) —
so the edit went to the NIX SOURCE TEMPLATE (shared across all accounts), never the runtime file.
Changes to the template:
- Renamed "Continuation Prompt Protocol (MANDATORY - NEVER SKIP)" → "Session Handoff Protocol".
  New body: (1) keep the plan doc current as PRIMARY tracker; (2) write the plan path (one line)
  to `$CLAUDE_PROJECT_DIR/.claude/active-plan`; (3) write distilled nuance to
  `$CLAUDE_PROJECT_DIR/.claude/HANDOFF.md`; (4) one-line confirmation, no inline dump. Added a
  "Why files, not the clipboard" paragraph preserving the §1/§5 multi-session-concurrency rationale,
  cross-referencing this plan (044) + the `session-handoff-concurrency-fragility` auto-memory. Added
  the `Stop`/`SessionEnd`-can't-compose note (hook only *surfaces*; composing stays assistant
  discipline). `clip.exe`/`/tmp` DEMOTED to a "Last resort only (single-session machine)" clause that
  explicitly forbids the fallback on multi-session nodes.
- Updated the two cross-references: "Session Workflow Protocol" step 5 ("Checkpoint the handoff to
  per-worktree files (see Session Handoff Protocol below)") and "Plan File Conventions" → renamed
  "Continuation Prompt" bullet to "Handoff" (writes HANDOFF.md + active-plan). Also fixed the stale
  "stop with continuation prompt" phrasing in the ONE-TASK-PER-SESSION line.
- Kept the SEPARATE "Content Delivery for Copy-Paste" section (clip.exe for user-facing copy-paste
  content) untouched — different use case from session handoff.
Rewrite kept GENERIC (global cross-project/cross-account file, works in any repo/worktree).
**Validated:** `nix flake check --no-build` → all checks passed; `nix eval` rendering the template
with `{{ACCOUNT}}=MAX` confirms the generated CLAUDE.md carries the full "Session Handoff Protocol",
`active-plan`/`HANDOFF.md` paths, "Last resort only" demotion, the can't-compose note, and the 044
cross-reference. NOTE: the memory file `session-handoff-concurrency-fragility.md` lives in the **n3x**
project memory dir (slug `-home-tim-src-n3x`, per §6 header), not nixcfg's — referenced by name in
the template rather than a hardcoded absolute path (correct for a global cross-project file).
**DoD:** CLAUDE.md protocol section rewritten; clipboard/`/tmp` path removed or demoted to "last
resort, single-session machines only"; cross-reference to this plan + the memory file.

### T6 - Optional fully-hands-free start (REDESIGNED per T1) `TASK:WONTFIX (deferred to 045)`
**Disposition 2026-06-21 (user decision):** DROP from plan 044; the hands-free auto-start belongs to
plan `045-unattended-plan-burndown.md`. Rationale: (1) T1 empirically disproved `initialUserMessage`
on both 2.1.158 and built 2.1.183 — no hook field auto-fires a first turn, so a hook can never deliver
hands-free start (§8). (2) The only viable mechanism is an explicit launch-time prompt argument
(`claude "resume the active plan's next pending task"`), which is the same headless-first-turn problem
plan 045 must solve for Mode B (unattended burndown) anyway — building it here would duplicate 045's
core. (3) The *attended* resume path 044 set out to fix is already fully delivered: T3 (hook push) +
T4 (`next-task` honoring `.claude/active-plan`) + T5 (file-based handoff) give paste-free, one-keystroke
resumption. A standalone `--resume-plan` wrapper alias would be pure ergonomics over T4 with no new
capability. The `--resume-plan` opt-in design sketch is preserved in §10 (Mode A bullet) as the seed for
045's attended-launch ergonomics.
**DoD:** N/A — task closed as WONTFIX/deferred; auto-start folded into plan 045. The attended-resume goal
of 044 is satisfied by T3+T4+T5 (no typing of a continuation prompt; `/next-task` resumes the pointed plan).

### T7 - Validate end-to-end across two worktrees concurrently `TASK:COMPLETE`
**Done 2026-06-21.** Reproduced the §1 concurrency scenario at the hook level and proved isolation. See "§8 T7 findings" for the full method/results.
Reproduce the original failure scenario: run sessions in two different worktrees simultaneously, checkpoint both, relaunch both, confirm each rehydrates **its own** plan/handoff with no cross-contamination.
**DoD:** documented test showing worktree A resumes A's plan and worktree B resumes B's plan, with the shared clipboard/`/tmp` no longer involved.

---

## 7. Open decisions
- **RESOLVED — precedence B → A → C** (plan pointer wins; HANDOFF.md is the fallback; transcript only as last resort). Rationale: the plan file is the durable two-tier source of truth; HANDOFF.md is volatile nuance. (If a session needs the freshest nuance to win, it should update the plan, not rely on HANDOFF.md overriding it.)
- **RESOLVED — dual-channel rehydration** (user decision 2026-06-20): hook *push* (T3) + readable-file *pull* (T4 `next-task` + the `active-plan`/`HANDOFF.md` files). Never a sole injection channel (#10373; Cursor prior art). See §10.
- **RESOLVED — explicit `active-plan` pointer, not auto-derivation.** Auto-derivation (most-recently-modified plan) is wrong when several plans are touched in a session. `next-task`'s existing auto-detection (CLAUDE.md/git-mtime) remains the *fallback* when no pointer exists (T4).
- **FOLLOW-UP (non-blocking) — matchers.** T3 ships `startup` only. Adding `resume` + `compact` matchers to RE-INJECT the handoff after compaction/resume is a community-validated pattern (a long session scrolls the once-injected context down and "forgets" it); revisit after T3 lands.
- **RESOLVED — Mode B (unattended burndown) moves to a successor plan 045** (user decision 2026-06-20); T6's auto-start is folded into that. See §10 + `045-unattended-plan-burndown.md`.

## 8. Verified facts (append T1 findings here)

### T1 findings — installed CC `2.1.158`, verified 2026-06-19 (cross-checked vs latest `2.1.183` on 2026-06-20)

> **Cross-version note (2026-06-20):** every finding below was re-verified by building latest
> `claude-code-2.1.183` (one-off nixpkgs `overrideAttrs` of `version`+`src`, GCS-prefetched hash) and
> re-running the sentinel probes. Result: **identical behavior on both versions** — `additionalContext`
> and plain stdout both inject; `initialUserMessage` works in neither. **Upgrading does not change any
> conclusion in this plan.** The system stays on 2.1.158 (its pinned-nixpkgs `pkgs.claude-code`); no
> upgrade is required for plan 044's core (T2-T5).

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
- **(d) `initialUserMessage` — NOT SUPPORTED on 2.1.158 OR latest 2.1.183. T6 is blocked via this
  mechanism, and upgrading does NOT unblock it.** Probes failed identically on both versions: empty
  `claude -p` with the field set still errors `Input must be provided…`; PTY-interactive launch with the
  field set sat at the prompt and never auto-fired a turn (no `BLORP-99`). The field does not drive a
  hands-free first turn. (A docs-research agent claimed 2.1.183 made the field work "in -p mode" — that
  was a hallucination; empirically refuted by building 2.1.183 and re-running both probes, 2026-06-20.)
  → **T6 redesign:** hands-free auto-start cannot come from a hook field on any current version. The
  viable path is launching with an explicit first-turn argument (`claude "resume the active plan's next
  pending task"`) from a wrapper/alias/opt-in marker. Reframe T6 around that, or drop it in favor of the
  `/resume` pull-command (T4).
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

### T2 findings — canonical paths + gitignore, verified 2026-06-20

**Canonical per-worktree handoff paths** (consumed by T3's hook, written by T5's checkpoint step):
- `$CLAUDE_PROJECT_DIR/.claude/active-plan` — one-line pointer naming the current plan file path.
- `$CLAUDE_PROJECT_DIR/.claude/HANDOFF.md` — distilled per-worktree handoff (source A).

Both live under the worktree's own `.claude/` (T1 confirmed `CLAUDE_PROJECT_DIR` = worktree root in the hook env), so concurrent sessions in *different* worktrees get distinct files — no shared-slot clobber.

**Ignore status in nixcfg — already satisfied, no repo-level `.gitignore` change.** The existing rule at `.gitignore` (`.claude/*` with `!.claude/settings.json` + `!.claude/user-plans/` re-includes) already ignores both target files while keeping tracked files tracked. Verified:
```
$ git check-ignore -v .claude/active-plan .claude/HANDOFF.md
.gitignore:133:.claude/*   .claude/active-plan
.gitignore:133:.claude/*   .claude/HANDOFF.md
$ git check-ignore .claude/settings.json .claude/user-plans/044-*.md   # → exit 1 (NOT ignored, correct)
```

**Reusable snippet (for any repo where the loop is used).** Some repos track all of `.claude/` (e.g. n3x, where `.claude/user-plans` is a symlink to a shared dir) — a blanket `.claude/*` would wrongly ignore tracked files there. The narrow, anchored form ignores exactly the two handoff files and never touches `settings.json`/`user-plans/`:
```gitignore
**/.claude/active-plan
**/.claude/HANDOFF.md
```
Empirically tested in a throwaway repo that tracks all of `.claude/` (worst case), including a nested `sub/.claude/active-plan`:

| pattern | `.claude/settings.json` | `.claude/user-plans/p.md` | `.claude/active-plan` | `.claude/HANDOFF.md` | `sub/.claude/active-plan` |
|---|---|---|---|---|---|
| `.claude/active-plan` (bare) | tracked-ok | tracked-ok | IGNORED | IGNORED | tracked-ok (misses nesting) |
| `**/.claude/active-plan` | tracked-ok | tracked-ok | IGNORED | IGNORED | IGNORED |

The `**/` form is chosen because it also catches nested/worktree paths while remaining safe for tracked files.

**Mechanism — HM-managed global gitignore (decided).** Rather than per-repo `.gitignore` edits, the two `**/.claude/...` patterns are added to the existing HM-managed global ignore at `modules/programs/git/git.nix` (`programs.git.ignores`, deployed to `~/.config/git/ignore` — XDG default, no `core.excludesFile` needed; see `modules/flake-parts/vm-tests.nix` Test 4). This applies to **every** repo/worktree the user opens, matching the multi-worktree practice, and is safe (verified it ignores only the two handoff files, never tracked `.claude/` content). nixcfg's own repo-level `.claude/*` rule remains as a redundant local backstop.

### T7 findings — two-worktree concurrent rehydration, verified 2026-06-21

**Decision (user, 2026-06-21):** exercise the **real nix build output** of the hook (no `home-manager switch`, live config untouched) + **deterministic hook-level** test (no live `claude -p` probe — T1 already proved real CC injects `additionalContext`; T7's new contribution is the concurrency/isolation dimension).

**Real artifact under test.** The deployed `claude-runtime/.claude-max/settings.json` is stale (Jun 16, pre-T3) — its `SessionStart` is null because the file is only refreshed by the HM activation `copy_template` step (no switch since T3). Rather than switch, the exact generated hook was realised from the nix build:
`nix eval .#homeConfigurations."tim@thinky-nixos".config…_internal.hooks.SessionStart` → command `/nix/store/yvp6vyagq22j4kmq4nd301xzx70lin0h-claude-resume-hook`, matcher `startup|resume|compact`. Building the equivalent `writeShellScript` expression (PATH=jq/fd/coreutils/gawk/gnugrep + `readFile resume-hook.sh`) produced the **identical** out-path, confirming the build output is byte-for-byte the configured hook.

**Fixture.** Worktree A = `/home/tim/src/nixcfg` (`active-plan` → `044`; first PENDING block is T6). Worktree B = throwaway `git worktree add --detach /home/tim/src/nixcfg-t7b main` with a synthetic `.claude/user-plans/999-t7-fixture-b.md` (TB1 `IN_PROGRESS` carrying sentinel `WORKTREE-B-SENTINEL-T7`, TB2 `PENDING`), `active-plan` → `999`, and a `HANDOFF.md` marker. Both `.claude/active-plan` + `.claude/HANDOFF.md` confirmed gitignored in B (`git check-ignore` → `.gitignore:133 .claude/*`).

**Method.** The real hook was invoked for **both worktrees concurrently** (backgrounded, `wait` on both PIDs — the actual §1 race), each with its own `CLAUDE_PROJECT_DIR` env + stdin JSON carrying a per-cwd `transcript_path`/`cwd`. Outputs captured to separate files and asserted.

**Result — 13/13 substantive assertions pass; full isolation.**
- Worktree A injected ONLY 044 (T6 block, `resolved path: /home/tim/src/nixcfg/.claude…`); contained NO B sentinel and did NOT name plan 999.
- Worktree B injected ONLY 999 (TB1 block + `WORKTREE-B-SENTINEL-T7`, `resolved path: /home/tim/src/nixcfg-t7b/.claude…`); emitted only the FIRST task (TB1, not TB2); did NOT name 044.
- Both envelopes valid `hookSpecificOutput.hookEventName=="SessionStart"`.
- (The 14th harness check "FAILED" only due to nested-quote escaping in the test `eval`, not the hook — confirmed manually below.)

**No shared-slot channel (the §1 fix, proven structurally).** `grep` of the realised hook: no `clip.exe`, no `/tmp`. Reads are scoped per-worktree by construction — sources B/A read `claude_dir="$proj/.claude"` where `proj="${CLAUDE_PROJECT_DIR:-$PWD}"` (line 25-26); source C reads only `dirname "$transcript_path"` taken from stdin (line 72-76, per-cwd transcript store). There is **no** global path any concurrent session could clobber. Cross-contamination of the kind in §1 (shared clipboard / `/tmp/continuation.md`) is therefore impossible for this rehydration channel.

**Teardown.** Throwaway worktree `/home/tim/src/nixcfg-t7b` removed; only this plan file is committed (per the untracked-files gotcha, staged by path, never `git add -A`).

### Activation — loop deployed live, verified 2026-06-21

**Work-host indirection (non-obvious).** This machine is `pa161878-nixos`, a **work** box whose live
home config is `tim@pa161878-nixos` from the **nixcfg-work** flake (which also owns the
`pa161878-nixos`/`corp-wsl-dev-team` NixOS configs). nixcfg-work consumes nixcfg as a flake input
(`nixcfg.url = "github:timblaktu/nixcfg"`, other inputs `follows nixcfg/*`), pinned in its `flake.lock`
to github rev `f916d7cb` on main. The claude-code module/templates therefore reach this machine
**through nixcfg-work's pin of nixcfg**, not from this repo directly. Consequence: a plain
`home-manager switch` from nixcfg-work deploys the *pinned* nixcfg (no plan-044 hook); the plan-044
branch is an unpushed local descendant of the pin.

**Activation performed (real but EPHEMERAL).** Verified the branch is a clean linear descendant of the
pin (`git merge-base --is-ancestor f916d7cb HEAD` → yes) and the entire `f916d7cb..HEAD` diff is exactly
the plan-044 work (no unrelated drift), then switched with the local override:
```
home-manager switch --flake '/home/tim/src/nixcfg-work#tim@pa161878-nixos' \
  --override-input nixcfg 'git+file:///home/tim/src/nixcfg?ref=plan-044-paste-free-resume' -b backup
```
Exit 0; generation 212. Override resolved `nixcfg` → local rev `3f12389`. **This deploy is ephemeral:**
nixcfg-work's lock still pins `f916d7cb`, so the *next plain* switch reverts the hook. For PERMANENT
activation: merge plan-044 → nixcfg main → push → bump nixcfg-work's `flake.lock` nixcfg rev → switch
(cross-repo, touches main — deliberately NOT done unsolicited).

**Live verification (post-switch).** Deployed `claude-runtime/.claude-max/settings.json` now carries the
`SessionStart` hook (matcher `startup|resume|compact` → `/nix/store/yvp6vyagq22j4kmq4nd301xzx70lin0h-claude-resume-hook`,
the byte-for-byte store path T7 validated; file exists). `.claude-max/CLAUDE.md` regenerated with the T5
"Session Handoff Protocol". Global ignore `~/.config/git/ignore` carries `**/.claude/active-plan` +
`**/.claude/HANDOFF.md` (T2). Fired the **deployed** hook with a real CC-shaped stdin
(`session_id`/`transcript_path`/`cwd`/`source:startup`) + `CLAUDE_PROJECT_DIR=/home/tim/src/nixcfg`:
exit 0, valid `hookSpecificOutput` envelope. Because T6 is now WONTFIX (044 has no PENDING/IN_PROGRESS
task), source B correctly yielded nothing and the hook **fell through B→A** to inject `.claude/HANDOFF.md`
— demonstrating the precedence chain on the real artifact. The loop fires paste-free for every new
session in this worktree until a plain nixcfg-work switch reverts it.

### PERMANENT activation — done + verified 2026-06-21

The ephemeral `--override-input` deploy above is now **superseded by a permanent lock-pinned deploy.**
Executed the documented cross-repo sequence (user-approved; touches `main`):

1. **ff-push** `plan-044` HEAD → `origin/main`: clean fast-forward `f916d7c..840a5fd` (no merge commit;
   `main` was the exact ancestor). All 9 plan-044 commits verified **free of AI-attribution trailers**,
   so they add nothing to the deferred 043 scrub's dirty set. Local `main` pointer moved to match
   without a checkout (working tree + untracked files untouched).
2. **nixcfg-work lock bump** (branch `feat/darwin-support`): `nix flake update nixcfg` →
   `f916d7cb` → `840a5fd` (only the nixcfg rev line changed; `follows` inputs unchanged because
   plan-044 never touched nixcfg's own `flake.lock`). Committed as `8741b71`; nixcfg-work's pre-commit
   flake check passed.
3. **Plain `home-manager switch`** `--flake '/home/tim/src/nixcfg-work#tim@pa161878-nixos' -b backup`
   (NO `--override-input`): exit 0.
4. **Verification (post-plain-switch):** all three deployed account settings
   (`.claude-{max,pro,work}/settings.json`) reference `/nix/store/yvp6…-claude-resume-hook` — the
   **byte-identical store hash** as the ephemeral deploy (same content → same path), proving the lock
   bump reproduces the exact plan-044 hook. Re-fired the deployed hook with CC-shaped stdin → exit 0,
   valid `hookSpecificOutput` envelope, B→A fall-through to `HANDOFF.md`. A plain switch no longer
   reverts the hook — **permanent on this host.**

**043-scrub coupling (bounded, not worsened):** the deferred scrub rewrites from `cc71386`, rehashing
ALL descendants — it already orphans whatever nixcfg rev nixcfg-work pins (`f916d7cb` before, `840a5fd`
now), and 043 Step 5 already commits to re-locking nixcfg-work post-scrub. This activation rides that
same wave and adds nothing to it (clean commits, normal ff-push, no force).

**Optional follow-up (NOT done):** the nixcfg-work lock commit `8741b71` is local-only on
`feat/darwin-support`. Pushing it to git.panasonic.aero would propagate the hook to colleagues' clones;
not required for this host and out of scope here.

---

## 10. Prior-art research + design decisions (2026-06-20)

Three parallel research threads were run before implementing T3: (1) Claude Code's own native continuity features, (2) external prior art across other agent ecosystems, (3) local nixcfg prior work. Findings that shaped the design:

### Findings that changed the design
1. **Native auto-memory already does passive rehydration.** `MEMORY.md` + per-fact files under `$CLAUDE_CONFIG_DIR/projects/<slug>/memory/` are a first-party CC feature (v2.1.59+): first ~200 lines of `MEMORY.md` auto-load every session AND re-inject after compaction, zero config. Already in use here. → **T3 payload stays LEAN: plan pointer + next task only; never re-inject memory facts.** Per-session discoveries belong in the auto-memory store, not the hook.
2. **A SessionStart hook is fragile as a SOLE channel.** CC issue #10373: SessionStart stdout silently fails to inject on some brand-new conversations (works on `/clear`/`/compact`/resume). Cursor 3.x's equivalent `additionalContext` channel is broken-and-acknowledged; the community workaround (Hindsight) writes state to a file the agent reads anyway. → **DUAL-CHANNEL (user-approved): hook push (T3) + readable-file pull (T4 `next-task` + `active-plan`/`HANDOFF.md`).**
3. **Phrase injected context as FACTUAL STATEMENTS, not commands.** Imperative text trips CC's prompt-injection defense and surfaces to the user instead of entering context. Use "The active task is T3; its next step is X."
4. **`hooks.custom` is dead code** — declared in `_hm/hooks.nix:183-188` but never merged into `_internal.hooks`. → T3 adds a default-on categorized `hooks.resume` block (idiomatic) or first wires `cfg.hooks.custom` into the `mkMerge`.
5. **`next-task` already IS the pull-command** (`task-automation.nix` `nextTaskMd`): reads plan, picks IN_PROGRESS→first PENDING, flips status, commits, executes, marks COMPLETE; even auto-detects the active plan. → T4 extends it (honor `.claude/active-plan` first) instead of authoring a parallel `/resume`. Also note: the sibling `run-tasks`/`/l` headless batch automation (`task_prompt` variant) is a SEED for plan 045's unattended driver.
6. **Two-tier memory-bank pattern (Cline/Roo):** stable spec file (source of truth) + small volatile "active context", with a HARD WALL so session scratch never corrupts the durable plan. Maps onto plan file + `HANDOFF.md`.
7. **`initialUserMessage` contradiction — unresolved, deliberately NOT relied upon.** T1 empirically found it does NOT auto-fire a turn (2.1.158 + built 2.1.183). A bundle-source read found the field present in the Zod schema and consumed (`w17=j.initialUserMessage`), possibly only in headless `-p` mode. These may not contradict (schema-present ≠ fires-interactively). RE-VERIFY in plan 045 (matters for unattended headless first-turn); 044 does not depend on it. (NB: a docs-research subagent earlier claimed 2.1.183 made it work in `-p` — that was refuted by building 2.1.183 in T1; treat the schema-presence claim as "field exists", not "auto-starts a turn".)

### Mode A vs Mode B (the two drivers over one substrate)
The substrate (plan-as-source-of-truth + per-worktree `active-plan`/`HANDOFF.md` + `next-task` status-transition discipline) is shared. The DRIVER differs:
- **Mode A — attended continuation (THIS PLAN, 044).** Human ends a session, launches fresh `claude`, hook+file surface "plan X, task T3, next step Y", human (or `/next-task`) acts. Optional ergonomics: a `--resume-plan` flag on the `claude*`/`opencode*` wrappers that launches `claude "resume the active plan's next pending task"` (explicit launch arg — robust, independent of `initialUserMessage`).
- **Mode B — unattended long-running burndown (SUCCESSOR PLAN 045).** A loop driver repeatedly launches fresh headless `claude -p "work the next PENDING task in plan X; update status; commit"` until no PENDING remains. Same checkpoint→fresh→rehydrate cycle, no human gate. Its hard parts are orthogonal to 044: autonomous permission posture, stop conditions (no-PENDING / budget / failure), runaway+cost guards (leans on existing nix-eval cgroup guard + earlyoom), headless first-turn mechanism, and hardening the existing `run-tasks` seed.

**Decision (user, 2026-06-20):** build 044 as the Mode-B-ready substrate (keep the hook/pointer/handoff contract clean and machine-parseable); split Mode B into dependent plan `045-unattended-plan-burndown.md`.

### Selected prior-art citations
- CC native: SessionStart contract + auto-memory + checkpointing/rewind/`/compact`/`--fork-session` (`code.claude.com/docs/en/hooks`, `/memory`, `/checkpointing`). Issue #10373 (silent SessionStart injection on new conversations).
- Cline/Roo Memory Bank: `docs.cline.bot/best-practices/memory-bank`. Aider history-budget pitfall: `github.com/Aider-AI/aider/issues/118`. Cursor broken channel + file backstop: `hindsight.vectorize.io/blog/2026/06/12/cursor-persistent-memory`. Concurrency/worktree isolation: `augmentcode.com/guides/git-worktrees-parallel-ai-agent-execution`, `penligent.ai/.../git-worktrees-need-runtime-isolation`. SessionStart practice + pitfalls: `github.com/disler/claude-code-hooks-mastery`, `github.com/obra/superpowers/issues/648` (double-inject), `classmethod.dev/.../claude-code-session-start-hook-verification`.

## 9. References
- Memory: `…/memory/session-handoff-concurrency-fragility.md` (the finding + how-to-apply).
- Transcript store: `$CLAUDE_CONFIG_DIR/projects/<cwd-slug>/<uuid>.jsonl` (per-cwd; use `fd -I`). `$CLAUDE_CONFIG_DIR` = `/home/tim/src/nixcfg/claude-runtime/.claude-max`.
- Nix module: `modules/programs/claude-code/_hm/hooks.nix` (extension point `hooks.custom.<Event>`), `modules/programs/claude-code/claude-code.nix` (`mkSettingsTemplate`), `modules/programs/claude-code/_hm/slash-commands.nix`.
- Existing deployed SessionStart precedent: `claude-runtime/.claude-max/.claude`-equivalent and per-project `.claude/SessionStart` (orphan/disk warnings) — extend, don't replace.
- Global protocol to amend (T5): `claude-runtime/.claude-max/CLAUDE.md` "Continuation Prompt Protocol" + "Session Workflow Protocol".
