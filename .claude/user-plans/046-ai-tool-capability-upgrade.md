# Plan 046 — Max-out Claude Code & OpenCode in nixcfg (latest versions + full capability exposure)

Status: PENDING
Owner: Tim Black
Created: 2026-06-24
Burndown: SAFE
Working branch: plan-046-ai-tool-capability-upgrade

## Goal (CC-centric — decided 2026-06-24)

**Decision:** go **Claude-Code-centric**. Get the CodeCompanion-V2 (CCv2) / Bedrock workflow
working in Claude Code via the nixcfg wrappers, update CC to latest, and expose the full CC
capability surface. **OpenCode is deprioritized** — kept *dormant* in-repo (its module + pin are
NOT deleted), revisited only if a concrete reason returns (chiefly: needing non-Claude CCv2 models
that CC cannot reach — see "Non-Claude models (parked)" below).

1. **Update Claude Code to latest** (2.1.92 → 2.1.190+) with a sustainable pin.
2. **Expose everything CC supports** in the Nix module + wrappers — config, hooks, skills,
   commands, context files, MCP, models, gateway/auth.
3. **OpenCode:** no new investment this plan; existing module/pin left as-is (dormant).

## Why CC-centric — and what's parked

Evidence: `docs/claude-code-codecompanion-parity-verdict.md` + nixcfg-work
`modules/home-manager/tim-corp-personal.nix` (branch `feat/darwin-support`).

- **CC speaks ONLY the Anthropic Messages API** → natively runs **Claude/Anthropic models only**
  (direct, Bedrock, Vertex, Mantle, Foundry, or an Anthropic-compatible gateway).
- **Claude-on-Bedrock works in CC TODAY** — opus-4-6 / sonnet-4-6 / haiku-4-5 on the work Bedrock
  endpoint (`ai-platform-bedrockapis.d-dp.nextcloud.aero/api/v1`). This is the foundation the
  CC-centric setup builds on; it needs no probe.
- **Non-Claude models (parked):** `ai-proxy/Auto-MoM` (current default), Qwen ×5, Llama 4, GLM 5
  live on the OpenAI-style `/v1` CCv2 endpoint, which CC cannot call directly. Whether CC can use
  them hinges on whether CCv2 ALSO exposes an Anthropic-Messages endpoint — an **authenticated
  probe that is credential-blocked**: the CCv2 **V2** auth change invalidated old tokens (user must
  regenerate a unified token via the Azure AD dashboard). Until then ⇒ **USER_INPUT_REQUIRED**,
  NOT a blocker for the rest of the plan. Two outcomes when unblocked:
  - CCv2 accepts Anthropic format ⇒ curate those IDs into CC's picker (`availableModels` /
    `ANTHROPIC_CUSTOM_MODEL_OPTION`); CC-only with the full catalog.
  - CCv2 is OpenAI-only ⇒ non-Claude needs a translating gateway (LiteLLM) OR a brief OC revival
    for those. Decide then.
- **RTK-Tokensave** is a CC `PreToolUse` hook first (OC secondary) — integrated Nix-managed (T11).

Probe note (2026-06-24): unauthenticated probing is uninformative — `codecompanionv2…` 401s every
path behind a global auth wall (`server: uvicorn`). The decisive test (`POST /v1/messages` vs
`/v1/chat/completions` with a valid token) is recorded in the verdict doc + T15.

## Current state (from 2026-06-24 capability + coverage audit)

- **CC pin:** follows `nixpkgs` unstable (2.1.92). Overlay previously pinned a 2.1.97 npm build,
  now removed (`overlays/default.nix:24`). Latest upstream **2.1.190**.
- **OC pin:** custom package `pkgs/opencode-pinned/package.nix` at **1.14.48** (version line ~19,
  `sha256` ~25, node-modules hash ~78), wired via `overlays/default.nix:29`. Latest **1.17.9**.
- **CC module coverage ~95%**, **OC module coverage ~90%**. Concrete gaps enumerated per task.
- **Shared infra exists:** `modules/lib/shared/mcp-server-defs.nix` (canonical MCP defs +
  `toClaudeCodeFormat`/`toOpencodeFormat`), `modules/lib/shared/ai-instructions.nix`,
  `modules/lib/rbw.nix`, `modules/lib/nix-guarded.nix`. Skills/commands/context files are
  **NOT yet shared** — each tool generates its own.

## Authoritative capability references (read before the relevant task)

- CC: `https://code.claude.com/docs/llms.txt` (index) → settings, env-vars, hooks,
  slash-commands, sub-agents, skills, plugins-reference, statusline, model-config,
  amazon-bedrock, google-vertex-ai, llm-gateway, sandboxing, memory, keybindings; plus
  `https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md`.
- OC: `https://opencode.ai/docs/` (config, providers, agents, commands, mcp-servers, lsp,
  formatters, plugins, skills, rules, permissions, keybinds, themes, share, server) +
  `https://opencode.ai/config.json`, `https://opencode.ai/tui.json`,
  `https://github.com/sst/opencode/releases`.
- In-repo: `docs/ai-tool-feature-comparison.md` (stale: ~2026-04-09), the verdict doc,
  `docs/opencode-model-discovery.md`, archived plans `032-cc-oc-parity-gap-closure.md`,
  `037-opencode-model-discovery.md`.

## Progress table

