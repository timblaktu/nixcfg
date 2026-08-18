# tmux upstream-contribution assessment (Plan 050 T7)

Assessment date: 2026-08-17. Branch `feat/tmux-command-status-indicator`.
Reviews the design PROPOSAL frozen in Plan 050 T2 (decisions D1-D9 + the
`programs.tmux.commandStatus` schema) and the T1 findings
(`docs/tmux-status-prior-art.md`) for suitability as a **technical upstream
contribution to the tmux project**. No code is submitted upstream in this task;
this is a written go/no-go assessment.

Upstream state verified against tmux `master` @ `30abbe36` (2026-08-17), the
GitHub API, and a local clone. Latest release tag is **3.7c**; the OSC 133
command-lifecycle work is in `master` targeting the **unreleased 3.8**.

## TL;DR — the recommendation

**Conditional GO, but on a MUCH smaller kernel than the plan implies, and NOT
yet.** Almost everything in the T2 proposal is either (a) already provided
natively by tmux 3.8, or (b) Nix/home-manager/app glue that is out of scope for
upstream. After stripping both, exactly **one** general, upstreamable primitive
remains:

> **a window-level aggregate of per-pane command state** — native format
> variables `#{window_command_running}` (and optionally
> `#{window_command_exit}` / a "worst exit status" rollup), mirroring the
> existing `#{window_activity_flag}` / `#{window_bell_flag}` /
> `#{window_silence_flag}` machinery.

This is a real, confirmed gap (there is no `window_command_*` var in `master`),
it mirrors an existing precedent almost exactly, and the maintainer has *already
mused about it himself* on issue #5237 ("monitor-command like monitor-silence
... a window-level feature"). That is the strongest possible sign a proposal is
in-scope. The reasons it is **conditional** and **not yet**:

