# AI Tool Feature Comparison: Claude Code vs OpenCode

Persistent reference for Nix module parity work. This document is **enumeration-based**:
every claim cites a source file:line in the upstream repos rather than relying on recall.

## 1. Methodology

This document was rebuilt 2026-04-06 (Plan 032 audit) after Plan 031's recall-based
comparison was found to have systematic omissions. The methodology now is:

- **OpenCode** schemas extracted mechanically from Zod definitions in
  `~/src/opencode/packages/opencode/src/config/{config.ts,tui-schema.ts,tui.ts}`
  and cross-checked against `packages/web/src/content/docs/{config,tui,keybinds}.mdx`.
- **Claude Code** schema assembled from `~/src/claude-code/examples/settings/*.json`,
  `~/src/claude-code/CHANGELOG.md` (versions 2.1.69–2.1.92), and the plugin-dev
  skill files. CC is closed source, so the schema is observed-only — there may be
  additional internal keys not documented in the public sources.
- Nix module exposure verified by reading `modules/programs/{claude-code,opencode}/`
  rather than recalled.

**Source commits at time of audit**:
- OpenCode: `b060066` (`~/src/opencode`) — refreshed 2026-04-09 (Plan 032 T14)
- Claude Code: `3c72545` (`~/src/claude-code`) — refreshed 2026-04-09 (Plan 032 T14)

**Authoritative-source paths** (so a future audit can re-verify):

| Tool | Schema source | Doc source |
|------|---------------|-----------|
| OpenCode `opencode.json` | `packages/opencode/src/config/config.ts:849-1044` | `packages/web/src/content/docs/config.mdx` |
| OpenCode `tui.json` | `packages/opencode/src/config/tui-schema.ts:1-37` + `config.ts:610-765` | `packages/web/src/content/docs/{tui,keybinds}.mdx` |
| Claude Code `settings.json` | `examples/settings/*.json` + `CHANGELOG.md` | `plugins/plugin-dev/skills/{plugin-settings,hook-development}/` |

## 2. Claude Code `settings.json` — Field Enumeration

Every key observed in CC's public sources. Type column shows JSON shape; "Source"
column gives the example file or CHANGELOG version that documents it.

### 2.1 Permissions

| Key | Type | Purpose | Source |
|-----|------|---------|--------|
| `permissions.defaultMode` | `"ask" \| "allow" \| "plan" \| "acceptEdits" \| "auto"` | Default tool decision mode | `examples/settings/settings-strict.json:3`, CHANGELOG v2.1.91 (auto) |
| `permissions.ask` | `string[]` (tool patterns) | Tools requiring approval | `examples/settings/settings-strict.json:4-6` |
| `permissions.deny` | `string[]` (tool patterns) | Tools that are blocked | `examples/settings/settings-strict.json:7-10` |
| `permissions.disableBypassPermissionsMode` | `"disable"` | Block `--dangerously-skip-permissions` | `examples/settings/settings-lax.json:3` |
| `allowManagedPermissionRulesOnly` | `boolean` | Block user-defined permission rules | `examples/settings/settings-strict.json:12` |

Permission rule syntax (CHANGELOG v2.1.72-2.1.85):
- `Bash(*)`, `Bash(git *)`, `Bash(npm install)`, `Bash(cmd:*)` — bash command patterns
- `Read(/path)`, `Read(//path/**)`, `Write(/path)`, `Edit(.claude)` — path patterns (`//` = absolute, recursive)
- `mcp__.*`, `mcp__servername_.*` — MCP regex
- Verbs: `allow`, `deny`, `ask`, `defer` (PreToolUse, headless sessions)

### 2.2 Sandbox

| Key | Type | Purpose | Source |
|-----|------|---------|--------|
| `sandbox.enabled` | `boolean` | Master switch | `examples/settings/settings-bash-sandbox.json:4` |
| `sandbox.failIfUnavailable` | `boolean` | Exit if sandbox missing | CHANGELOG v2.1.83 |
| `sandbox.autoAllowBashIfSandboxed` | `boolean` | Auto-approve sandboxed Bash | `examples/settings/settings-bash-sandbox.json:6` |
| `sandbox.allowUnsandboxedCommands` | `boolean` | Allow non-sandboxed commands | `examples/settings/settings-bash-sandbox.json:6` |
| `sandbox.excludedCommands` | `string[]` | Commands bypassing sandbox | `examples/settings/settings-bash-sandbox.json:7` |
| `sandbox.enableWeakerNestedSandbox` | `boolean` | Weaker nested sandbox | `examples/settings/settings-bash-sandbox.json:16` |
| `sandbox.enableWeakerNetworkIsolation` | `boolean` | TLS bypass (macOS) | CHANGELOG v2.1.70 |
| `sandbox.network.allowMachLookup` | `boolean` | Mach lookup (macOS) | CHANGELOG v2.1.97 |
| `sandbox.network.allowUnixSockets` | `string[]` | Allowed unix sockets | `examples/settings/settings-bash-sandbox.json:9` |
| `sandbox.network.allowAllUnixSockets` | `boolean` | All unix sockets | `examples/settings/settings-bash-sandbox.json:10` |
| `sandbox.network.allowLocalBinding` | `boolean` | Local network binding | `examples/settings/settings-bash-sandbox.json:11` |
| `sandbox.network.allowedDomains` | `string[]` | Allowed domains | `examples/settings/settings-bash-sandbox.json:12` |
| `sandbox.network.httpProxyPort` | `number \| null` | HTTP proxy | `examples/settings/settings-bash-sandbox.json:13` |
| `sandbox.network.socksProxyPort` | `number \| null` | SOCKS proxy | `examples/settings/settings-bash-sandbox.json:14` |
| `sandbox.filesystem.allowWrite` | `string[]` | Write whitelist | CHANGELOG v2.1.77 |
| `sandbox.filesystem.denyRead` | `string[]` | Read blacklist | CHANGELOG v2.1.70 |
| `sandbox.filesystem.allowRead` | `string[]` | Re-allow read in denied regions | CHANGELOG v2.1.77 |