| Task | Area | Status |
|---|---|---|
| T0 — Branch + escape-hatch audit | foundation | TASK:COMPLETE |
| T1 — Bump Claude Code to latest (pin strategy) | versions | TASK:COMPLETE |
| T2 — Bump OpenCode to latest | versions | TASK:DEFERRED (OC dormant) |
| T3 — Raw settings escape-hatch (CC done; OC optional/dormant) | foundation | TASK:COMPLETE |
| T4 — CC: model/provider/gateway/auth surface | claude-code | TASK:COMPLETE |
| T5 — CC: hooks entry-types + remaining events | claude-code | TASK:COMPLETE |
| T6 — CC: skills/commands/subagents/plugins frontmatter | claude-code | TASK:COMPLETE |
| T7 — CC: remaining settings + env (reliability, UX, statusline, keybindings, sandbox) | claude-code | TASK:COMPLETE |
| T8 — OC: new/changed top-level config keys | opencode | TASK:DEFERRED (OC dormant) |
| T9 — OC: file-based agents/commands/skills + permissions | opencode | TASK:DEFERRED (OC dormant) |
| T10 — OC: full TUI (keybinds/themes/scroll/attention) + plugins | opencode | TASK:DEFERRED (OC dormant) |
| T11 — RTK-Tokensave: Nix-managed hook (CC) | cross-cutting | TASK:PENDING |
| T12 — Shared skills/commands/context-file machinery | cross-cutting | TASK:DEFERRED (needs OC) |
| T13 — CC gateway model discovery in wrapper (Claude subset) | cross-cutting | TASK:PENDING |
| T14 — Docs refresh (comparison + verdict addendum) | docs | TASK:PENDING |
| T15 — CCv2 Anthropic-format probe (non-Claude models) | investigation | TASK:BLOCKED — USER_INPUT_REQUIRED (regen CCv2 token, then run probe) |

**Active (CC-centric) work:** T1, T3, T4, T5, T6, T7, T11, T13, T14. **Dormant (OC):** T2, T8,
T9, T10, T12 — revive only if T15 forces a non-Claude path. **Blocked:** T15 (credential-gated).

Dependency summary: T1→T4..T7 (CC features need the newer binary). T2→T8..T10 (OC features need
the newer binary). T3 is independent and unblocks "set anything" immediately. T11/T12/T13 depend
on the relevant module being on the new version. T14 depends on whatever shipped.

---

## T0 — Create branch; audit the "set anything" escape hatches `TASK:COMPLETE` (2026-06-24)

From `main`, create/switch to `plan-046-ai-tool-capability-upgrade`. Then read both modules'
settings/config builders and record whether a user can already set an ARBITRARY upstream key
without a module change (CC: is there a raw `settings`/`settingsExtra` deep-merge, or only
`experimental`? OC: is there a raw `opencode.json`/`tui.json` passthrough?). This determines how
much of T3 is genuinely new.

**DoD:** branch is checked out (`git branch --show-current` prints it) AND this T0 block is
updated with: (a) CC's current escape-hatch mechanism + file:line, (b) OC's, (c) a yes/no on
"can set an arbitrary key today." No code changes. `nix` missing ⇒ ENVIRONMENT_NOT_CAPABLE.

**Findings (2026-06-24):**
- Branch `plan-046-ai-tool-capability-upgrade` created from `main` and checked out.
- **(a) CC:** `settings.json` is built by `mkSettingsTemplate` (`claude-code.nix:684-800`) as a
  FIXED composition of known keys (`optionalAttrs` `//` merges). Freeform
  `(pkgs.formats.json {}).type` exists only on sub-trees: sandbox network/filesystem
  (`:348`, `:387`) and `experimental` (`:472`). The `experimental` key (`:756`) accepts arbitrary
  nested attrs but ONLY under `experimental`. There is **no top-level `settingsExtra` deep-merge.**
- **(b) OC:** `opencode.json` is built by `mkOpencodeConfig` (`opencode.nix:995-1101`), same
  fixed-composition pattern, ending at `:1101` with no trailing passthrough. Freeform only on
  `provider.options` (`:103`), `agent.options` (`:273`), provider `models` (`:789`). `tui.json` is
  built separately in `_hm/tui-json.nix`. There is **no top-level `settingsExtra`/`tuiExtra`.**
- **(c) Can set an arbitrary NEW top-level key today?** CC: **No** (only via `experimental`).
  OC: **No**. ⇒ **T3 is genuinely net-new for both** and is the cheapest "support everything"
  guarantee (covers future upstream keys without a module change).

> **DIRECTION CHANGE (2026-06-24, post-T0):** User has decided to go **Claude-Code-centric** —
> get the CCv2 features working in CC via the wrappers and **deprioritize OpenCode** (kept dormant,
> not deleted, revisit if a reason arises). This plan is being re-scoped accordingly: OC version
> bump (T2) and OC feature tasks (T8-T10) become DEFERRED; CC + wrapper + RTK + gateway tasks are
> elevated; a new decision/task covers how non-Claude CCv2 models (Auto-MoM/Qwen/Llama/GLM) are
> reached (CC speaks Anthropic Messages only — see the model-path decision in chat). Re-scope lands
> in the next edit once the model-path is chosen.

---

## T1 — Bump Claude Code to latest with a sustainable pin `TASK:COMPLETE` (2026-06-24)

**Done (2026-06-24):** flake nixpkgs is locked at `331800de`, which ships claude-code **2.1.158**
(NOT the live-channel 2.1.92). Vendored `pkgs/claude-code-pinned/` (byte-identical copy of the
nixpkgs derivation + `update.sh`; only `manifest.json` moves the version), pinned to **2.1.191**
(bucket `latest` on 2026-06-24). Wired via `overlays/default.nix` `claude-code = prev.callPackage
../pkgs/claude-code-pinned/package.nix { }`. **Verified:** `nix flake check --no-build` → all
checks passed; `nix build` of the pinned package → `claude-code-2.1.191` with `versionCheckHook`
green (runs `claude --version`). Bump path: edit `manifest.json` (or run `update.sh [version]`),
re-stage, rebuild. This unblocks T4-T7 (fallbackModel/Fable/availableModels/reliability all
postdate 2.1.158).

nixpkgs-unstable lags badly (2.1.92 vs 2.1.190), and target features need ≥2.1.129 (gateway
discovery), 2.1.166 (`fallbackModel`), 2.1.170 (Fable), 2.1.175 (`enforceAvailableModels`),
2.1.187 (org model restrictions). Add a **pin-ahead overlay** for `claude-code` (mirror the
existing OpenCode pin pattern in `overlays/default.nix` + `pkgs/`), tracking latest stable.
Document the version and how to bump (which hashes). Idempotent: if already pinned to ≥ target,
leave unchanged.

Files: `overlays/default.nix`, new `pkgs/claude-code-pinned/` (or equivalent), maybe `flake.nix`.

