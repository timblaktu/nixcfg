# Plan 032: Claude Code ↔ OpenCode Nix Module Parity Gap Closure

## Context

Plan 031 (commit `0e83352`) claimed to establish CC↔OC parity, but its comparison
document was built by recall and missed ~30 features — most notably vim/editor mode and
OpenCode's entire `tui.json` second config file. The audit pass on 2026-04-06 rewrote
`docs/ai-tool-feature-comparison.md` from authoritative schema sources and produced
three gap tables (CC, OC, asymmetries) that drive this plan.

This plan executes those gap tables. **Read `docs/ai-tool-feature-comparison.md` §7
before starting any task.** Each task ID below maps directly to a gap row.

## Sources of truth

| Tool | Path | What lives there |
|------|------|------------------|
| OpenCode master schema | `~/src/opencode/packages/opencode/src/config/config.ts:849-1044` | every `opencode.json` field |
| OpenCode TUI schema | `~/src/opencode/packages/opencode/src/config/tui-schema.ts` + `config.ts:610-765` | every `tui.json` field + ~110 keybinds |
| Claude Code examples | `~/src/claude-code/examples/settings/*.json` | example settings.json shapes |
| Claude Code CHANGELOG | `~/src/claude-code/CHANGELOG.md` | new keys per version |
| Claude Code hooks | `~/src/claude-code/plugins/plugin-dev/skills/hook-development/` | hook event types |
| Comparison doc | `docs/ai-tool-feature-comparison.md` | per-feature table with citations |
| CC Nix module | `modules/programs/claude-code/{claude-code.nix,_hm/}` | current CC option surface |
| OC Nix module | `modules/programs/opencode/{opencode.nix,_hm/}` | current OC option surface |

## Methodology rule

**Every task in this plan must verify the upstream schema before implementing.** A task
that adds Nix options for `sandbox.network.allowedDomains` must first re-read
`examples/settings/settings-bash-sandbox.json` (or the cited CHANGELOG entry) to confirm
the field name and shape. Do not work from this plan's tables alone — they are a map,
not a substitute for the source.

## Prioritization

- **P0 (correctness)**: Tasks that fix Plan 031 misclassifications (e.g., OC tui options
  written to wrong file).
- **P1 (security/governance)**: CC sandbox + governance features (CC-G1 through G7).
- **P2 (functionality)**: OC tui.json file + keybinds (OC-G1, OC-G6).
- **P3 (per-feature parity)**: Remaining individual gaps.
- **P4 (documentation)**: Items that cannot be exposed (CC-G18 vim mode) — document
  the limitation in module README.

## Tasks

### T0 — Hygiene check (always run first)

**Goal**: Re-verify the comparison doc against current upstream HEADs before any module
work. Both `~/src/opencode` and `~/src/claude-code` may have moved.

**Steps**:
1. `git -C ~/src/opencode pull && git -C ~/src/claude-code pull`
2. Compare new HEAD commits to those recorded in `docs/ai-tool-feature-comparison.md` §1.
3. For any diff in `config.ts`, `tui-schema.ts`, `examples/settings/`, or `CHANGELOG.md`,
   update §2-§5 of the comparison doc.
4. Re-run the canary check (vim mode in §5).

**DoD**: Comparison doc commit SHAs in §1 match current upstream HEADs; canary still
passes; any new keys added to the field-enumeration tables.

---

### T1 (P0) — Verify OC `tui.*` option destinations — **COMPLETE (2026-04-08, commit b67d2b6)**

**Goal**: The current OC module exposes `tui.scrollSpeed`, `tui.scrollAcceleration`,
`tui.theme`, `tui.diffStyle`. Per `tui-schema.ts`, these belong in `tui.json`, not
`opencode.json`. Verify which file they currently land in.

**Steps**:
1. Read `modules/programs/opencode/opencode.nix` — find where the JSON is written.
2. If options are written to `opencode.json`, this is **wrong** (OC ignores them there).
3. Build a test home configuration and inspect the generated files at
   `claude-runtime/.claude-default/.config/opencode/{opencode,tui}.json` (or wherever
   the module places them).