1. The natural precedent it must engage (#5237, the 3.8 OSC 133 work) closed
   only 2026-08-06 and **has not shipped in a release**. Proposing a window-level
   aggregate before 3.8 is even tagged is premature; the right move is to build
   on the shipped pane-level vars, live with them, and propose the aggregate as a
   focused follow-up in the same thread's lineage.
2. nicm attached a real reservation to the window-level idea ("might not work so
   well") — so the proposal must pre-empt the aggregation-semantics questions
   (per-session winlink vs per-window; how "exit status" aggregates; clear-on-
   view) rather than hand them to him.
3. The contribution is small enough that its value is "saves every user a
   `#{P:}` fold," not "unlocks something impossible." That is still worth doing
   (the `#{P:}` fold is genuinely unsolved across the plugin ecosystem — see T1),
   but it sets the effort/ambition bar low: one format callback family + a flag
   maintained in the monitor path, framed as the minimal mirror of the alert
   flags.

Net: **GO to prepare the proposal now (this doc + a draft), but GATE the actual
submission on tmux 3.8 shipping**, and submit it as a narrow "add the missing
window-level command aggregate to match `window_*_flag`" patch, stripped of every
Nix/agent/attention concept. Everything else in Plan 050 stays downstream in
nixcfg and is not upstream material.

---

## 1. Separating the tmux-GENERAL kernel from the Nix glue

The T2 proposal has four layers. Only the first is even a candidate for upstream,
and 3.8 has already absorbed most of it:

| Layer | In the T2 proposal | Upstreamable? | Why |
|---|---|---|---|
| **Per-pane command lifecycle** | `backend="hooks"`: a `tmux-cmd-state` helper writes `set -p @cmd_state {running,done,error}` from shell preexec/precmd + CC hooks | **NO — already native in 3.8** | `#{pane_command_running}`, `#{pane_command_status}`, `#{pane_command_duration}`, hooks `pane-command-{started,finished}` + `pane-shell-prompt`, all from OSC 133 A/B/C/D parsed in `input.c`. Our `@cmd_state` is a pre-3.8 userspace polyfill of exactly this. |
| **Pane→window aggregation** | the generated `#{P:}` priority-fold that reduces N panes to the one window entry | **YES — this is the kernel** | Confirmed: **no** `#{window_command_*}` var exists in `master`. The `#{P:}` fold is a userspace workaround for a genuine native gap. |
| **State model / channels / clearOnView / sources** | `states` attrset, priorities, `channels`, `clearOnView`, `sources`, `alert`, `monitorFallback` | **NO — downstream policy** | These are UX/config-surface decisions and a Nix module API. tmux already gives the raw signals + `set-hook -B -T` + styling formats; how a *user* composes them into a status bar is `.tmux.conf`/home-manager territory, not a tmux feature. |
| **Cross-module Nix seam / CC integration** | shared lib `modules/lib/tmux-cmd-state.nix`, `programs.<prog>.tmuxStatus.events`, read-only `sources` registry | **NO — pure Nix/app glue** | Nothing tmux-shaped. Out of scope entirely. |

**Conclusion:** the *only* general tmux primitive worth proposing is the
window-level aggregate of per-pane command state. The T1 doc already identified
this ("No window-level OSC 133 aggregate exists ... the `#{P:}` fold is
mandatory") — this assessment confirms it against `master` and elevates it to the
sole upstream candidate.

### What 3.8 already gives us (so we do NOT propose it)

Verified present in `master`:

- Format vars: `#{pane_command_running}` (0/1), `#{pane_command_status}` (exit
  code, empty until first `;D`), `#{pane_command_duration}`,
  `#{pane_command_start_time}` / `#{pane_command_end_time}`,
  `#{pane_last_prompt_time}`.
- Hooks: `pane-command-started`, `pane-command-finished`, `pane-shell-prompt`
  (payloads carry exit status + timings), built on the new generic events infra
  (`d29aa12` "Replace the notification system with events").
- `set-hook -B -T '<format>'` — a monitor that fires a hook only when a format
  expression becomes true (nicm's own example targets long-running commands:
  `#{&&:#{pane_command_running},#{e|>:#{pane_command_duration},10}}`).

This means the plan's `backend="osc133"` (deferred to plan 051) is not a nixcfg
invention to defend upstream — it is just *consuming* shipped 3.8 vars. Good:
plan 051 rides the standard, it doesn't fork it.

---

## 2. Generality pressure-test — strip every app-specific concept

The T2 proposal is saturated with concepts a tmux maintainer would (correctly)
reject. For the upstream kernel these must be expunged entirely:

| Downstream concept (T2) | Upstream verdict | Generic re-expression (if any) |
|---|---|---|
| `attention` state, "agent needs input" | **REJECT** — app-specific, not a command lifecycle at all; OSC 133 never covers it | none. Stays 100% downstream (`@cmd_state attention` is a nixcfg user-option, invisible to any upstream feature). |
| `error` state = non-zero exit | **GENERALIZE** — this is just "exit status != 0", already derivable from `#{pane_command_status}` per-pane | at the window level: an aggregate exit rollup, phrased purely as exit-status arithmetic, never "error". |
| `claude-code` / `sources` / `events` | **REJECT** — application wiring | none. Downstream only. |
| `style`/`channels`/`clearOnView`/palette presets | **REJECT** — status-bar styling policy | tmux already exposes `window-status-*-style`; users compose. Not a feature. |
| priority fold `attention>error>running>idle` | **REJECT the ordering** (it encodes attention) — but the *mechanism* "reduce panes to a window bit" is the kernel | a bare boolean aggregate (`window_command_running` = any pane running) + a defined exit-status rollup; no opinion about priority/attention. |

**The residue after stripping is provably generic:** "tmux tracks per-pane
command state (it already does, natively); expose the same rollup at the window
level that it already exposes for activity/bell/silence." There is no "agent," no
"attention," no app name, no styling — just a format variable mirroring three
that already exist. That is the test the proposal must pass, and this residue
passes it.

---

## 3. Fit with tmux idioms + maintainer norms

Evidence gathered on the actual (not nominal) contribution process:

- **Flow:** GitHub PRs and `tmux-users@googlegroups.com` are both entry points,
  but nicm typically **hand-applies a rewritten variant to the OpenBSD CVS tree
  and closes the PR** rather than merging it (of the last 100 closed PRs, only 7
  were merged; representative closes: *"Applied to OpenBSD now, will be in GitHub
  later"*). No `CONTRIBUTING` file, no CLA, no DCO. Success = your feature lands
  in his words, not your green merge button. Plan accordingly: submit a minimal,
  correct patch and expect it to be re-written.
- **Minimalism / anti-bloat is real and documented.** On the OSC 133 origin issue
  #3064 nicm rejected "extensions ... don't look of much use" and told the
  contributor to ship one small concrete thing first. On #5237 he rejected the
  "forward OSC 133 to the outer terminal" framing outright ("not something tmux
  is going to be able to do ... meant for shells, not full screen programs") and
  instead **implemented native support himself, data-first** (parse marks → store
  per-pane metadata → fire hooks → add format vars → *then* consider UI
  separately). An app-specific or "forward it out" framing is dead on arrival; a
  minimal, general, data-first mirror of existing machinery is the accepted shape.
- **Accepted recent precedent for exactly this shape:** `bdd78ce` "Handle OSC 9;4
  progress bar sequence and store in format variables" and the whole 3.8 OSC 133
  var/hook set — i.e. *parse-a-signal-into-format-vars* is a blessed pattern.
- **C style (KNF / `style(9)`, enforced by review, no `.clang-format`):** hard
  tabs, return type on its own line + function name at column 0, declarations at
  top of block tab-aligned in columns, `return (x);` parenthesized, OpenBSD safe
  libc (`xstrdup`/`format_printf`), 80-col soft limit, ISC header.
- **How a format var is added (2 sites in `format.c`):** a static callback
  `format_cb_<name>(struct format_tree *ft)` returning a heap string (or NULL),
  plus an **alphabetically-sorted** row in `format_table[]`:
  `{ "window_command_running", FORMAT_TABLE_STRING, format_cb_window_command_running }`.
  Backing state lives on the struct (pane vars read `wp->flags & PANE_CMDRUNNING`,
  `wp->cmd_status`, etc.).
- **How window aggregates actually work (precedent to mirror):** `#{window_bell_flag}`
  et al. do **not** scan panes at eval time — they read a pre-aggregated bit on
  the per-session `winlink` (`ft->wl->flags & WINLINK_BELL`), set eagerly by the
  monitor/alerts path (`alerts.c`) when any pane triggers, with a parallel
  `WINDOW_*` bit on `struct window`. A faithful `#{window_command_running}` would
  set/clear a `WINDOW_CMDRUNNING`-style bit as panes enter/leave
  `PANE_CMDRUNNING`, and expose a one-line callback reflecting it. (A lazy
  "iterate `w->panes` in the callback" variant is simpler but unlike the existing
  flags — the eager form matches precedent and nicm's data-first preference.)

The proposal's kernel fits all of these: it is minimal, general, composes with
existing formats/styles, is zero-cost when unused, and its naming
(`window_command_running`) is consistent with both `#{pane_command_*}` and
`#{window_*_flag}`.

---

## 4. Contribution FORM — options weighed

**(a) Native window-level format vars — RECOMMENDED.**
Add `#{window_command_running}` (any pane in the window currently running a
command) and, optionally, an exit rollup `#{window_command_exit}` (e.g. the
worst/non-zero exit among the window's most-recently-finished commands — semantics
to be pinned; see risks). Mirror the `WINDOW_*`/`WINLINK_*` alert-flag machinery:
maintain the bit eagerly where `PANE_CMDRUNNING` is set/cleared, expose trivial
`format_cb_*` callbacks, alphabetized `format_table[]` rows, manpage entries next
to the existing `window_*_flag` / `pane_command_*` docs.
- **Pros:** eliminates the userspace `#{P:}` fold for every tmux user; matches an
  existing, recently-active precedent; nicm already floated the idea; smallest
  possible general surface.
- **Cons:** exit-status aggregation has no single obvious semantics (see §6);
  per-session vs per-window scoping must be decided; must wait for 3.8.

**(b) Document a `#{P:}` recipe in the manpage / FAQ — LOWER VALUE, optional
companion.**
Add a worked `window-status-format` example using `#{P:}` to roll pane command
state up to the window entry.
- **Pros:** zero risk, no C, useful immediately on 3.8.
- **Cons:** doesn't fix the gap, just documents the workaround; the `#{P:}` fold
  is fiddly (empty-until-first-`;D` `pane_command_status`, single-arg vs two-arg
  `#{P:}`, sentinel-char hazards — all catalogued in T1). Good as a *fallback* if
  (a) is rejected, or as a stepping-stone PR that demonstrates the need for (a).

**(c) A new `monitor-command` window option + `alert-command` hook — NOT
RECOMMENDED.**
Parallel to `monitor-silence`. nicm himself raised this ("monitor-command like
monitor-silence") but immediately doubted it ("a window-level feature not a
pane-level so might not work so well"). It also re-introduces a whole
option+hook+action subsystem for what a single aggregate format var + the
existing `set-hook -B -T` already covers. Heavier than warranted; skip.

**Recommendation:** pursue **(a)**, optionally opening with **(b)** as a
low-friction PR that surfaces the need and gives nicm the `#{P:}` recipe to react
to. Do **not** pursue (c).

---

## 5. Venue, precedent thread, and framing

- **Venue:** open a GitHub issue first (not a cold PR), referencing **#5237**
  (closed 2026-08-06, the thread where the 3.8 pane-level work landed and where
  nicm floated the window-level idea) and **#3064** (the OSC 133 origin). Frame it
  as the natural completion of the work he just did: "3.8 added per-pane
  `#{pane_command_*}`; there is no window-level rollup the way `window_*_flag`
  rolls up activity/bell/silence — here is the minimal mirror." Expect a
  hand-applied variant, not a merge.
- **Precedent to cite in the patch:** the `window_bell_flag` /
  `WINLINK_BELL` / `alerts.c` machinery (the aggregation pattern) and `bdd78ce`
  (parse-signal-into-format-var). Match `format.c` conventions exactly.
- **Draft problem statement (maintainer-framed, app-free):**
  > tmux 3.8 exposes per-pane command lifecycle via `#{pane_command_running}` /
  > `#{pane_command_status}`, but a status line renders one entry per window and
  > has no way to know whether *any* pane in a window is running a command — the
  > way `#{window_activity_flag}` / `#{window_bell_flag}` /
  > `#{window_silence_flag}` already aggregate per-pane monitor state to the
  > window. Users currently reconstruct this with a fragile `#{P:}` pane-loop.
  > Proposal: add `#{window_command_running}` (and an exit-status rollup),
  > maintained alongside `PANE_CMDRUNNING` in the same place the alert flags are
  > maintained, exposed via trivial `format_cb_*` callbacks — minimal, general,
  > zero-cost when unused, no new subsystem.

---

## 6. Risks / open questions to resolve BEFORE submitting

1. **Exit-status aggregation semantics.** `window_command_running` (boolean OR) is
   unambiguous; a window exit rollup is not. Options: "any non-zero among panes'
   last-finished commands," "most recent finish across panes," or expose only the
   boolean and leave exit to per-pane. Recommend shipping only the **boolean
   running aggregate** first (matches the alert-flag precedent — those are all
   booleans) and deferring any exit rollup; this also sidesteps nicm's "might not
   work so well" concern by keeping the semantics trivially defensible.
2. **Per-session (`winlink`) vs per-window (`window`) scope.** The alert flags
   maintain BOTH (`WINDOW_*` computed, `WINLINK_*` read by the format so it can
   clear per-session on view). A faithful patch must decide whether "command
   running" is a per-session clear-on-view concept (it probably is NOT — running
   is not an alert you dismiss) and likely only needs the `WINDOW_*` bit + a
   direct callback. Get this right or the patch reads as not-understanding the
   existing model.
3. **Timing gate.** 3.8 is unreleased (latest tag 3.7c). Submitting a window
   aggregate before the pane-level base ships is premature and invites "wait and
   see." Prepare now, submit after 3.8 tags.
4. **Value ceiling.** This saves a `#{P:}` fold; it does not unlock the
   impossible. Worth doing, but calibrate expectations — a polite "nice, applied"
   is the best-case outcome, and a "just use `#{P:}`" close is a plausible one.
   The `#{P:}` recipe (form b) is the graceful fallback either way.

---

## 7. Go/no-go — recommendation (Tim decides)

**Recommended: CONDITIONAL GO.**
- **GO** to treat the window-level aggregate as the one upstreamable kernel and to
  prepare the proposal (this assessment + a draft issue and, later, a `format.c`
  patch mirroring the alert-flag machinery), stripped of all Nix/agent/attention
  concepts.
- **GATE** the actual upstream submission on tmux **3.8 shipping** (build on the
  released pane-level vars first), and open with a GitHub issue referencing #5237,
  not a cold PR.
- **DESCOPE** everything else in Plan 050 (states/sources/channels/clearOnView,
  the shared lib, CC wiring, `attention`) as permanently downstream — none of it
  is upstream material, and confirming that is itself a useful T7 outcome: it lets
  T3-T6 proceed as pure nixcfg refactors without any "should this be upstream?"
  hesitation.

**Effect on Plan 050 T2 sign-off:** T7 finds **no generality refinement required
in the frozen T2 spec** for the downstream design — the spec is already correctly
scoped as a Nix abstraction over tmux primitives. The one refinement it surfaces
is a *forward-looking note*, not a schema change: when plan 051 wires
`backend="osc133"` on tmux ≥ 3.8, the per-pane source term should be the native
`#{pane_command_running}` / `#{pane_command_status}` (already the plan), and if
the upstream `#{window_command_running}` aggregate lands, the generated `#{P:}`
fold in T4 can collapse to that single native var — so **keep the aggregation
behind the shared-lib `mkFold` generator** (already the D2/T4 design) precisely so
that future swap is a one-line change. That is a vindication of the existing seam,
not a change to it.

**Alternatives if Tim prefers:**
- **Full GO now:** open the issue immediately against #5237 even pre-release.
  Downside: premature, likely "wait for 3.8."
- **NO-GO / defer indefinitely:** keep the `#{P:}` fold purely downstream, never
  propose upstream. Legitimate — the value is modest — but forgoes a genuinely
  in-scope contribution the maintainer has already signalled openness to.

---

## Appendix — provenance of upstream claims

All upstream facts above verified 2026-08-17 against tmux `master` @ `30abbe36`
(local clone + GitHub API), not from memory:
- Pane-level command vars/hooks present in `master`, absent in `3.7c`
  (`pane_command_running` appears 4× in `format.c@master`, 0× in `format.c@3.7c`).
- **No** `window_command_*` var in `master` (`grep 'window_command' format.c` →
  no matches) — the gap is confirmed.
- `input_osc_133()` in `input.c` handles A/B/C/D (+N/P/I); exit code via
  `input_osc_133_exit_status()`.
- Hooks registered in `options-table.c`; `set-hook -B -T` monitor in
  `cmd-set-option.c`.
- Window alert aggregates: `format_cb_window_bell_flag` reads
  `ft->wl->flags & WINLINK_BELL`; `WINDOW_*`/`WINLINK_*` bits in `tmux.h`,
  maintained in `alerts.c`.
- Issues #3064 (closed 2022-02-16), #5237 (closed 2026-08-06); nicm's
  "monitor-command ... a window-level feature ... might not work so well" remark
  is on #5237. Contribution flow (hand-apply-and-close): last-100-closed-PRs API
  sample, 7 merged.