**DoD:** `nix flake check --no-build` passes AND
`nix eval --raw '.#...claude-code.version'` (or `nix run '.#...claude-code' -- --version`) reports
**≥ 2.1.190**. Pin mechanism + bump instructions recorded in this task block. If upstream tarball
hashes can't be resolved without network ⇒ ENVIRONMENT_NOT_CAPABLE (note it; don't fake hashes).

---

## T2 — Bump OpenCode pin to latest `TASK:PENDING`

Update `pkgs/opencode-pinned/package.nix`: `version` 1.14.48 → **1.17.9** (or newest), refresh
`src` `sha256` and the node-modules hash. Check the OC releases for config-schema breaking
changes between 1.14 and 1.17 (e.g. plural `agents/`/`commands/` dirs, `steps` vs `maxSteps`,
`share` vs `autoshare`) and note any that affect the module (handled in T8-T10). Idempotent.

Files: `pkgs/opencode-pinned/package.nix`, possibly `overlays/default.nix` comment.

**DoD:** `nix flake check --no-build` passes AND `nix run '.#...opencode' -- --version` reports
**≥ 1.17.9** AND breaking-schema notes recorded in this block. Hash resolution needs network ⇒
if unavailable, ENVIRONMENT_NOT_CAPABLE.

---

## T3 — Raw settings/config escape-hatch in both modules `TASK:PENDING`

Independent of T1/T2. Guarantee "fully support everything" even for keys the module doesn't model
explicitly: add a freeform deep-merge escape hatch to each module so any current/future upstream
key is settable from Nix.

- CC: `programs.claude-code.settingsExtra` (attrs) deep-merged LAST into the generated
  `settings.json` (and per-account variant). Precedence: explicit options < `settingsExtra`.
- OC: `programs.opencode.settingsExtra` (→ `opencode.json`) and `tuiExtra` (→ `tui.json`),
  deep-merged last.

Idempotent (skip if already present, per T0 findings).

Files: `modules/programs/claude-code/claude-code.nix`, `modules/programs/opencode/opencode.nix`
(+ `_hm/tui-json.nix`).

**DoD:** `nix flake check --no-build` passes AND a test eval setting an arbitrary unknown key via
`settingsExtra`/`tuiExtra` shows that key in the rendered JSON.

**Done — CC half (2026-06-24):** Added `programs.claude-code.settingsExtra`
(`(pkgs.formats.json {}).type`, default `{}`) and wrapped `mkSettingsTemplate`'s built attrset in
`lib.recursiveUpdate ( <built> ) cfg.settingsExtra` (claude-code.nix). **Semantic decision (supersedes
the earlier "explicit options win" wording): `settingsExtra` WINS on leaf conflicts** — it is a true
escape hatch, applied LAST, so any upstream key (incl. unmodeled/future ones) can be set OR
overridden from Nix; nested keys deep-merge. Verified: `nix-instantiate --parse` OK;
`recursiveUpdate` semantics proven (`{permissions={allow;}}` ⊕ `{spinnerTipsEnabled;permissions={deny;}}`
→ allow+deny+new key); commit pre-gate `nix flake check` passes (renders all accounts with the
default `{}` no-op merge wired in).
**OC half — DEFERRED (dormant):** `opencode.json settingsExtra` + `tui.json tuiExtra` not done; OC is
parked. Add only if OC is revived.

---

## T4 — Claude Code: model / provider / gateway / auth surface `TASK:COMPLETE` (2026-06-24)

**Done (2026-06-24):** env-var names verified against `code.claude.com/docs/en/model-config`
+ `microsoft-foundry` + `~/src/claude-code/CHANGELOG.md` before modeling. Added to
`modules/programs/claude-code/claude-code.nix`:
- **Global `programs.claude-code.models`** group: `fallback` (nullOr listOf str, ≤3, asserted)
  → settings.json `fallbackModel`; `available` (nullOr listOf str) → `availableModels`;
  `enforceAvailable` (nullOr bool) → `enforceAvailableModels`; `fable.{model,name,description,
  supports}` → env `ANTHROPIC_DEFAULT_FABLE_MODEL[_NAME|_DESCRIPTION|_SUPPORTS]` (note: the
  capability env var is `_SUPPORTS`, not `_CAPABILITIES`); `customOption` → env
  `ANTHROPIC_CUSTOM_MODEL_OPTION`. The model settings keys serialize flat at the top level of
  settings.json (added after `governanceJson`); the Fable/custom env (`modelGlobalEnv`) is folded
  into the settings `env` block AND every wrapper.
- **Per-account `accounts.<name>.provider`** submodule → documented env, emitted into BOTH the
  account's settings.json `env` block and its wrapper script (`providerEnv` helper):
  Bedrock (`CLAUDE_CODE_USE_BEDROCK`, `ANTHROPIC_BEDROCK_BASE_URL`, `CLAUDE_CODE_SKIP_BEDROCK_AUTH`,
  `ANTHROPIC_BEDROCK_SERVICE_TIER`), Vertex (`CLAUDE_CODE_USE_VERTEX`, `ANTHROPIC_VERTEX_BASE_URL`,
  `ANTHROPIC_VERTEX_PROJECT_ID`, `CLOUD_ML_REGION`), Mantle (`CLAUDE_CODE_USE_MANTLE`,
  `ANTHROPIC_BEDROCK_MANTLE_BASE_URL`), Foundry (`CLAUDE_CODE_USE_FOUNDRY`,
  `ANTHROPIC_FOUNDRY_RESOURCE`, `ANTHROPIC_FOUNDRY_BASE_URL`), `customHeaders` →
  `ANTHROPIC_CUSTOM_HEADERS`, plus a freeform `extraEnv` escape hatch for un-modeled provider env
  (Anthropic-on-AWS, `ANTHROPIC_FOUNDRY_API_KEY`, etc.). All defaults off/null — nothing emitted
  unless set. `_hm/lib.nix` needed no change: the merged env flows through its existing
  `extraEnvVars`→`extraEnvExports` path.