4. If misplaced, file is moved as part of T2.

**DoD**: Confirmed (with cited file:line and a generated-output snippet) which file
each option currently writes to. Findings recorded in plan as a comment.

**T1 FINDINGS (2026-04-08)**: **Bug confirmed, worse than anticipated.**

- `modules/programs/opencode/opencode.nix:557-564` writes `tui = { scroll_speed,
  scroll_acceleration: { enabled }, diff_style }` as a nested key **inside
  `opencode.json`**. Line 557 also writes top-level `theme` into `opencode.json`
  when `cfg.tui.theme != null`.
- Upstream `~/src/opencode/packages/opencode/src/config/tui-migrate.ts` runs
  `migrateTuiConfig` on every opencode startup. It detects `theme`, `keybinds`,
  `tui` keys in `opencode.json`, extracts them, writes `tui.json` **only if
  `tui.json` does not already exist** (line 63-64: `if (targetExists) continue`),
  then strips those keys from `opencode.json` and writes a `.tui-migration.bak`
  backup.
- Interaction with our activation script (`opencode.nix:716-747`): the activation
  script does `rm -f "$target" && cp "$template" "$target"` for `opencode.json`
  every HM switch. Result:
  1. First HM switch → opencode.json contains tui keys → user runs opencode →
     migration creates tui.json from current nix values → strips tui keys from
     opencode.json.
  2. User changes `programs.opencode.tui.theme` in nix → HM switch → activation
     overwrites opencode.json with new tui keys → tui.json still exists from
     step 1 → user runs opencode → migration re-triggers → sees tui.json already
     exists → `continue`s WITHOUT updating tui.json → strips tui keys from
     opencode.json. **The new nix value is silently lost.**
- **Bug 2** (discovered during T1): `opencode.nix:373` declares
  `diffStyle` enum `[ "auto" "unified" "side-by-side" ]`. Upstream
  `tui-schema.ts:22` accepts only `[ "auto" "stacked" ]`. Setting `unified` or
  `side-by-side` in nix produces a value that upstream's `.strict()` zod schema
  rejects → silently ignored even if it reached `tui.json`.
- **Bug 3** (discovered during T1): tui module does not handle `keybinds`,
  `plugin`, `plugin_enabled` at all — those upstream fields are completely
  unreachable via nix today.

**Conclusion**: T2 must (a) stop writing tui keys to opencode.json, (b) write
tui.json directly via activation script (same rm/cp pattern as opencode.json),
(c) fix the diffStyle enum, (d) add missing fields. Keeping the migration path
alive is actively harmful — we must bypass it by generating tui.json ourselves
and keeping tui keys out of opencode.json.

---

### T2 (P0/P2) — Add OC `tui.json` deployment sub-module — **COMPLETE (2026-04-08, commit b67d2b6)**

**Implementation notes (2026-04-08)**:
- Sub-module at `modules/programs/opencode/_hm/tui-json.nix` imported from
  `opencode.nix`. Owns all `programs.opencode.tui.*` options (moved from
  opencode.nix); writes `tui.json` via its own activation block ordered
  `entryAfter [ "opencodeConfigTemplates" ]`.
- Option defaults are all `null` / `{}` / `[]` so we only emit keys the user
  sets, leaving upstream defaults in place. A `hasTuiContent` gate skips the
  activation block entirely when nothing is customized (avoids writing an
  almost-empty tui.json).
- `diffStyle` enum corrected to `[ "auto" "stacked" ]` (previously
  `[ "auto" "unified" "side-by-side" ]` which upstream .strict() zod schema
  silently rejected).
- Added: `tui.keybinds` (`attrsOf str`, freeform — upstream validates key
  names against `Config.Keybinds.shape`, ~110 bindings), `tui.plugins`
  (`listOf str`), `tui.pluginEnabled` (`attrsOf bool`).