### 2.3 Hooks

CC supports the following hook events (see `plugins/plugin-dev/skills/hook-development/` and CHANGELOG):

| Event | Trigger | First documented |
|-------|---------|------------------|
| `PreToolUse` | Before tool execution | foundational |
| `PostToolUse` | After tool execution | foundational |
| `Stop` | Agent considers stopping | foundational |
| `SubagentStop` | Subagent considers stopping | v2.1.84 |
| `UserPromptSubmit` | User submits prompt | v2.1.75 |
| `SessionStart` | Session init | v2.1.75 |
| `SessionEnd` | Session terminate | v2.1.75 |
| `PreCompact` / `PostCompact` | Around context compaction | v2.1.76 |
| `CwdChanged` | Working directory change | v2.1.83 |
| `FileChanged` | Project file change | v2.1.83 |
| `PermissionDenied` | Auto-mode classifier denial | v2.1.89 |
| `StopFailure` | API error stops turn | v2.1.78 |
| `TaskCreated` | TaskCreate invoked | v2.1.84 |
| `WorktreeCreate` / `WorktreeRemove` | Worktree isolation lifecycle | v2.1.75 |
| `InstructionsLoaded` | CLAUDE.md loaded | v2.1.69 |
| `Elicitation` / `ElicitationResult` | MCP structured input | v2.1.76 |
| `Notification` | Claude sends notification | v2.1.76 |
| `ConfigChange` | Config file changed during session | v2.1.89 |
| `SubagentStart` | Subagent spawned | CHANGELOG (post-v2.1.92) |
| `TaskCompleted` | Multi-agent task finished | CHANGELOG (post-v2.1.92) |
| `TeammateIdle` | Multi-agent teammate idle | CHANGELOG (post-v2.1.92) |
| `Setup` | Triggered via `--init` / `--maintenance` | CHANGELOG (post-v2.1.92) |

Hook config shape: `hooks: { <Event>: [{ matcher, hooks: [{ type: "command"|"prompt", command|prompt }] }] }`.

### 2.4 MCP, plugins, marketplaces

| Key | Type | Purpose | Source |
|-----|------|---------|--------|
| `allowedMcpServers` | `string[]` | Allowed MCP servers | CHANGELOG v2.1.84 |
| `deniedMcpServers` | `string[]` | Denied MCP servers | CHANGELOG v2.1.84 |
| `allowedChannelPlugins` | `string[]` | Enterprise plugin allowlist | CHANGELOG v2.1.84 |
| `enabledPlugins` | `object` | Plugin enable/disable | CHANGELOG v2.1.80 |
| `pluginTrustMessage` | `string` | Custom plugin trust warning | CHANGELOG v2.1.69 |
| `strictKnownMarketplaces` | `string[]` | Known-only marketplace restriction | `examples/settings/settings-lax.json:5` |
| `allowManagedHooksOnly` | `boolean` | Block user hooks | `examples/settings/settings-strict.json:13` |
| `forceRemoteSettingsRefresh` | `boolean` | Block startup until settings refreshed | CHANGELOG v2.1.92 |

MCP server entry shape (foundational): `mcpServers: { <name>: { command, args, env } }` for stdio; remote MCP via `{ url, headers }`.

### 2.5 UX, voice, thinking

| Key | Type | Purpose | Source |
|-----|------|---------|--------|
| `voiceEnabled` | `boolean` | Voice input on startup | CHANGELOG v2.1.70 |
| `language` | `string` (BCP47) | Voice/dictation language | CHANGELOG v2.1.70 |
| `showThinkingSummaries` | `boolean` | Display thinking summaries | CHANGELOG v2.1.89 |
| `cleanupPeriodDays` | `number` | Transcript retention | CHANGELOG (foundational) |
| `disableSkillShellExecution` | `boolean` | Disable inline shell in skills | CHANGELOG (pre-v2.1.92) |
| `disableDeepLinkRegistration` | `boolean` | Block protocol-handler registration | CHANGELOG v2.1.83 |
| `includeGitInstructions` | `boolean` | Include git instructions in prompt | CHANGELOG v2.1.70 |
| `apiKeyHelper` | `string` (script path) | Dynamic API key generation | CHANGELOG v2.1.81 |
| `worktree.sparsePaths` | `string[]` | Sparse checkout paths | CHANGELOG v2.1.77 |
| `modelOverrides` | `object` | Custom provider model IDs | CHANGELOG v2.1.73 |
| `feedbackSurveyRate` | `number` | Survey sample rate | CHANGELOG (version unknown) |