- **Assertion:** `models.fallback` length ≤ 3.

**Verified (eval, thinky-ubuntu via `extendModules`):** a config setting `models.fallback`
(list), `models.available`, `enforceAvailable`, Fable + customOption, and `accounts.max.provider`
{bedrock+vertex+customHeaders} rendered `fallbackModel`/`availableModels`/`enforceAvailableModels`
into BOTH accounts' settings.json; the Bedrock+Vertex+headers env appeared ONLY in `max`'s
settings `env` block and `max`'s `claudemax` wrapper script (the `pro` account carried none —
per-account isolation confirmed). `nix flake check --no-build` → all checks passed. This unblocks
T13 (gateway discovery builds on the model/provider surface).

Depends on: T1. Add the model/provider knobs the module lacks (audit gaps): `fallbackModel`
(ordered list, ≤3), `availableModels` + `enforceAvailableModels`, Fable family
(`ANTHROPIC_DEFAULT_FABLE_MODEL` + NAME/DESCRIPTION/CAPABILITIES) and `fable`/`best` aliases,
custom picker entry (`ANTHROPIC_CUSTOM_MODEL_OPTION`), and the full set of provider/auth env the
wrapper can emit per-account: Bedrock (`CLAUDE_CODE_USE_BEDROCK`, `ANTHROPIC_BEDROCK_BASE_URL`,
`CLAUDE_CODE_SKIP_BEDROCK_AUTH`, `ANTHROPIC_BEDROCK_SERVICE_TIER`), Vertex
(`CLAUDE_CODE_USE_VERTEX`, `ANTHROPIC_VERTEX_BASE_URL`, `ANTHROPIC_VERTEX_PROJECT_ID`,
`CLOUD_ML_REGION`), Mantle (`ANTHROPIC_BEDROCK_MANTLE_BASE_URL`, `CLAUDE_CODE_USE_MANTLE`),
Foundry, Anthropic-AWS, and `ANTHROPIC_CUSTOM_HEADERS`. (Gateway model *discovery* env is T13.)
Keep defaults null/empty; work layer supplies values. Idempotent edits.

Files: `modules/programs/claude-code/claude-code.nix`, `_hm/lib.nix` (wrapper env emission).

**DoD:** `nix flake check --no-build` passes AND `nix eval` type-checks a config that sets
`fallbackModel` (list), `availableModels`, and a Bedrock/Vertex auth block, AND those values
appear in the rendered settings.json / wrapper script (verify via eval). Depends-unmet (T1) ⇒
BLOCKED-BY-DEP.

---

## T5 — Claude Code: hooks entry-types + remaining events `TASK:COMPLETE` (2026-06-24)

**Done (2026-06-24):** event/entry/field names verified against `code.claude.com/docs/en/hooks`
(live, 2026-06-24) + `~/src/claude-code/CHANGELOG.md` before modeling. Changes:
- **Events** (`_hm/hooks.nix` `hookEvents`): added the 5 missing events
  `PostToolUseFailure`, `PostToolBatch`, `PermissionRequest`, `UserPromptExpansion`,
  `MessageDisplay`. (Full upstream list is 29; the rest were already present, incl. `SessionEnd`
  which the docs page omits but is real.)
- **Entry types + per-entry fields** (`mkHook`): rewrote the helper to emit any entry `type`
  (`command`/`http`/`mcp_tool`/`prompt`/`agent`) and the common per-entry fields. New params:
  `args`, `shell` (command); `url`/`headers`/`allowedEnvVars` (http); `server`/`tool`/`input`
  (mcp_tool); `prompt`/`model` (prompt+agent); `ifFilter`→`"if"`, `async`, `asyncRewake`, `once`,
  `statusMessage`. Each emitted only when set (optionalAttrs). `ifFilter` is renamed because `if`
  is a Nix keyword; it serializes to the JSON key `"if"`.
- **`hooks.custom` wired through** — it was defined but **never serialized** (dead option). Now
  concatenated into `_internal.hooks`. Being freeform `types.attrs`, a user can write any entry
  type/field directly (example added to the option).
- **Latent merge bug fixed (discovered during T5):** `_internal.hooks` is `types.attrs`, whose
  native merge is a right-biased `//` — so the old `mkMerge [...]` kept only the LAST contributor's
  list per event. Security's `PreToolUse` was silently clobbering development's; logging's
  `PostToolUse` clobbered the flake-check/auto-stage hooks. Replaced `mkMerge` with explicit
  `lib.zipAttrsWith (_: lib.concatLists)` over the category attrsets (+ `cfg.hooks.custom` last),
  converting list-embedded `mkIf` to `lib.optional`. Now every enabled category AND custom hooks
  coexist on the same event.
- **Gating settings** (`claude-code.nix` new `hookSettings` group, serialized flat top-level):
  `disableAllHooks` (nullOr bool) and `allowedHttpHookUrls` (nullOr listOf str). The plan's
  `httpHookAllowedEnvVars` is **NOT** a real top-level key — current docs show the per-entry
  `allowedEnvVars` field on http hooks (now supported via `mkHook`) is the documented mechanism;
  `allowManagedHooksOnly` already lives under `governance`. Noted, not invented.

**Verified (eval, tim@thinky-ubuntu via `extendModules`):** baseline `_internal.hooks` now has
`PreToolUse`=2 (development+security), `PostToolUse`=3 (flakeCheck+autoStage+logging),
`SessionStart`=1 (resume) — confirming the clobber fix. With a custom config defining an `http`
hook (`url`/`headers`/`allowedEnvVars`/`if`/`statusMessage`/`timeout`) and an `mcp_tool` hook
(`server`/`tool`/`input`/`if`) under one matcher, `PreToolUse` rendered 3 groups (2 categorized +
1 custom), entry types `[["command"],["command"],["http","mcp_tool"]]`, and `disableAllHooks`/
`allowedHttpHookUrls` serialized. `nix flake check --no-build` → all checks passed. Idempotent
(append-if-absent semantics; default `custom` = all-empty no-op).