- **vimPreset NOT implemented** — reading `config.ts:610-765` closely,
  upstream keybinds are for TUI actions (session/messages/model/agent
  navigation), not text-editor modal behavior. There is no meaningful vim
  editor mode to preset; Plan 031's framing was inaccurate. The `keybinds`
  option is sufficient for users who want custom bindings. A vim-flavored
  preset could still be layered on later as an opt-in if a compelling use
  case emerges.
- tui keys are no longer written to opencode.json (removed the `tui = {...}`
  and `theme` blocks from `mkOpencodeConfig`). Activation also cleans up any
  stale `opencode.json.tui-migration.bak` left by prior upstream migrations.

**Validation**: `nix flake check --no-build` passed; `home-manager switch
--flake '.#tim@pa161878-nixos' --dry-run` passed (opencodeTuiJson block
correctly gated off since pa161878-nixos does not currently set any tui
options). Plan 032 OC-G1, OC-G6 closed.

---

**Original task spec (for reference)**:

### T2 spec — Add OC `tui.json` deployment sub-module

**Goal**: Create `modules/programs/opencode/_hm/tui-json.nix` that writes a complete
`tui.json` file to `$OPENCODE_CONFIG_DIR/tui.json` (or the project equivalent).

**Scope**:
- New options module: `programs.opencode.tui.{theme,scrollSpeed,scrollAcceleration,diffStyle,plugins,pluginEnabled}`
- New nested options module for keybinds: `programs.opencode.tui.keybinds.<binding>` for
  each of the ~110 bindings in `config.ts:610-765`. Use a single `submodule` with
  `freeformType = lib.types.attrsOf lib.types.str` so users can set arbitrary bindings
  without us hand-listing all 110.
- A `vimPreset` convenience option (`programs.opencode.tui.vimPreset.enable`) that
  pre-fills keybinds with vim-style defaults. This is the primary user-visible response
  to Plan 031's vim oversight.
- Wire into `opencode.nix` so `tui.json` is materialized via `home.file` /
  `xdg.configFile`.

**Migration**: Move the four existing `tui.*` options from `opencode.nix` into the new
sub-module so that they land in `tui.json` not `opencode.json` (T1 will determine if a
migration warning is needed).

**DoD**:
- `tui.json` is written with correct content for at least one host config
- Round-trip test: option set in nix → field appears in generated `tui.json` with right
  shape (verify against `tui-schema.ts`)
- `nix flake check --no-build` passes
- Comparison doc §6.7 / §7.2 OC-G1, OC-G6 marked closed

---

### T3 (P1) — CC sandbox option surface — COMPLETE (2026-04-08)

**Implementation**: Added `programs.claudeCode.sandbox.*` option tree in
`modules/programs/claude-code/claude-code.nix` covering all §2.2 keys:
`enabled`, `failIfUnavailable`, `autoAllowBashIfSandboxed`,
`allowUnsandboxedCommands`, `excludedCommands`, `enableWeakerNestedSandbox`,
`enableWeakerNetworkIsolation`, plus `network.{allowUnixSockets,
allowAllUnixSockets, allowLocalBinding, allowedDomains, httpProxyPort,
socksProxyPort}` and `filesystem.{allowWrite, denyRead, allowRead}`. All leaves
default to null; nested `network` and `filesystem` use freeform submodules
(`(pkgs.formats.json {}).type`) for forward-compat. Serialization in
`mkSettingsTemplate` strips nulls via a local `stripNulls` helper and only emits
`sandbox = ...` when at least one leaf is set. Verified against
`~/src/claude-code/examples/settings/settings-bash-sandbox.json`. Pre-commit
auto-reformatted; `nix flake check --no-build` passed.

**Gaps**: CC-G1 (entire `sandbox.*` subtree).

**Scope**: Add `programs.claudeCode.sandbox.*` option group covering every key in
comparison doc §2.2. Use a submodule with `freeformType` for `sandbox.network` and
`sandbox.filesystem` to allow forward-compat. Render into `settings.json` via the
existing JSON writer.