### 2.6 `/config` runtime menu

The runtime `/config` menu surfaces options that **may or may not** persist to
`settings.json`. Some are session-transient.

| `/config` option | Persists to `settings.json`? | Key | CHANGELOG |
|------------------|------------------------------|-----|-----------|
| Editor mode (vim toggle) | **No — runtime/session only** | (none) | v2.1.91 (replaces removed `/vim` command) |
| Voice input | Yes | `voiceEnabled` | v2.1.70 |
| Thinking visibility | Partial | `showThinkingSummaries` | v2.1.89 |
| Effort level | No (per-session) | (none) | v2.1.77 |
| Model selection | No (per-session) | (none) | foundational |
| Show turn duration | No (per-session) | (none) | v2.1.79 |
| Language | Yes | `language` | v2.1.70 |

## 3. OpenCode `opencode.json` — Field Enumeration

Every leaf field in OC's master Zod schema (`config.ts`). Source line numbers reference
that file unless noted.

### 3.1 Top-level

| Key | Type | Default | Source |
|-----|------|---------|--------|
| `$schema` | string | — | :851 |
| `logLevel` | enum | — | :852 |
| `model` | `provider/model` | — | :892 |
| `small_model` | `provider/model` | — | :893 |
| `default_agent` | string | — | :896 |
| `username` | string | — | :902 |
| `disabled_providers` | string[] | — | :887 |
| `enabled_providers` | string[] | — | :888 |
| `share` | `"manual" \| "auto" \| "disabled"` | — | :871 |
| `autoshare` | boolean | — (deprecated) | :877 |
| `autoupdate` | `boolean \| "notify"` | — | :881 |
| `snapshot` | boolean | true | :864 |
| `instructions` | string[] | — | :998 |
| `layout` | `"auto" \| "stretch"` | — (deprecated) | :999 |
| `tools` | `Record<string, boolean>` | — (deprecated, use `permission`) | :1001 |

### 3.2 Server / watcher

| Key | Type | Source |
|-----|------|--------|
| `server.port` | int | :772 |
| `server.hostname` | string | :774 |
| `server.mdns` | boolean | :774 |
| `server.mdnsDomain` | string | :775 |
| `server.cors` | string[] | :776 |
| `watcher.ignore` | string[] | :859-862 |

### 3.3 Skills

| Key | Type | Source |
|-----|------|--------|
| `skills.paths` | string[] | :513 |
| `skills.urls` | string[] | :514-517 |

### 3.4 Plugins, commands, agents

| Key | Type | Source |
|-----|------|--------|
| `plugin` | `PluginSpec[]` | :870 |
| `command.{name}` | `Record<string, Command>` | :854-857 |
| `mode.{name}` | `Agent` (deprecated) | :906-913 |
| `agent.{plan, build, general, explore, title, summary, compaction, ...}` | `Agent` | :917-927 |

Per-agent fields (`AgentSchema`, :523-554):
`model`, `variant`, `temperature`, `top_p`, `prompt`, `tools` (deprecated), `disable`,
`description`, `mode` (`subagent`/`primary`/`all`), `hidden`, `color`, `steps`,
`maxSteps` (deprecated), `permission`, `options`.

### 3.5 Providers

| Key | Type | Source |
|-----|------|--------|
| `provider.{id}.whitelist` | string[] | :790 |
| `provider.{id}.blacklist` | string[] | :791 |
| `provider.{id}.models.{model}.variants.{name}.disabled` | boolean | :802 |
| `provider.{id}.options.apiKey` | string | :812 |
| `provider.{id}.options.baseURL` | string | :813 |
| `provider.{id}.options.enterpriseUrl` | string | :814 |
| `provider.{id}.options.setCacheKey` | boolean | :815 |
| `provider.{id}.options.timeout` | `number \| false` (default 300000) | :816 |
| `provider.{id}.options.chunkTimeout` | int | :831 |

### 3.6 MCP

| Key | Type | Source |
|-----|------|--------|
| `mcp.{id}.type` | `"local" \| "remote"` | :375, :411 |
| `mcp.{id}.command` (local) | `string[]` | :376 |
| `mcp.{id}.environment` (local) | `Record<string, string>` | :377 |
| `mcp.{id}.url` (remote) | string | :412 |
| `mcp.{id}.headers` (remote) | `Record<string, string>` | :414 |
| `mcp.{id}.enabled` | boolean | :381, :413 |
| `mcp.{id}.timeout` | int (default 5000) | :382 |
| `mcp.{id}.oauth` | `McpOAuth \| false` | :415 |
| `mcp.{id}.oauth.{clientId, clientSecret, scope, redirectUri}` | strings | :396-403 |

### 3.7 Permissions

OC permission keys (`PermissionSchema`, :471-501) — every leaf is `"ask" | "allow" | "deny"` or a record of glob → action:

`read`, `edit`, `glob`, `grep`, `list`, `bash`, `task`, `external_directory`,
`todowrite`, `question`, `webfetch`, `websearch`, `codesearch`, `lsp`, `doom_loop`,
`skill`. Plus catchall `Record<string, PermissionRule>` (:494) for arbitrary tool names.

### 3.8 Formatter / LSP