Depends on: T1. `_hm/hooks.nix` already covers most EVENTS. Close the remaining gaps:
- Missing events: `PostToolUseFailure`, `PostToolBatch`, `PermissionRequest`, `MessageDisplay`,
  `UserPromptExpansion` (verify against current list; add any others).
- Hook ENTRY types beyond `command`: `http` (`url`/`headers`/`allowedEnvVars`), `mcp_tool`
  (`server`/`tool`/`input`), `prompt`, `agent` (`prompt`/`model`); plus per-entry fields `if`
  (permission-rule filter), `async`/`asyncRewake`, `once`, `timeout`, `statusMessage`.
- Gating settings: `disableAllHooks`, `allowedHttpHookUrls`, `httpHookAllowedEnvVars`.
Idempotent (append-if-absent in the hooks attrset).

Files: `modules/programs/claude-code/_hm/hooks.nix`, `claude-code.nix` (gating settings).

**DoD:** `nix flake check --no-build` passes AND the rendered settings.json can express an `http`
hook and a `mcp_tool` hook with an `if` filter (verify via eval of a config that defines them).
BLOCKED-BY-DEP if T1 unmet.

---

## T6 — Claude Code: skills/commands/subagents/plugins frontmatter `TASK:COMPLETE` (2026-06-24)

**Done (2026-06-24):** field names + casing verified against `code.claude.com/docs/en/skills`,
`/sub-agents`, `/settings`, `/plugin-marketplaces` (live, 2026-06-24) and `~/src/claude-code/`
CHANGELOG + plugin-dev reference skills before modeling. Changes:
- **Skill frontmatter** (`_hm/skills.nix`): extended the custom-skill submodule with the full
  documented SKILL.md frontmatter set — `whenToUse`→`when_to_use`, `argumentHint`→`argument-hint`,
  `arguments`, `allowedTools`→`allowed-tools`, `disallowedTools`→`disallowed-tools`, `model`,
  `disableModelInvocation`→`disable-model-invocation`, `userInvocable`→`user-invocable`, `effort`
  (enum low/medium/high/xhigh/max), `context` (enum `fork`), `agent`, `paths`, `shell` (enum
  bash/powershell), `hooks` (freeform attrs). Rewrote `mkSkillFile` with a generic YAML
  frontmatter builder (`mkFmValue`/`mkFrontmatter`): scalars inline, lists/attrs as JSON flow
  (valid YAML), nulls/`{}`/`[]` dropped so only set fields emit. Upstream merged custom slash
  commands INTO skills, so this single path covers command-style frontmatter too — the dead
  `_internal.slashCommandDefs` (never deployed, like pre-T5 `hooks.custom`) was left untouched
  rather than wired to a deprecated abstraction.
- **Subagent frontmatter** (`_hm/sub-agents.nix`): rewrote `mkSubAgent` to emit the full
  documented field set (from the JSON `--agents` form): `tools`/`disallowedTools` (comma-sep),
  `model`, `color` (enum), `permissionMode` (enum default/acceptEdits/auto/dontAsk/
  bypassPermissions/plan), `maxTurns`, `skills` + `mcpServers` + `hooks` (JSON flow), `memory`
  (enum user/project/local), `background`, `effort`, `isolation` (enum `worktree`),
  `initialPrompt`. Added matching options to the custom-subagent submodule. All new params default
  null/`{}`/`[]`; builtin agents (codeSearcher/memoryBank/architect) rely on defaults and emit
  unchanged frontmatter.
- **Plugin/skill settings** (`claude-code.nix`, new `plugins`/`skillSettings` groups, serialized
  FLAT top-level): `plugins.extraKnownMarketplaces` (freeform JSON, attrs keyed by marketplace
  name w/ a `source` object) → `extraKnownMarketplaces`; `skillSettings.disableBundled` →
  `disableBundledSkills`; `skillSettings.maxDescriptionChars` → `maxSkillDescriptionChars`;
  `skillSettings.listingBudgetFraction` → `skillListingBudgetFraction`. Managed `enabledPlugins`/
  `strictKnownMarketplaces` already live under `governance` (T-032) — NOT duplicated here. All
  default null → nothing emitted unless set.

**Verified (eval, tim@thinky-ubuntu via `extendModules` + building the writeText drvs out of the
activation string context):** a custom skill rendered `argument-hint`/`allowed-tools`/
`disallowed-tools`/`disable-model-invocation`/`user-invocable`/`context: fork`/`agent`/`paths`/
`shell`/`hooks`/`when_to_use` in SKILL.md; a custom subagent rendered `permissionMode: plan` +
`isolation: worktree` (plus memory/effort/background/maxTurns/skills/mcpServers); both accounts'
settings.json carried `extraKnownMarketplaces` + `disableBundledSkills`/`maxSkillDescriptionChars`/
`skillListingBudgetFraction`. `nix flake check --no-build` → all checks passed. Idempotent
(append-if-absent option additions; default no-op merges). Note: bare `argument-hint: [issue-number]`
is YAML-sequence syntax but CC coerces it to a string (CHANGELOG fix) and the upstream docs use the
same bare form, so it is the intended representation.

Depends on: T1. Upstream merged commands into skills and enriched frontmatter. Expose:
- Skill/command frontmatter: `argument-hint`, `arguments`, `allowed-tools`/`disallowed-tools`,
  `model`, `disable-model-invocation`, `user-invocable`, `effort`, `context` (`fork`), `agent`,
  `paths`, `shell`, `hooks`.
- Subagent frontmatter: `permissionMode`, `maxTurns`, `skills` (preload), `mcpServers` (ref or
  inline), `memory` (user/project/local), `background`, `effort`, `isolation: worktree`, `color`,
  `initialPrompt`, `disallowedTools`.
- Plugins: `enabledPlugins` (present in governance — verify), `extraKnownMarketplaces` (source
  shape), plugin `defaultEnabled`/`dependencies`, `disableBundledSkills`,
  `maxSkillDescriptionChars`, `skillListingBudgetFraction`.
Idempotent.

Files: `_hm/skills.nix`, `_hm/slash-commands.nix`, `_hm/sub-agents.nix`, `claude-code.nix`
(plugins/skills settings).