**DoD**: All §2.2 keys exposable as nix options; one example host enables sandbox via
nix and the resulting `settings.json` validates against
`examples/settings/settings-bash-sandbox.json`.

---

### T4 (P1) — CC governance options — COMPLETE (2026-04-08)

**Implementation notes (2026-04-08)**: Added 10 nullable options:
- `permissions.disableBypassPermissionsMode` (CC-G2) — `nullOr str`, serializes
  inside `permissions` block. Upstream value is `"disable"` (string, not bool);
  typed as `str` for forward-compat with future enum values.
- `governance.{allowManagedPermissionRulesOnly, allowManagedHooksOnly}` (CC-G3) —
  `nullOr bool`.
- `governance.{allowedMcpServers, deniedMcpServers}` (CC-G4) —
  `nullOr (listOf str)`.
- `governance.strictKnownMarketplaces` (CC-G5) — `nullOr jsonType` (freeform, upstream
  accepts list of `{hostPattern, pathPattern}` objects).
- `governance.{allowedChannelPlugins}` (CC-G6) — `nullOr (listOf str)`.
- `governance.{enabledPlugins}` (CC-G6) — `nullOr jsonType` (freeform).
- `governance.pluginTrustMessage` (CC-G7) — `nullOr str`.
- `governance.forceRemoteSettingsRefresh` (CC-G7) — `nullOr bool`.

All governance keys serialize flat at top level of settings.json (not nested under
"governance") matching upstream schema. The nix-side `governance.*` grouping is
for ergonomics only. Keys verified against `~/src/claude-code/examples/settings/
settings-strict.json` + CHANGELOG entries.

`nix flake check --no-build` passed. CC-G2..CC-G7 closed.

**Gaps**: CC-G2, CC-G3, CC-G4, CC-G5, CC-G6, CC-G7.

**Original scope**: Add the following top-level options under `programs.claudeCode`:
- `permissions.disableBypassPermissionsMode`
- `governance.allowManagedPermissionRulesOnly`
- `governance.allowManagedHooksOnly`
- `governance.allowedMcpServers` / `deniedMcpServers`
- `governance.strictKnownMarketplaces`
- `governance.allowedChannelPlugins`
- `governance.enabledPlugins`
- `governance.pluginTrustMessage`
- `governance.forceRemoteSettingsRefresh`

**DoD**: Options serialize to expected `settings.json` keys; documented in module README;
strict-mode example host built and dry-run-validated.

---

### T5 (P1) — CC security hardening + UX options — **COMPLETE (2026-04-08)**

**Implementation notes (2026-04-08)**: Added 7 nullable scalar options under
`programs.claudeCode` (the existing module name is `programs.claude-code`):
- `voice.enable` → `voiceEnabled`
- `voice.language` → `language`
- `display.showThinkingSummaries` → `showThinkingSummaries`
- `cleanupPeriodDays` → `cleanupPeriodDays` (positive int)
- `security.disableSkillShellExecution` → `disableSkillShellExecution`
- `security.disableDeepLinkRegistration` → `disableDeepLinkRegistration`
- `prompt.includeGitInstructions` → `includeGitInstructions`

All defaults are `null`; serialization in `mkSettingsTemplate` only emits keys
the user actually sets, leaving upstream defaults in place. Keys verified
against `~/src/claude-code/CHANGELOG.md` (every key matched a recorded entry).
Settings written to `settings.json` template only — `.claude.json` runtime
state file does not need merging since the wrapper passes
`--settings=$accountDir/settings.json` directly.

`nix flake check --no-build` passed. Comparison doc CC-G8..CC-G13 closed.

---

### T5 spec — CC security hardening + UX options

**Gaps**: CC-G8, CC-G9, CC-G10, CC-G11, CC-G12, CC-G13.

**Scope**: Add scalar options:
- `voice.enable` (→ `voiceEnabled`)
- `voice.language` (→ `language`)
- `display.showThinkingSummaries`
- `cleanupPeriodDays`
- `security.disableSkillShellExecution`
- `security.disableDeepLinkRegistration`
- `prompt.includeGitInstructions`