| Key | Type | Source |
|-----|------|--------|
| `formatter` | `false \| Record<string, {disabled?, command?, environment?, extensions?}>` | :948-961 |
| `lsp` | `false \| Record<string, {disabled?, command?, extensions?, env?, initialization?}>` | :962-997 |

### 3.9 Compaction, enterprise, experimental

| Key | Type | Default | Source |
|-----|------|---------|--------|
| `compaction.auto` | boolean | true | :1009 |
| `compaction.prune` | boolean | true | :1010 |
| `compaction.reserved` | int | — | :1011 |
| `enterprise.url` | string | — | :1004 |
| `experimental.disable_paste_summary` | boolean | — | :1021 |
| `experimental.batch_tool` | boolean | — | :1022 |
| `experimental.openTelemetry` | boolean | — | :1023 |
| `experimental.primary_tools` | string[] | — | :1027 |
| `experimental.continue_loop_on_deny` | boolean | — | :1031 |
| `experimental.mcp_timeout` | int | — | :1032 |

## 4. OpenCode `tui.json` — Field Enumeration

This is OC's **second** config file. Schema in `tui-schema.ts` plus the keybind map
embedded in `config.ts:610-765`. **None of this is currently exposed by our OC Nix
module's tui.json output** — the module only writes `opencode.json`.

### 4.1 Top-level

| Key | Type | Default | Source |
|-----|------|---------|--------|
| `$schema` | string | — | tui-schema.ts:29 |
| `theme` | string | — | tui-schema.ts:30 |
| `scroll_speed` | number ≥ 0.001 | 3 (mdx) | tui-schema.ts:14 |
| `scroll_acceleration.enabled` | boolean | required | tui-schema.ts:17 |
| `diff_style` | `"auto" \| "stacked"` | — | tui-schema.ts:21 |
| `mouse` | boolean | true | tui-schema.ts:25 (confirmed present in b060066) |
| `plugin` | `PluginSpec[]` | — | tui-schema.ts:32 |
| `plugin_enabled` | `Record<string, boolean>` | — | tui-schema.ts:33 |

### 4.2 Keybinds (`keybinds.*`)

The keybind schema (config.ts:610-765) defines **~110 named bindings**, each a string.
Notable groups:

- **Leader**: `leader` (default `ctrl+x`)
- **App lifecycle**: `app_exit`, `editor_open`, `theme_list`, `sidebar_toggle`,
  `scrollbar_toggle`, `username_toggle`, `status_view`
- **Sessions**: `session_export`, `session_new`, `session_list`, `session_timeline`,
  `session_fork`, `session_rename`, `session_delete`, `session_share`,
  `session_unshare`, `session_interrupt`, `session_compact`, `session_child_first`,
  `session_child_cycle`, `session_child_cycle_reverse`, `session_parent`
- **Stash**: `stash_delete`
- **Models**: `model_list`, `model_provider_list`, `model_favorite_toggle`,
  `model_cycle_recent`, `model_cycle_recent_reverse`, `model_cycle_favorite`,
  `model_cycle_favorite_reverse`, `variant_cycle`
- **Agents**: `agent_list`, `agent_cycle`, `agent_cycle_reverse`, `variant_list` (new in b060066)
- **Commands**: `command_list`
- **Messages navigation**: `messages_page_up/down`, `messages_line_up/down`,
  `messages_half_page_up/down`, `messages_first/last`, `messages_next/previous`,
  `messages_last_user`, `messages_copy`, `messages_undo`, `messages_redo`,
  `messages_toggle_conceal`
- **Tool details**: `tool_details`
- **Input editing** (~40 bindings): `input_clear`, `input_paste`, `input_submit`,
  `input_newline`, `input_move_{left,right,up,down}`, `input_select_{left,right,up,down}`,
  `input_line_{home,end}`, `input_select_line_{home,end}`,
  `input_visual_line_{home,end}`, `input_select_visual_line_{home,end}`,
  `input_buffer_{home,end}`, `input_select_buffer_{home,end}`,
  `input_delete_line`, `input_delete_to_line_{end,start}`,
  `input_backspace`, `input_delete`, `input_undo`, `input_redo`,
  `input_word_{forward,backward}`, `input_select_word_{forward,backward}`,
  `input_delete_word_{forward,backward}`, `history_{previous,next}`
- **Misc**: `terminal_suspend`, `terminal_title_toggle`, `tips_toggle`,
  `plugin_manager`, `display_thinking`

## 5. Vim / Editor Mode — Canary Result

Plan 031 omitted vim mode from its parity matrix. Re-audit finds:

- **Claude Code**: `/vim` command was **removed in v2.1.91** (CHANGELOG.md line 24);
  vim mode is now toggled via the runtime `/config` → "Editor mode" menu and is **not
  persisted to settings.json**. There is no stable settings.json key for it. This means
  Nix-managed CC config cannot pin vim mode on or off — it is a runtime user toggle.
- **OpenCode**: there is **no dedicated `vim_mode` field** in either `opencode.json` or
  `tui.json`. OC instead exposes ~110 individually-configurable keybinds in
  `tui.json:keybinds.*` (`config.ts:610-765`); a vim-style configuration is achieved by
  remapping each binding. There is no preset.