**DoD:** `nix flake check --no-build` passes AND an eval shows a custom skill emitting the new
frontmatter keys, a subagent emitting `permissionMode`/`isolation`, and `extraKnownMarketplaces`
in settings.json. BLOCKED-BY-DEP if T1 unmet.

---

## T7 — Claude Code: remaining settings + env (reliability, UX, statusline, keybindings, sandbox) `TASK:COMPLETE` (2026-06-24)

**Done (2026-06-24):** every key/env-var name verified against `code.claude.com/docs/en/`
{settings,sandboxing,statusline,keybindings} (live) + the raw upstream `CHANGELOG.md`
(github main) before modeling. Changes:
- **Reliability env + version floors** (`claude-code.nix` new `reliability` group): env →
  `CLAUDE_CODE_MAX_RETRIES` (typed `ints.between 0 15`, cap verified v2.1.186),
  `CLAUDE_CODE_RETRY_WATCHDOG`=1 (bool, v2.1.186), `CLAUDE_CODE_SAFE_MODE`=1 (bool, `--safe-mode`
  v2.1.169); settings.json flat keys → `autoUpdatesChannel` (enum stable/latest), `minimumVersion`,
  `requiredMinimumVersion`/`requiredMaximumVersion` (managed-only). The env vars are folded into a
  new global `reliabilityEnv` helper (mirrors `modelGlobalEnv`) → emitted into BOTH the settings
  `env` block AND every wrapper.
- **MCP runtime env** (new `mcpRuntime` group, also via `reliabilityEnv`): `MCP_TIMEOUT`,
  `MCP_TOOL_TIMEOUT`, `MAX_MCP_OUTPUT_TOKENS` (all ms/token ints), `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT`
  (ms, v2.1.187).
- **UX settings** (new `ux` group, flat top-level): `outputStyle` (str), `effortLevel`
  (enum low/medium/high/xhigh), `editorMode` (enum normal/vim — note Plan 032 recorded this as
  runtime-only on v2.1.91; upstream re-added the persistent setting, re-verified present 2026-06-24).
- **Sandbox additions** (extend existing `sandbox` block): `allowAppleEvents` (bool scalar, v2.1.181,
  macOS user/managed/CLI-only) into `sandboxBase`; `credentials` (freeform OBJECT, NOT a bool —
  `{ files=[{path;mode="deny";}]; envVars=[{name;mode="deny";}]; }`, v2.1.187) merged into
  `sandboxJson` when non-null.
- **Statusline** (`_hm/statusline.nix`): new `refreshInterval` (nullOr positive int, seconds,
  v2.1.97) + `padding` (int, default 0) options; `statusLine` now emits `padding = cfg.padding`
  and `refreshInterval` when set (was hardcoded `padding = 0`).
- **keybindings.json deployment**: new freeform `keybindings` option (shape
  `{ bindings = [ { context; bindings = { "<keys>" = "<action>"|null; } } ]; }`), rendered to a
  `claude-keybindings.json` writeText and `copy_template`d into each enabled account's config dir
  (= `CLAUDE_CONFIG_DIR`, where CC reads it) when non-null.
- **Attribution — NO-AI guarantee enforced**: new freeform `attribution` option (human-only bylines,
  default null/omitted) + `includeCoAuthoredBy` which **DEFAULTS TO `false` (the one intentional
  non-null default in the module)** so the generated settings.json **always** emits
  `includeCoAuthoredBy: false`, suppressing the "Co-Authored-By: Claude" trailer upstream adds by
  default. Verified the trailer is never emitted by default (see below).
- **OTEL/telemetry passthrough:** intentionally NOT re-modeled — `OTEL_*` /
  `CLAUDE_CODE_ENABLE_TELEMETRY` are already fully settable via the existing global
  `environmentVariables`, per-account `extraEnvVars`/`provider.extraEnv`, and the T3 `settingsExtra`
  escape hatch. Adding typed duplicates would be redundant.

**Verified (eval, real host `tim@pa161878-nixos` via nixcfg-work `--override-input` +
`extendModules`; settings/keybindings drvs pulled from the activation string context, then built):**
a T7 test config rendered into settings.json: all 7 reliability/MCP env vars in the `env` block,
`autoUpdatesChannel`/`minimumVersion`/`requiredMinimumVersion`/`requiredMaximumVersion`,
`outputStyle`/`effortLevel`/`editorMode`, `sandbox.allowAppleEvents=true` +
`sandbox.credentials.files`, `statusLine.refreshInterval=5`/`padding=1`, and `includeCoAuthoredBy:
false` with NO `attribution` key. keybindings.json rendered the `bindings` array verbatim. The
`claudemax` wrapper exported all 7 env vars. **Baseline (no T7 config) still emits
`includeCoAuthoredBy: false` and NO `attribution` key** — the no-AI-attribution guarantee holds by
default. `nix flake check --no-build` → all checks passed. Idempotent (append-only option additions;
all leaves default null except `includeCoAuthoredBy`=false; keybindings deploys only when set).

Files touched: `modules/programs/claude-code/claude-code.nix`,
`modules/programs/claude-code/_hm/statusline.nix`. (`_hm/lib.nix` needed no change — the merged env
flows through its existing `extraEnvVars`→`extraEnvExports` path.) This leaves T11, T13, T14 as the
remaining active CC-centric tasks.

Depends on: T1. Expose the remaining net-new knobs:
- Reliability/unattended (high value for burndown): `CLAUDE_CODE_MAX_RETRIES` (≤15),
  `CLAUDE_CODE_RETRY_WATCHDOG`, `--safe-mode`/`CLAUDE_CODE_SAFE_MODE`, `autoUpdatesChannel`,
  `minimumVersion`, `requiredMinimumVersion`/`requiredMaximumVersion`.
- Statusline: `refreshInterval`, `padding` (extend `_hm/statusline.nix`).
- Output styles (`outputStyle` + `.claude/output-styles/`), `effortLevel`/effort enum,
  `editorMode`, `tui` mode, `keybindings.json` deployment.