**DoD**: All options serialize; one host sets each; flake check passes.

---

### T6 (P1) — CC apiKeyHelper + worktree + modelOverrides — COMPLETE (2026-04-09)

**Implementation notes (2026-04-09)**: Added 3 nullable options under
`programs.claude-code` closing CC-G14, CC-G15, CC-G16:
- `apiKeyHelper` — `nullOr str`, script path for dynamic API key generation
  (5-min TTL, prints key on stdout). Serializes as top-level `apiKeyHelper`.
- `worktree.sparsePaths` — `nullOr (listOf str)`, directories for sparse-checkout
  in `claude --worktree`. Serializes as `worktree.sparsePaths` (nested object).
- `modelOverrides` — `nullOr (attrsOf str)`, maps model picker names to custom
  provider model IDs (e.g. Bedrock ARNs). Serializes as top-level `modelOverrides`.

All default to null; only emitted when set. Keys verified against
`~/src/claude-code/CHANGELOG.md`. `nix flake check --no-build` passed (exit 0).
Commit `952624e`.

**Gaps**: CC-G14, CC-G15, CC-G16.

**Original scope**:
- `apiKeyHelper`: option taking a script path (or a derivation that produces one). Note
  in module docs that the contract is undocumented upstream — users must provide a
  script that prints an API key on stdout.
- `worktree.sparsePaths`: list of strings.
- `modelOverrides`: free-form attrset (`attrsOf str`).

**DoD**: Options serialize; integration with rbw/secret loading documented; flake check.

---

### T7 (P1) — CC hook event coverage audit — COMPLETE (2026-04-09, commit 24ed850)

**Gap**: CC-G17.