Both tools "support" vim-style editing, but neither exposes it as a single declarative
setting. Plan 031's omission was real but the underlying state is more nuanced than
"both have vim mode" — see §7 asymmetries.

## 6. Cross-Reference Matrix

Categorized by capability. "CC key" / "OC key" name the schema field, "CC Nix" / "OC Nix"
name the corresponding nixcfg module option (or `—` if not exposed).

### 6.1 Permissions

| Capability | CC key | OC key | CC Nix | OC Nix |
|-----------|--------|--------|--------|--------|
| Default decision mode | `permissions.defaultMode` | (per-rule) | `permissions.defaultMode` | — |
| Allow rules | `permissions.ask`/built-in | `permission.*` | `permissions.allow/ask/deny` | `permission.*` (typed catchall, T12) |
| Deny rules | `permissions.deny` | `permission.*` = `deny` | `permissions.deny` | `permission.*` (typed catchall, T12) |
| Bypass-mode lock | `permissions.disableBypassPermissionsMode` | n/a | `permissions.disableBypassPermissionsMode` (T4) | n/a |
| Managed-rules-only | `allowManagedPermissionRulesOnly` | n/a | `governance.allowManagedPermissionRulesOnly` (T4) | n/a |
| Doom loop prevention | n/a | `permission.doom_loop` | n/a | `permission.doom_loop` (typed catchall, T12) |

### 6.2 Sandbox / process isolation

| Capability | CC key | OC key | CC Nix | OC Nix |
|-----------|--------|--------|--------|--------|
| Sandbox enable | `sandbox.enabled` | n/a | `sandbox.enabled` (T3) | n/a |
| Sandbox network controls | `sandbox.network.*` | n/a | `sandbox.network.*` (T3) | n/a |
| Sandbox FS controls | `sandbox.filesystem.*` | n/a | `sandbox.filesystem.*` (T3) | n/a |
| Excluded commands | `sandbox.excludedCommands` | n/a | `sandbox.excludedCommands` (T3) | n/a |

### 6.3 Hooks / events

| Capability | CC | OC | CC Nix | OC Nix |
|-----------|----|----|--------|--------|
| Hook event coverage | 19 events (§2.3) | none (plugin SDK only) | `hooks.nix` (categorized) | n/a |
| `command` hooks | yes | n/a | yes | n/a |
| `prompt` hooks | yes | n/a | yes | n/a |

### 6.4 MCP

| Capability | CC | OC | CC Nix | OC Nix |
|-----------|----|----|--------|--------|
| stdio MCP | `mcpServers.{name}` | `mcp.{id}.type=local` | `mcp-servers.nix` | `mcp-servers.nix` |
| Remote MCP | `mcpServers.{name}` (url) | `mcp.{id}.type=remote` | yes | yes |
| Per-server enable toggle | n/a (presence = enabled) | `mcp.{id}.enabled` | n/a | yes |
| Per-server timeout | n/a | `mcp.{id}.timeout` | n/a | `mcp.*.timeout` (T11) |
| OAuth MCP | n/a | `mcp.{id}.oauth` | n/a | `mcp.*.oauth` (T11) |
| Allow/deny lists | `allowedMcpServers`/`deniedMcpServers` | n/a | `governance.allowed/deniedMcpServers` (T4) | n/a |

### 6.5 Commands / agents / skills

| Capability | CC | OC | CC Nix | OC Nix |
|-----------|----|----|--------|--------|
| File-based commands | `.claude/commands/` | `.opencode/commands/` | `slash-commands.nix`, `git-commands.nix`, `extended-commands.nix` | `file-commands.nix` |
| File-based agents | `.claude/agents/` | `.opencode/agents/` | `sub-agents.nix` | `agent-files.nix` |
| File-based skills | `.claude/skills/` | `.opencode/skills/` | `skills.nix` | `skills.nix` |
| Skill paths in config | n/a | `skills.paths` | n/a | `skills.paths` (pre-existing) |
| Skill URLs in config | n/a | `skills.urls` | n/a | `skills.urls` (pre-existing) |
| Memory / instructions | `CLAUDE.md` | `AGENTS.md` + `instructions[]` | yes (template) | yes (shared lib) |

### 6.6 Compaction

| Capability | CC | OC | CC Nix | OC Nix |
|-----------|----|----|--------|--------|
| Auto-compact | built-in (no key) | `compaction.auto` | n/a | yes (Plan 031 T5) |
| Prune tool outputs | n/a | `compaction.prune` | n/a | yes |
| Reserved tokens | n/a | `compaction.reserved` | n/a | `compaction.reserved` (T13) |
| Specialized compaction agent | n/a | `agent.compaction` | n/a | `agent.compaction` (typed catchall, T12) |

### 6.7 UX / display / editor mode