- Sandbox additions: `sandbox.credentials`, `sandbox.allowAppleEvents`.
- MCP: `MCP_TIMEOUT`, `MCP_TOOL_TIMEOUT`, `MAX_MCP_OUTPUT_TOKENS`,
  `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT`.
- Telemetry/OTEL passthrough, `attribution` (commit/pr/sessionUrl) — note: keep the
  **NO-AI-ATTRIBUTION** rule; default attribution to human-only, never add Co-Authored-By.
Idempotent.

Files: `claude-code.nix`, `_hm/statusline.nix`, `_hm/lib.nix`.

**DoD:** `nix flake check --no-build` passes AND eval shows `fallbackModel`-free reliability env
+ statusline `refreshInterval` + a `keybindings.json` artifact rendered. Confirm no AI-attribution
trailer is ever emitted by default. BLOCKED-BY-DEP if T1 unmet.

---

## T8 — OpenCode: new/changed top-level config keys `TASK:PENDING`

Depends on: T2. Add/verify the top-level keys not yet modeled (audit + 1.17 schema):
`small_model` (verify), `tool_output` (`max_lines`/`max_bytes`), `attachment.image.*`,
`compaction.tail_turns`/`preserve_recent_tokens`/`prune` (verify), `watcher.ignore` (verify),
`snapshot`, `autoupdate`, `logLevel`, `shell`, `tools` (global on/off), `references` (git/local),
`enterprise.url`, and `experimental.*` (`policies`, `primary_tools`, `batch_tool`,
`continue_loop_on_deny`, `mcp_timeout`, `openTelemetry`). Avoid deprecated keys
(`autoshare`→`share`, `mode`→`agent`, `maxSteps`→`steps`, `layout`, `reference`→`references`).
Idempotent.

Files: `modules/programs/opencode/opencode.nix`.

**DoD:** `nix flake check --no-build` passes AND eval shows the new keys serialized into
`opencode.json` for a config that sets them. BLOCKED-BY-DEP if T2 unmet.

---

## T9 — OpenCode: file-based agents/commands/skills + permissions `TASK:PENDING`

Depends on: T2. Ensure both inline-JSON AND file-based authoring are supported and write to the
**plural** dirs (`.opencode/agents/`, `.opencode/commands/`, `.opencode/skills/`). Add: agent
`top_p`/`steps`/`variant` (verify), the `scout` built-in awareness, `permission` keys incl.
`skill` (wildcards) and `doom_loop`/`external_directory` defaults, command `subtask`/`model`.
Skills `SKILL.md` frontmatter (`name`/`description`/`license`/`compatibility`/`metadata`).
Idempotent.

Files: `opencode.nix`, `_hm/agent-files.nix`, `_hm/file-commands.nix`, `_hm/skills.nix`.

**DoD:** `nix flake check --no-build` passes AND eval renders a file-based agent + command +
skill into the correct plural dirs AND a `permission.skill` rule into `opencode.json`.
BLOCKED-BY-DEP if T2 unmet.

---

## T10 — OpenCode: full TUI + plugins `TASK:PENDING`

Depends on: T2. Extend `_hm/tui-json.nix` to the full `tui.json` surface: `theme` (incl. custom
theme JSON files under `themes/`), `keybinds` (all categories; leader/chord/object forms,
disable via `"none"`), `leader_timeout`, `scroll_speed`, `scroll_acceleration`, `diff_style`,
`mouse`, `attention` (`enabled`/`notifications`/`sound`/`volume`). Plugins: `plugin` array (npm
names + local `file://`), and the project/global plugin dirs. Idempotent.

Files: `modules/programs/opencode/_hm/tui-json.nix`, `opencode.nix` (plugin).

**DoD:** `nix flake check --no-build` passes AND eval renders a custom theme + a keybind override
+ an `attention` block into `tui.json`, and a plugin entry into `opencode.json`.
BLOCKED-BY-DEP if T2 unmet.

---

## T11 — RTK-Tokensave: Nix-managed hook (CC) + plugin (OC) `TASK:PENDING`

Depends on: T1 (CC side), T2 (OC side) for the respective halves; otherwise independent.
Integrate PAC `rtk` declaratively — never run `rtk init -g` imperatively (it clobbers
`~/.claude/settings.json`/`CLAUDE.md`, assumes `~/.claude`, conflicts with our
`CLAUDE_CONFIG_DIR`). 
- CC: add a `PreToolUse` matcher `Bash` → `rtk hook claude` hook (gated by an enable flag,
  default off; on for the `work` account). Deploy `RTK.md` into the Nix-managed config dir.
