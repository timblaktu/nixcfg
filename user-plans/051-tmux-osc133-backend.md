# Plan 051 — tmux `osc133` command-status backend (deferred from Plan 050 / D1)

Status: PLANNING (blocked on Plan 050)
Working branch: TBD (create from the branch that lands Plan 050; do NOT use main/master)
Owner: Tim
Created: 2026-08-17
Depends on: **Plan 050** (`.claude/user-plans/050-tmux-status-declarative-refactor.md`)
must be COMPLETE — specifically its `hooks` backend + the abstract per-pane
"state provider" seam that makes the backend a source-term swap.

> Not burndown-eligible yet (no `Burndown: SAFE`): this plan is blocked on Plan 050
> and its T1 requires an interactive choice about how tmux 3.8 is obtained. Promote
> to burndown only after Plan 050 lands and T1's packaging decision is made.

## Why this plan exists (context — self-contained)

Plan 050 builds a declarative, per-pane tmux command/process status indicator. Its
**T2/D1 decision** was: ship the `hooks` backend now (works on the local tmux 3.6a),
and **design** the `osc133` backend as a *swappable per-pane source term* behind an
abstract state-provider seam — but do NOT implement `osc133` in Plan 050. This plan
is that deferred implementation.

**The design invariant Plan 050 leaves in place (the seam this plan fills):** there
is ONE generated `#{P:}` pane-loop priority-fold that aggregates per-pane state into
each window's single status entry. Both backends reuse that exact expression; only
the **per-pane source term** differs:
- `backend = "hooks"` (Plan 050 default): per-pane term = `#{@cmd_state}`, written by
  the shared `tmux-cmd-state` helper from per-shell hooks.
- `backend = "osc133"` (THIS plan): per-pane term = native `#{pane_command_running}`
  / `#{pane_command_status}`, which tmux ≥ 3.8 derives in-process from OSC 133 marks
  — **zero shell→tmux pokes and zero `#()` for shell commands**.

**Two things that do NOT go away on `osc133`** (established in Plan 050 T1, lanes 2-3):
1. **The shell must still EMIT OSC 133** (`;A` prompt-start, `;C` output-start,
   `;D;<exit>` finished+code). OSC 133 standardizes the terminal↔shell wire protocol
   and its meaning, NOT who prints it; upstream bash/zsh do not emit it by default.
   Emission comes from a prompt tool (starship/oh-my-posh/powerlevel10k already do
   it) or a small per-shell integration snippet. So `osc133` relocates+standardizes
   the per-shell piece; it does not eliminate "something in the shell emits state".
2. **Agent "attention" (Claude Code needs-input) can NEVER come from OSC 133** — it
   is not a shell-command lifecycle event. The custom per-pane producer writing
   `set -p @cmd_state attention` stays, OR'd into the same `#{P:}` fold at top
   priority, on BOTH backends.

**Cost that makes this a separate plan:** the local tmux is **3.6a**;
`#{pane_command_running}` / `#{pane_command_status}` / `pane-command-started` /
`pane-command-finished` land in tmux **3.8** (unreleased at time of writing — tmux
master). Realizing `osc133` therefore requires pinning a tmux ≥ 3.8 build (a custom
Nix derivation/overlay) and running a non-release tmux. Released 3.4-3.7 store OSC
133 marks only for copy-mode next-prompt/previous-prompt — no lifecycle format/hook.

**Primary refs** (from `docs/tmux-status-prior-art.md`, Plan 050 T1 lane 2):
- tmux #3064 https://github.com/tmux/tmux/issues/3064 · #5237 https://github.com/tmux/tmux/issues/5237
- `input.c::input_osc_133`; format vars `#{pane_command_running}` (0/1),
  `#{pane_command_status}` (empty until first `;D`, then exit code),
  `#{pane_command_duration}`, `#{pane_command_start_time}`/`_end_time`,
  `#{pane_last_prompt_time}`; hooks `pane-command-started`/`-finished`/
  `pane-shell-prompt`; `set-hook -B` (fire only when a format is true).
- iTerm2 escape codes https://iterm2.com/documentation-escape-codes.html ;
  WezTerm shell integration https://wezterm.org/shell-integration.html

## Design constraints inherited from Plan 050 (do not re-litigate)
- The `#{P:}` aggregation expression and the `states` set/priorities are Plan 050's;
  this plan swaps only the per-pane source term for shell-command states.
- `#{pane_command_running}` is `0`/`1` (safe in `#{?}`). `#{pane_command_status}` is
  **empty until the first command completes** and can legitimately be `0` (success),
  so `error` must be tested as *"set AND != 0"* via `#{&&:}` (Plan 050's fold already
  does this for the osc133 arm; verify it against a real 3.8 build).
- `allow-passthrough` is OUT OF SCOPE — reading `#{pane_command_*}` inside tmux needs
  no passthrough (that only matters for exporting marks to an OUTER terminal).
- Keep `backend = "hooks"` the default; `osc133` is opt-in and asserts tmux ≥ 3.8.

## Tasks