| Capability | CC | OC | CC Nix | OC Nix |
|-----------|----|----|--------|--------|
| Theme | n/a (in-app) | `tui.json:theme` | n/a | yes (`tui.theme`) |
| Diff style | n/a | `tui.json:diff_style` | n/a | yes (`tui.diffStyle`) |
| Scroll speed | n/a | `tui.json:scroll_speed` | n/a | yes (`tui.scrollSpeed`) |
| Scroll acceleration | n/a | `tui.json:scroll_acceleration` | n/a | yes (`tui.scrollAcceleration`) |
| Vim/editor mode | `/config` runtime only (not persisted) | individual `tui.keybinds.*` | n/a (cannot be set via config; CC-G18 doc) | `tui.keybinds` (T2) |
| Custom keybinds | n/a | ~110 in `tui.keybinds.*` | n/a | `tui.keybinds` (T2) |
| Voice input | `voiceEnabled` | n/a | `voice.enable` (T5) | n/a |
| Voice/dictation language | `language` | n/a | `voice.language` (T5) | n/a |
| Thinking summaries | `showThinkingSummaries` | n/a (per-session) | `display.showThinkingSummaries` (T5) | n/a |
| Statusline | runtime/external | n/a | `statusline.nix` (custom) | n/a |
| Snapshot tracking | n/a | `snapshot` | n/a | `snapshot` (T9) |
| Session sharing | n/a | `share`/`autoshare` | n/a | yes (`share`) |
| Watcher ignore | n/a | `watcher.ignore` | n/a | yes (`watcher.ignore`) |

### 6.8 Providers

| Capability | CC | OC | CC Nix | OC Nix |
|-----------|----|----|--------|--------|
| Custom base URL | env / proxy | `provider.{id}.options.baseURL` | yes (account `customApi.baseUrl`) | yes |
| API key in config | env / `apiKeyHelper` | `provider.{id}.options.apiKey` | yes (rbw + bearer token) | yes (rbw) |
| Provider whitelist/blacklist | `allowedMcpServers` (MCP only) | `provider.{id}.{white,black}list` | — | `provider.*.whitelist/blacklist` (T10) |
| Disabled providers | n/a | `disabled_providers` | n/a | `disabledProviders` (T10) |
| Enterprise URL | `apiKeyHelper` | `enterprise.url` | `apiKeyHelper` (T6) | `enterprise.url` (T10) |
| Model variants | n/a | `provider.{id}.models.{m}.variants` | n/a | `provider.*.models` (T10) |
| Cache key control | n/a | `provider.{id}.options.setCacheKey` | n/a | `provider.*.options.setCacheKey` (T10) |
| Request timeouts | n/a | `provider.{id}.options.{timeout,chunkTimeout}` | n/a | `provider.*.options.timeout/chunkTimeout` (T10) |

### 6.9 Plugins, marketplaces, governance

| Capability | CC | OC | CC Nix | OC Nix |
|-----------|----|----|--------|--------|
| Plugin enable/disable | `enabledPlugins` | `plugin` (array) | `governance.enabledPlugins` (T4) | `plugin` (T13) |
| Plugin trust message | `pluginTrustMessage` | n/a | `governance.pluginTrustMessage` (T4) | n/a |
| Marketplace allowlist | `strictKnownMarketplaces`, `allowedChannelPlugins` | n/a | `governance.strictKnownMarketplaces/allowedChannelPlugins` (T4) | n/a |
| Force settings refresh | `forceRemoteSettingsRefresh` | n/a | `governance.forceRemoteSettingsRefresh` (T4) | n/a |
| Disable skill shell exec | `disableSkillShellExecution` | n/a | `security.disableSkillShellExecution` (T5) | n/a |
| Disable deep links | `disableDeepLinkRegistration` | n/a | `security.disableDeepLinkRegistration` (T5) | n/a |
| Worktree sparse paths | `worktree.sparsePaths` | n/a | `worktree.sparsePaths` (T6) | n/a |

### 6.10 Observability / experimental

| Capability | CC | OC | CC Nix | OC Nix |
|-----------|----|----|--------|--------|
| OpenTelemetry | n/a | `experimental.openTelemetry` | n/a | `experimental.openTelemetry` (T13) |
| Batch tool | n/a | `experimental.batch_tool` | n/a | `experimental.batch_tool` (T13) |
| Disable paste summary | n/a | `experimental.disable_paste_summary` | n/a | `experimental.disable_paste_summary` (T13) |
| Primary-only tools | n/a | `experimental.primary_tools` | n/a | `experimental.primary_tools` (T13) |
| Continue on deny | n/a | `experimental.continue_loop_on_deny` | n/a | `experimental.continue_loop_on_deny` (T13) |
| Survey rate | `feedbackSurveyRate` | n/a | — | n/a |
| Cleanup period | `cleanupPeriodDays` | n/a | `cleanupPeriodDays` (T5) | n/a |

## 7. Gap Tables

These three tables drive Plan 032 (`.claude/user-plans/032-cc-oc-parity-gap-closure.md`).
A "gap" is a feature the upstream tool supports that our Nix module does not currently
expose. Gaps marked **(P31-MISS)** were also missing from Plan 031's comparison doc.

### 7.1 Gaps — Claude Code Nix module