- OC: add an `rtk`-rewriting plugin via the `tool.execute.before` hook (OC's plugin event), gated
  the same way. (`rtk init -g --opencode` documents the intended behavior.)
- Package the `rtk` binary OR make the hook degrade gracefully to a pass-through no-op when `rtk`
  is absent (must never block a Bash/tool call). Document which path was taken.
Idempotent (append-if-absent).

Files: `_hm/hooks.nix` (+ enable option), maybe `pkgs/` (rtk), OC plugin wiring; PATH wiring in
both wrappers.

**DoD:** `nix flake check --no-build` passes AND (CC) rendered settings.json with the flag on
contains a `PreToolUse` `Bash` hook calling `rtk hook claude`, AND (OC) the plugin/hook is wired,
AND with `rtk` absent both are pass-throughs (demonstrate the guard). Cloning the real `rtk` repo
to confirm the exact contract needs GitLab auth ⇒ if unavailable, implement against the documented
contract in `docs/claude-code-codecompanion-parity-verdict.md` and mark repo-verification
USER_INPUT_REQUIRED (never guess credentials).

---

## T12 — Shared skills/commands/context-file machinery `TASK:PENDING`

Depends on: T6 (CC skills/commands shape) and T9 (OC shape). Today skills, commands, and context
files are generated separately per tool. Build/extend shared lib (alongside
`modules/lib/shared/mcp-server-defs.nix`) so a skill/command/context-file is **defined once and
deployed to BOTH tools** where formats are compatible:
- Skills: `SKILL.md` is the same agentskills.io standard in both ⇒ one definition → CC
  `skills/` + OC `skills/` (and `.claude/skills` compat).
- Commands: shared definition → CC command/skill frontmatter + OC command frontmatter
  (map fields; note CC merged commands into skills).
- Context files: one canonical source → CC `CLAUDE.md` and OC `AGENTS.md` (OC also reads
  `CLAUDE.md` as fallback — exploit that to avoid duplication where possible).
Provide `toClaudeCode*`/`toOpencode*` transformers mirroring the MCP pattern. Idempotent.

Files: new `modules/lib/shared/ai-skills.nix` / `ai-commands.nix` (or extend
`ai-instructions.nix`); rewire `claude-code/_hm/{skills,slash-commands}.nix` and
`opencode/_hm/{skills,file-commands,agent-files}.nix` to consume shared defs.

**DoD:** `nix flake check --no-build` passes AND a single shared skill + shared command defined
once renders into BOTH tools' config dirs (verify via eval of both modules) with no duplicated
source. Existing per-tool custom skills/commands still work (back-compat).

---

## T13 — Claude Code gateway model discovery in the wrapper `TASK:PENDING`

Depends on: T1, T4. CC now supports native gateway discovery
(`CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1`, ≥2.1.129; queries `/v1/models`, caches to
`~/.claude/cache/gateway-models.json`, **filters to `claude`/`anthropic` IDs only**). Wire an
opt-in per-account `discovery.enable` flag in the CC wrapper that exports this env (and, where
needed, seeds `availableModels` from the cache) — mirroring the OC discovery pattern in
`opencode/_hm/model-discovery.nix`. Note in docs: this surfaces only the Claude subset of your
CCv2/Bedrock catalog (by design); non-Claude models remain OC-only. Default off; idempotent.

Files: `modules/programs/claude-code/_hm/lib.nix`, `claude-code.nix` (discovery submodule).

**DoD:** `nix flake check --no-build` passes AND a generated `claudework` wrapper with the flag on
exports `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1` (verify via wrapper-text eval); with the
flag off the wrapper is unchanged for that account. BLOCKED-BY-DEP if T1/T4 unmet.

---

## T14 — Docs refresh `TASK:PENDING`

Depends on: whatever shipped (T1-T13). Update `docs/ai-tool-feature-comparison.md` to reflect the
new tool versions and the now-exposed Nix options (flip the relevant rows; note last-refreshed
date). Add an implementation-status addendum to
`docs/claude-code-codecompanion-parity-verdict.md` capturing the final hybrid model (OC primary
for non-Claude/Auto-MoM/Qwen/Llama/GLM; CC secondary for Claude + richer harness + RTK) and the
pin strategy. No new top-level doc unless necessary; ask where ambiguous.

**DoD:** `docs/ai-tool-feature-comparison.md` mentions CC 2.1.190 / OC 1.17.9 and the new options
(grep confirms), AND the verdict doc has a dated "Status: implemented" addendum. `nix flake check
--no-build` still passes.

---

## T15 — CCv2 Anthropic-format probe (non-Claude models) `TASK:BLOCKED — USER_INPUT_REQUIRED`

Determines whether CC can use the non-Claude CCv2 catalog (`Auto-MoM`, Qwen, Llama 4, GLM 5).
**Blocked on credentials:** the CCv2 V2 auth change invalidated old tokens; user must regenerate a
unified token via the Azure AD dashboard (`codecompanion.d-dp.nextcloud.aero/dashboard` → Code
Companion V2 → Generate token). Do NOT attempt to work around auth (CLAUDE.md rule).

When unblocked, run (token stays local; `!`-runnable):
`TOKEN=$(rbw get --field "Bedrock API Key" "PAC Code Companion v2"); H=https://codecompanionv2.d-dp.nextcloud.aero;`
then probe `GET /v1/models`, `POST /v1/messages` (with `anthropic-version: 2023-06-01`), and
`POST /v1/chat/completions`.

**Interpretation / DoD:** record the three HTTP codes in this block.
- `POST /v1/messages -> 200` ⇒ CC can use the full catalog. Follow-up: curate non-Claude IDs into
  CC via `availableModels` / `ANTHROPIC_CUSTOM_MODEL_OPTION` (CC's native discovery filters to
  `claude`/`anthropic` IDs, so non-Claude must be added manually). CC-only achievable.
- `/v1/messages -> 404/405` but `/v1/chat/completions -> 200` ⇒ CCv2 is OpenAI-only; non-Claude in
  CC needs a translating gateway (LiteLLM) OR a brief OC revival ⇒ escalate to user (decision).
- `/v1/messages -> 400/422` ⇒ endpoint exists, body wrong ⇒ refine probe, not a dead end.

This task NEVER blocks the CC-centric build (T1/T3-T7/T11/T13). It only decides the non-Claude
branch. Until the token is regenerated, leave BLOCKED.

**Findings (fill in when unblocked):** _TBD_

## Notes for the executor

- **No-workaround rule:** unmet prerequisite ⇒ emit the proper sentinel (BLOCKED-BY-DEP /
  ENVIRONMENT_NOT_CAPABLE / USER_INPUT_REQUIRED). A prerequisite that should have been a declared
  dependency is an authoring bug — surface it; don't guess.
- **Auth:** GitLab (`git.panasonic.aero`) cloning of the `rtk` repo, or any Bitwarden/SOPS/SSH
  step ⇒ USER_INPUT_REQUIRED. Never guess credentials (CLAUDE.md auth rule).
- **AI attribution:** NEVER emit `Co-Authored-By`/AI markers in commits/PRs (T7's `attribution`
  defaults to human-only).
- **Nix hygiene:** single-quote derivation refs in zsh (`nix build '.#x'`); stage before nix;
  serialize nix invocations (no concurrent evals); `nix flake check --no-build` for fast eval.
- **Deployment:** this plan changes nixcfg only. The work host (and CCv2/Bedrock values) pick it
  up via a **nixcfg-work** flake.lock bump + `home-manager switch` — same path as prior features.
- **OC stays primary** throughout; nothing here moves the daily driver off OpenCode.