| ID | Task | Status |
|----|------|--------|
| T1 | Obtain tmux ≥ 3.8 (packaging decision + derivation); verify vars exist | TASK:PENDING |
| T2 | Per-shell OSC 133 emitter (or detect prompt-tool provision) | TASK:PENDING |
| T3 | Implement `backend = "osc133"` source term behind the Plan 050 seam | TASK:PENDING |
| T4 | Make `backend` a real dual switch (hooks\|osc133) + tmux≥3.8 assertion | TASK:PENDING |
| T5 | Wire `error` from `#{pane_command_status}` != 0; agent-attention unchanged | TASK:PENDING |
| T6 | Validate parity + multi-pane correctness on a live 3.8 build | TASK:PENDING |

### T1 — Obtain tmux ≥ 3.8 and verify the native vars `TASK:PENDING` (Interactive — packaging choice)
Decide HOW tmux ≥ 3.8 is provided (this is a user choice — mark USER_INPUT_REQUIRED):
(a) overlay pinning `pkgs.tmux` to a tmux master commit (custom `src`/`version`);
(b) a separate `tmux-osc133` package used only where `backend="osc133"`;
(c) wait for an upstream 3.8 release and pin the channel. Then build it and confirm
the format vars/hooks actually exist on the built binary.
**DoD:** the chosen tmux is built and on PATH for the test host, AND
`tmux display -p '#{pane_command_running}'` resolves (empty/0/1, not a literal
`#{pane_command_running}`) AND `tmux display -p '#{pane_command_status}'` exists.
If tmux ≥ 3.8 cannot be built on the host → ENVIRONMENT_NOT_CAPABLE (leave PENDING).

### T2 — Per-shell OSC 133 emitter `TASK:PENDING`
Depends on: T1. Ensure each interactive shell EMITS OSC 133 `;A/;B/;C/;D;<exit>`.
First DETECT whether the user's prompt tool already emits it (starship/oh-my-posh/
powerlevel10k) — if so, no emitter needed for that shell. Otherwise install a
minimal, idempotent emitter: zsh via `add-zsh-hook precmd/preexec`; fish via
`fish_prompt`/`--on-event`; bash via nixpkgs `bash-preexec` (sourced LAST,
idempotent handlers, guard `${bash_preexec_imported:-}`). Marks must be printed to
the terminal (the shell's own stdout), correctly bracketed so `;D` carries `$?`.
**DoD:** in a pane on the T1 tmux, running a command flips
`#{pane_command_running}` 1→0 and sets `#{pane_command_status}` to the command's
exit code (verify a success `0` and a failure non-zero). Idempotent across shell
re-source. No double-emission with a prompt tool that already emits.

### T3 — Implement the `osc133` source term behind the Plan 050 seam `TASK:PENDING`
Depends on: T1, T2, and Plan 050's abstract state-provider seam. Fill the `osc133`
branch of the per-pane source term so the SAME generated `#{P:}` fold consumes
`#{pane_command_running}`/`#{pane_command_status}` for shell-command states, while
agent-attention still comes from `#{@cmd_state}` (unchanged). No `#()`; no shell→tmux
`@cmd_state` pokes for shell commands on this backend.
**DoD:** with `backend="osc133"` set, a running command shows `running`, a finished
command shows `done`, a failed one shows `error`, purely from native vars — verified
live. `nix flake check --no-build` passes.

### T4 — Dual `backend` switch + assertion `TASK:PENDING`
Depends on: T3. Make `programs.tmux.commandStatus.backend` a real enum
`"hooks" | "osc133"` (default `hooks`). On `osc133`, assert the configured tmux is
≥ 3.8 (fail eval with a clear message otherwise) and DISABLE the per-shell
`@cmd_state` command hooks (the shell emits OSC 133 instead), while KEEPING the
agent-attention producer. On `hooks`, behavior is exactly Plan 050's.
**DoD:** toggling `backend` between the two values switches the source term with no
other config change; `osc133` on a < 3.8 tmux fails eval with the assertion message;
`nix flake check --no-build` passes for both values.

### T5 — `error` state from native status; agent-attention parity `TASK:PENDING`
Depends on: T3. Confirm `error` derives from `#{pane_command_status}` "set AND != 0"
(guarded by `#{&&:}` because status is empty until first `;D` and `0` is success),
and that agent-`attention` (CC `Notification` → `set -p @cmd_state attention`) still
folds in at top priority on the osc133 backend.
**DoD:** a 3-pane window where one pane runs, one exits non-zero, one has CC
attention resolves to the highest-priority state (`attention > error > running >
done`) via the single `#{P:}` fold — verified live on the T1 tmux.

### T6 — Full parity + multi-pane validation on a live 3.8 build `TASK:PENDING`
Depends on: T4, T5. Re-run Plan 050's behavior-parity checklist AND the multi-pane
correctness test against `backend="osc133"`: styling re-evaluated every redraw (no
`#()`); running on start, done/error on finish; active pane never shows stale
done/attention; clearOnView clears the viewed pane (after-select-window +
pane-focus-in); CC lifecycle maps correctly; two panes with different states resolve
by priority not last-writer.
**DoD:** every checklist item passes on the osc133 backend; document any 3.8-specific
gotchas found; `nix flake check --no-build` passes. Present results to Tim.

## Guardrails
Serialize all nix (no concurrent nix). No AI attribution in commits. Use Plan 050's
`dev-switch -d` loop for iteration. Pre-commit hook runs `nix flake check` only when
`.nix` is staged (~6 min); `.md`/script-only commits skip it. Building a tmux master
derivation may be slow — treat as a long-running task (poll, don't block).