| ID | CC feature | Schema key | Status | Closed by |
|----|-----------|-----------|--------|-----------|
| CC-G1 | Sandbox configuration | `sandbox.*` (entire subtree) | **CLOSED** | T3 |
| CC-G2 | Bypass-mode lockdown | `permissions.disableBypassPermissionsMode` | **CLOSED** | T4 |
| CC-G3 | Managed-rules-only | `allowManagedPermissionRulesOnly` | **CLOSED** | T4 |
| CC-G4 | Managed-hooks-only | `allowManagedHooksOnly` | **CLOSED** | T4 |
| CC-G5 | MCP allow/deny lists | `allowedMcpServers`, `deniedMcpServers` | **CLOSED** | T4 |
| CC-G6 | Marketplace governance | `strictKnownMarketplaces`, `allowedChannelPlugins` | **CLOSED** | T4 |
| CC-G7 | Plugin governance | `enabledPlugins`, `pluginTrustMessage`, `forceRemoteSettingsRefresh` | **CLOSED** | T4 |
| CC-G8 | Voice / language | `voiceEnabled`, `language` | **CLOSED** | T5 |
| CC-G9 | Thinking summaries | `showThinkingSummaries` | **CLOSED** | T5 |
| CC-G10 | Cleanup retention | `cleanupPeriodDays` | **CLOSED** | T5 |
| CC-G11 | Disable skill shell | `disableSkillShellExecution` | **CLOSED** | T5 |
| CC-G12 | Disable deep links | `disableDeepLinkRegistration` | **CLOSED** | T5 |
| CC-G13 | Include git instructions | `includeGitInstructions` | **CLOSED** | T5 |
| CC-G14 | API key helper | `apiKeyHelper` | **CLOSED** | T6 |
| CC-G15 | Worktree sparse paths | `worktree.sparsePaths` | **CLOSED** | T6 |
| CC-G16 | Model overrides | `modelOverrides` | **CLOSED** | T6 |
| CC-G17 | New hook event types | 25 events (§2.3) | **CLOSED** | T7 |
| CC-G18 | Editor mode (vim) | (no key — `/config` runtime) | **CLOSED-BY-DOC** | T8 |

### 7.2 Gaps — OpenCode Nix module

| ID | OC feature | Schema key | Status | Closed by |
|----|-----------|-----------|--------|-----------|
| OC-G1 | Entire `tui.json` file | `tui-schema.ts` (whole file) | **CLOSED** | T2 |
| OC-G2 | Theme | `tui.json:theme` | **CLOSED** | T2 (moved to tui.json) |
| OC-G3 | Scroll speed | `tui.json:scroll_speed` | **CLOSED** | T2 (moved to tui.json) |
| OC-G4 | Scroll acceleration | `tui.json:scroll_acceleration` | **CLOSED** | T2 (moved to tui.json) |
| OC-G5 | Diff style | `tui.json:diff_style` | **CLOSED** | T2 (enum fixed + moved) |
| OC-G6 | Keybinds (~110) | `tui.json:keybinds.*` | **CLOSED** | T2 (freeform attrsOf str) |
| OC-G7 | TUI plugins | `tui.json:plugin`, `plugin_enabled` | **CLOSED** | T2 |
| OC-G8 | Server config | `server.{port,hostname,mdns,mdnsDomain,cors}` | **CLOSED** | T9 |
| OC-G9 | Skills paths/URLs | `skills.{paths,urls}` | **CLOSED** | pre-existing (confirmed T9) |
| OC-G10 | Provider whitelist/blacklist | `provider.{id}.{whitelist,blacklist}` | **CLOSED** | T10 |
| OC-G11 | Provider timeouts | `provider.{id}.options.{timeout,chunkTimeout}` | **CLOSED** | T10 |
| OC-G12 | Provider cache key | `provider.{id}.options.setCacheKey` | **CLOSED** | T10 |
| OC-G13 | Enterprise URL | `enterprise.url` | **CLOSED** | T10 |
| OC-G14 | Disabled providers | `disabled_providers`, `enabled_providers` | **CLOSED** | T10 |
| OC-G15 | Snapshot toggle | `snapshot` | **CLOSED** | T9 |
| OC-G16 | Auto-update mode | `autoupdate` | **CLOSED** | T9 (type widened) |
| OC-G17 | Per-MCP enabled / timeout / oauth | `mcp.{id}.{enabled,timeout,oauth}` | **CLOSED** | T11 |
| OC-G18 | Default agent | `default_agent` | **CLOSED** | pre-existing (confirmed T9) |
| OC-G19 | Username | `username` | **CLOSED** | T9 |
| OC-G20 | Permission catchall | `permission.{custom-tool}` | **CLOSED** | T12 (documented catchall) |
| OC-G21 | Specialized agents | `agent.{title,summary,compaction}` | **CLOSED** | T12 (documented catchall) |
| OC-G22 | Agent variants/colors/steps | `agent.{name}.{variant,color,steps,hidden,mode}` | **CLOSED** | T12 (9 new fields) |
| OC-G23 | Experimental flags | `experimental.{openTelemetry,batch_tool,primary_tools,...}` | **CLOSED** | T13 (typed submodule) |
| OC-G24 | Plugin spec | `plugin[]` | **CLOSED** | T13 |
| OC-G25 | LSP per-server `env` / `initialization` | `lsp.{name}.{env,initialization}` | **CLOSED** | T13 |

### 7.3 Asymmetries (both tools support, but Nix exposure differs)