**Implementation notes (2026-04-09)**: Rather than adding 25 individual category
options (most events don't warrant opinionated Nix wrappers), took a structural
approach:

- Defined canonical `hookEvents` list (25 events) in `_hm/hooks.nix` as single
  source of truth. The `custom` option default, base merge structure, and hasHooks
  gate all derive from this list.
- Updated `hooks.custom` default from 4 hardcoded keys to `genAttrs hookEvents`,
  giving users discoverability of all event slots.
- **Fixed bug**: `hasHooks` gate in `claude-code.nix:695-696` only checked 4 events
  with a typo (`Start` instead of `SessionStart`). Replaced with generic
  `filterAttrs` that removes null and empty-list slots, then checks `!= {}`.
- Updated comparison doc §2.3 with 5 events found in CHANGELOG but missing from
  prior audit: `ConfigChange`, `SubagentStart`, `TaskCompleted`, `TeammateIdle`,
  `Setup`.
- Existing categorized hooks (formatting, security, logging, development, git,
  testing, notifications) remain unchanged — they're workflow-oriented composites
  of `PreToolUse`/`PostToolUse`/`SessionStart`/`Stop`.

Validated: `nix flake check --no-build` passed; `home-manager switch --dry-run`
passed. CC-G17 closed.

**Original scope**: Walk every hook event listed in comparison doc §2.3 and verify
`modules/programs/claude-code/_hm/hooks.nix` exposes a category for each.

**DoD**: Every event in §2.3 has a corresponding option path; tested by setting one hook
of each new event type and verifying generated JSON.

---

### T8 (P4) — Document CC editor-mode limitation — **COMPLETE (2026-04-08)**

Added a "Known upstream limitations" block to the header comment of
`modules/programs/claude-code/claude-code.nix` noting that editor / vim mode
cannot be set via `settings.json` (upstream removed the persistent setting in
v2.1.91; runtime `/config` toggle only). Cross-references comparison doc §5
CC-G18. No README exists for the CC module; the header comment is the
nearest discoverable doc home for users browsing the module source.

Comparison doc §7.1 CC-G18 marked closed-by-doc.

---

### T8 spec — Document CC editor-mode limitation

**Gap**: CC-G18.

**Scope**: Add a section to `modules/programs/claude-code/README.md` (or the module's
nearest doc home) noting that vim/editor mode cannot be set via `settings.json` because
upstream removed the persistent setting in v2.1.91 — it is now a runtime `/config`
toggle. Reference comparison doc §5.

**DoD**: Documentation merged; comparison doc §7.1 CC-G18 marked closed-by-doc.

---

### T9 (P2) — OC server + skills + autoupdate + snapshot + username + default_agent — **COMPLETE (2026-04-08)**

**Implementation notes (2026-04-08)**: Added to `modules/programs/opencode/opencode.nix`:
- `server.{port,hostname,mdns,mdnsDomain,cors}` — nullable submodule fields; only
  emitted under `server` key when at least one is set (OC-G8).
- `snapshot` — `nullOr bool`, default null (OC-G15).
- `username` — `nullOr str`, default null (OC-G18).
- `autoupdate` — type widened from `bool` to `nullOr (either bool (enum ["notify"]))`,
  default preserved as `true`; serialization gated on `!= null` (OC-G16).
- `defaultAgent` — already present (line 303, pre-existing, OC-G19 already closed).
- `skills.paths` / `skills.urls` — already present in `_hm/skills.nix` and wired via
  `_internal.skill{Paths,Urls}` (OC-G8/G9 already closed).

Keys verified against `~/src/opencode/packages/opencode/src/config/config.ts:770-788`
(Server schema) and 849-1044 (Info schema). All key names use camelCase as upstream
defines them (mdnsDomain, default_agent is exposed in Nix as `defaultAgent` but
upstream JSON key is `default_agent` — already handled by existing serializer).

**Caveat**: `defaultAgent` → upstream key is `default_agent` (snake_case), already
serialized correctly by the pre-existing `optionalAttrs ... { default_agent = ... }`
line. Other new keys (snapshot, username, autoupdate, server subfields) are camelCase
in upstream except `mdnsDomain` which upstream has as `mdnsDomain` — confirmed.

`nix flake check --no-build` passed (exit 0). Comparison doc OC-G8, OC-G15, OC-G16,
OC-G18 closed; OC-G9, OC-G19 confirmed already-closed.

---

### T9 spec — OC server + skills + autoupdate + snapshot + username + default_agent

**Gaps**: OC-G8, OC-G9, OC-G15, OC-G16, OC-G18, OC-G19.

**Scope**: Add scalar/list options:
- `server.{port,hostname,mdns,mdnsDomain,cors}`
- `skills.paths`, `skills.urls`
- `snapshot` (boolean)
- `autoupdate` (`null | bool | "notify"`)
- `username`
- `defaultAgent`

**DoD**: Options serialize to `opencode.json`; flake check.

---

### T10 (P3) — OC provider option surface — COMPLETE (2026-04-09, commit 08fa0c4)

**Gaps**: OC-G10, OC-G11, OC-G12, OC-G13, OC-G14.

**Implementation notes (2026-04-09)**: Replaced bare `types.attrs` provider option
with `types.attrsOf providerModule` submodule. Provider submodule mirrors upstream
`config.ts:788-847` with typed options:
- `whitelist` / `blacklist` — `nullOr (listOf str)` for model filtering
- `models` — `nullOr jsonType` for per-model overrides with variants
- `options` — freeform submodule with typed leaves for `timeout` (int | false),
  `chunkTimeout` (int), `setCacheKey` (bool), `enterpriseUrl` (str), `apiKey` (str),
  `baseURL` (str), plus catchall for provider-specific keys (e.g. Bedrock's
  region/profile/endpoint)

Added top-level options:
- `disabledProviders` — `nullOr (listOf str)`, disables auto-detected providers
- `enabledProviders` — `nullOr (listOf str)`, allowlist mode
- `enterprise.url` — `nullOr str`, enterprise self-hosted URL

Serialization via `mkProviderAttrs` helper strips null leaves and empty provider
entries. Keys verified against `~/src/opencode/packages/opencode/src/config/config.ts`
and `~/src/opencode/packages/web/src/content/docs/config.mdx` examples.

`nix flake check --no-build` passed; `home-manager switch --dry-run` passed.
OC-G10..OC-G14 closed.

**Original scope**: Extend the OC provider option type to include `whitelist`, `blacklist`,
`options.{timeout,chunkTimeout,setCacheKey,enterpriseUrl}`. Add `disabledProviders` /
`enabledProviders` top-level lists. Add `enterprise.url`.

**DoD**: A test host configures whitelist + timeout for one provider; generated
`opencode.json` matches `~/src/opencode/packages/web/src/content/docs/config.mdx`
example shape.

---

### T11 (P3) — OC MCP per-server knobs — COMPLETE (2026-04-09)

**Gap**: OC-G17.

**Implementation notes (2026-04-09)**: Extended `_hm/mcp-servers.nix` custom server
submodule with three new options matching upstream `config.ts:373-431`:
- `timeout` — `nullOr ints.positive`, milliseconds (both McpLocal and McpRemote support
  this). Default null = omit (upstream default: 5000ms).
- `oauth` — `nullOr (either (enum [false]) (submodule { clientId, clientSecret, scope }))`
  for remote servers. `false` disables OAuth auto-detection; submodule mirrors
  `McpOAuth` schema (config.ts:394-407). All submodule fields nullable.
- `enabled` — changed from `types.bool` (default true) to `nullOr bool` (default null)
  so users can explicitly disable a server without removing it from config.
- Removed incorrect comment claiming "OpenCode doesn't support timeout at server level".
- Added `cleanCustomServer` helper that strips null values, empty attrsets, and empty
  lists from custom server definitions before serialization. This prevents upstream's
  `.strict()` zod schemas from rejecting unknown keys (e.g., `url: null` on a local
  server). Also recursively strips nulls from nested `oauth` attrsets.

`nix flake check --no-build` passed; `home-manager switch --dry-run` passed. OC-G17 closed.

**Original scope**: Extend `opencode/_hm/mcp-servers.nix` so each server option supports
`enabled` (already in CC parity?), `timeout`, and `oauth.{clientId,clientSecret,scope}`.

**DoD**: One server configures oauth via nix; generated MCP block matches
`config.ts:393-426`.

---

### T12 (P3) — OC permission catchall + specialized agents + agent fields — COMPLETE (2026-04-09, commit c4d35c5)

**Gaps**: OC-G20, OC-G21, OC-G22.

**Implementation notes (2026-04-09)**: Three changes in `opencode.nix`:

1. **Permission catchall (OC-G20)**: Already worked — `attrsOf permissionRuleType`
   accepts arbitrary keys. Updated description to document catchall behavior and
   added MCP tool name example (`mcp__myserver__mytool`).

2. **Specialized agents (OC-G21)**: Already worked — `attrsOf agentModule` accepts
   any name. Updated description and added example showing well-known agent names:
   plan, build (primary); general, explore (subagent); title, summary, compaction
   (specialized).

3. **Agent submodule fields (OC-G22)**: Extended `agentModule` to mirror upstream
   `config.ts:521-556` with 9 new fields: `variant` (str), `temperature` (float),
   `top_p` (float), `disable` (bool), `mode` (enum: subagent/primary/all),
   `hidden` (bool), `color` (str — hex or theme name), `steps` (positive int),
   `options` (freeform JSON). Made `description` optional (nullable) to match
   upstream. Updated `agentConfig` serializer to emit all new fields when non-null.

`nix flake check --no-build` passed; `home-manager switch --dry-run` passed.
OC-G20, OC-G21, OC-G22 closed.

---

### T13 (P3) — OC experimental + plugin + LSP env passthrough — COMPLETE (2026-04-09, commit be1bafd)

**Gaps**: OC-G23, OC-G24, OC-G25.

**Implementation notes (2026-04-09)**: Three changes in `opencode.nix`:

1. **Experimental typed attrset (OC-G23)**: Replaced bare `types.attrs` with a
   typed submodule backed by `freeformType = jsonType` for forward-compat. Six
   typed fields matching upstream `config.ts:1019-1038` (snake_case as upstream
   defines them): `openTelemetry` (bool), `batch_tool` (bool),
   `disable_paste_summary` (bool), `primary_tools` (listOf str),
   `continue_loop_on_deny` (bool), `mcp_timeout` (positive int). Serialization
   strips null leaves via `filterAttrs`.

2. **Plugin top-level array (OC-G24)**: Added `plugin` option as
   `listOf (either str (listOf jsonType))` matching upstream `PluginSpec =
   string | [string, Record<string, unknown>]` (config.ts:48/870). Separate
   from `tui.plugins` (which controls TUI plugin enablement).

3. **LSP configuration (OC-G25)**: Added `lsp` option as `either (enum [false])
   (attrsOf lspServerModule)`. Server submodule has `command`, `extensions`,
   `disabled`, `env` (attrsOf str), and `initialization` (nullOr jsonType).
   Supports `false` to disable all LSP. Serialization strips null/empty leaves.
   Matches upstream config.ts:962-997.

**Bonus**: Added `compaction.reserved` (nullOr ints.unsigned) — upstream field
that was missing from our module (config.ts:1011-1016).

`nix flake check --no-build` passed; `home-manager switch --dry-run` passed.
OC-G23, OC-G24, OC-G25 closed.

**Original scope**:
- Make `experimental` a typed attrset rather than freeform (add fields:
  `openTelemetry`, `batchTool`, `disablePasteSummary`, `primaryTools`,
  `continueLoopOnDeny`, `mcpTimeout`).
- Add `plugin` (top-level array, separate from tui plugins).
- Verify `lsp.{name}.env` and `lsp.{name}.initialization` round-trip.

**DoD**: Each new field tested by setting once and inspecting `opencode.json`.

---

### T14 — Comparison doc closure — COMPLETE (2026-04-09)

**Implementation notes (2026-04-09)**:
- Pulled both upstream repos: OC `3a0e00d` → `b060066`, CC `b543a25` → `3c72545`
- New upstream fields found: OC `oauth.redirectUri`, `variant_list` keybind, `mouse`
  in tui-schema; CC v2.1.94-2.1.97 added `sandbox.network.allowMachLookup`, statusline
  `refreshInterval`. All forward-compatible with freeform types — no new gaps created.
- Updated §1 commit SHAs to current upstream HEADs
- Updated §6 cross-reference matrix: replaced all "—" cells with actual Nix option
  paths for every gap closed by T2-T13 (26 cell updates across §6.1-§6.10)
- Restructured §7.1 and §7.2 gap tables: replaced "Why it matters / P31-MISS?" columns
  with "Status / Closed by" columns. All 43 gaps marked CLOSED (or CLOSED-BY-DOC for
  CC-G18).
- Added new upstream fields to §2.2 (sandbox.network.allowMachLookup), §3.6
  (oauth.redirectUri), §4.2 (variant_list keybind)
- Updated §12 audit history with T14 closure entry

**DoD**: Every closed gap reflects current module state; doc commit SHAs in §1 are
re-verified against upstream HEADs (re-run T0).

---

## Definition of Done (whole plan)

- All P0 + P1 + P2 tasks complete (T0, T1, T2, T3, T4, T5, T8, T9)
- P3 tasks completed in priority order as time allows (T6, T7, T10, T11, T12, T13)
- P4 doc task complete (T8)
- `nix flake check --no-build` passes
- One reference host has each newly-exposed option set in its config to prove the path
  works end-to-end
- Comparison doc §7 gap tables show no remaining unaddressed rows (or rows are marked
  "closed-by-doc" / "closed-as-wontfix" with rationale)
- T14 completed last

## Non-Goals

- Reimplementing CC sandbox in OC (no equivalent upstream)
- Adding hooks to OC (OC has plugin SDK, not hooks — different surface)
- Exposing every theme name as a nix enum (theme list lives in mdx, not schema)
- Changing CC editor-mode behavior (upstream-only)
- Touching `~/src/opencode` or `~/src/claude-code` directly (read-only audit sources)