| ID | Capability | CC Nix state | OC Nix state | Asymmetry |
|----|-----------|--------------|--------------|-----------|
| ASYM-1 | MCP servers | `mcp-servers.nix` (rich) | `mcp-servers.nix` (rich) | Generally aligned post Plan 031 (cliMcpServer parity) |
| ASYM-2 | File commands | 4 modules (slash, git, extended, memory) | 1 module (`file-commands.nix`) | CC has more categories, OC has flatter layout |
| ASYM-3 | Skills | `skills.nix` deploys files | `skills.nix` shares CC's files (Plan 031 T4) | OC does not also write `skills.paths` to opencode.json |
| ASYM-4 | Compaction | n/a in CC | exposed in OC | CC has no equivalent surface |
| ASYM-5 | Bitwarden / rbw secrets | per-account bearer token | per-account secret loading | Both work, different code paths |
| ASYM-6 | Statusline | `statusline.nix` (custom shell) | n/a | CC-only feature |
| ASYM-7 | Hooks | `hooks.nix` (categorized) | n/a (OC plugins not modeled) | CC-only feature |

## 8. Permission Name Mapping

(Verified against schemas — unchanged from Plan 031 except `Skill` row added.)

| Capability | Claude Code | OpenCode |
|-----------|------------|----------|
| Shell execution | `Bash` | `bash` |
| File reading | `Read` | `read` |
| File writing | `Write` | `edit` (covers write+edit+patch) |
| File editing | `Edit` | `edit` |
| File search (glob) | `Glob` (via Bash) | `glob` |
| Content search | `Grep` (via Bash) | `grep` |
| Directory listing | (via Bash) | `list` |
| Sub-task spawning | `Task` | `task` |
| Skill invocation | `Skill` | `skill` |
| LSP operations | n/a | `lsp` |
| Todo management | `TodoWrite` | `todowrite` |
| User questions | `AskUserQuestion` | `question` |
| Web fetch | `WebFetch` | `webfetch` |
| Web search | `WebSearch` | `websearch` |
| Code search | n/a | `codesearch` |
| External dirs | n/a | `external_directory` |
| Loop prevention | n/a | `doom_loop` |
| MCP tools | `mcp__servername` | `mcp__servername` |

## 9. MCP Server Availability Matrix

(Re-verified post Plan 031 T6.)

| Server | Shared def | CC module | OC module |
|--------|-----------|-----------|-----------|
| mcp-nixos | yes | yes | yes |
| sequential-thinking | yes | yes | yes |
| context7 | yes | yes | yes |
| serena | yes | yes | yes |
| brave-search | yes | yes | yes |
| puppeteer | yes | yes | yes |
| github | yes | yes | yes |
| gitlab | yes | yes | yes |
| filesystem | yes | yes | yes |
| cli-mcp-server | yes | yes | yes (added Plan 031 T6) |

## 10. Config Format Differences

| Aspect | Claude Code | OpenCode |
|--------|------------|----------|
| Primary config | `settings.json` | `opencode.json` |
| **Secondary config** | (none) | **`tui.json`** ← formerly missed |
| Instruction file | `CLAUDE.md` | `AGENTS.md` |
| Config dir env | `CLAUDE_CONFIG_DIR` | `OPENCODE_CONFIG_DIR` |
| Command files | `.claude/commands/{cat}/{name}.md` | `.opencode/commands/{cat}/{name}.md` |
| Agent files | `.claude/agents/{name}.md` | `.opencode/agents/{name}.md` |
| Skill files | `.claude/skills/{name}/SKILL.md` | `.opencode/skills/{name}/SKILL.md` |
| MCP shape | `{ command, args, env }` | `{ type, command[], environment }` |
| MCP enable key | (presence = enabled) | `enabled: true/false` |
| Permission verbs | `allow` / `deny` / `ask` / `defer` | `allow` / `ask` / `deny` |
| Permission patterns | path/regex inside string (`Bash(*)`) | object glob → action |
| Schema reference | n/a | `$schema` URL in config |

## 11. Known Ambiguities

- **CC `feedbackSurveyRate`**: documented in CHANGELOG without a version anchor.
  May be enterprise-only.
- **CC `apiKeyHelper`**: appears in v2.1.81 context but not in any example file.
  Format (script invocation contract) is not publicly documented.
- **CC editor mode**: confirmed runtime-only (CHANGELOG v2.1.91); whether any
  internal preference key persists is not visible from public sources.
- **OC `provider.{id}.options` catchall**: `.catchall(z.any())` allows arbitrary
  provider options not enumerable from the schema.
- **OC `theme` enum**: schema is `string`, not enum. The list of valid themes lives
  in `packages/web/src/content/docs/themes.mdx` (not enumerated here).
- **CC `/config` persistence**: most runtime menu options are session-only; the
  exhaustive set of persistent vs. transient options is not documented in one place.

## 12. Audit History

| Date | Event |
|------|-------|
| 2026-04-06 | Plan 031 T1 — recall-based comparison written; missed vim mode, tui.json, ~30 other features |
| 2026-04-06 | Plan 032 audit — this document rewritten by enumeration; canary (vim mode) verified |
| 2026-04-09 | Plan 032 T14 — all 43 gaps closed (CC-G1..G18, OC-G1..G25). §6 cross-ref updated, §7 gap tables marked CLOSED. Upstream HEADs refreshed: OC `b060066`, CC `3c72545`. New upstream fields noted: OC `oauth.redirectUri`, `variant_list` keybind, `mouse` in tui-schema; CC v2.1.94-2.1.97 (`sandbox.network.allowMachLookup`, statusline `refreshInterval`). All forward-compatible with existing freeform types — no new gaps. |
