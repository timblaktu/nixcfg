# Claude Code vs OpenCode for CodeCompanion V2 — Parity Verdict

**Date:** 2026-06-24
**Question:** I prefer OpenCode because it uses our internal CodeCompanion API better than
Claude Code. In light of recent Claude Code releases and CodeCompanion V2, is that still
true — can I use Claude Code fully with CodeCompanion?

**Verdict (corrected 2026-06-24):** The answer decomposes by **model family**, not by tool.
**Claude/Anthropic models** (including Claude-on-Bedrock: opus-4-6 / sonnet-4-6 / haiku-4-5) work
in Claude Code today. **Non-Claude CCv2 models** (`ai-proxy/Auto-MoM` — your current default —
Qwen, Llama 4, GLM 5) do **not**: CC speaks only the Anthropic Messages API and cannot call CCv2's
OpenAI-style `/v1` endpoint. An earlier draft of this doc said "largely outdated / migration
viable" — that was premature, weighing token-saving + gateway *connectivity* but not the actual
*model catalog* (see §4). **User decision (2026-06-24): go Claude-Code-centric anyway** — build
around Claude-on-Bedrock + CC's richer harness + RTK, leave OpenCode dormant, and **park** the
non-Claude question behind a credential-gated probe (the CCv2 **V2** auth change invalidated old
tokens). Tracked in `.claude/user-plans/046-ai-tool-capability-upgrade.md`.

---

## 1. Where this is all managed: nixcfg (not nixcfg-work)

Both the Claude Code and OpenCode stacks — modules, wrappers, runtime dirs — live entirely in
**nixcfg**. `nixcfg-work` only layers deployment-specific secrets/values on top via a
flake.lock pin.

| Component | Claude Code | OpenCode |
|---|---|---|
| HM module | `modules/programs/claude-code/` | `modules/programs/opencode/` |
| Wrappers | `tur-package/claude-wrappers/` (`claudemax/pro/work`) | `tur-package/opencode-wrappers/` (`opencodemax/pro/work`) |
| Runtime dirs | `claude-runtime/.claude-{max,pro,work}/` | `opencode-runtime/.opencode-{max,pro,work}/` |

The work layer's seams are explicit in the code (marked "set by team/host layer"):
`modules/flake-parts/lib.nix:292,308-323,503-512` (Bedrock/CCv2 provider scaffolding with
blank `baseURL`, bitwarden item, `modelMappings`) and the `*work` wrappers'
`ANTHROPIC_BASE_URL="https://api.example.com/v1"` placeholder.

**Implication:** feature-parity work belongs in nixcfg; it reaches the work host through
nixcfg-work's lock bump (same path the burndown/resume features took).

---

## 2. What the CCv2 / TokenSave materials actually say

Two separate things — and **both are Claude-Code-first, not OpenCode advantages.**

### 2a. CodeCompanion V2 (the LLM gateway)

Source: *"Code Companion Upgrades - 30th May 2026"* email (Sanket Deshmukh, 2026-06-01).

The V2 change is **operational, not architectural**:

- Unified token, generated via the Azure AD dashboard
  (`https://codecompanion.d-dp.nextcloud.aero/dashboard` → Code Companion V2 → Generate token).
- **Per-model hourly rate limits**, with an email alert when a limit is reached
  ("switch to another available model until the limit resets").

It remains an OpenAI/Anthropic-compatible proxy. Nothing here is OpenCode-specific.

### 2b. RTK-Tokensave (Rust Token Killer) — this inverts the assumption

Source: *"Code Companion Updates - Introducing a New LLM Token Saving Tool"* email
(2026-06-16) + Confluence PDF *"Saving LLM Tokens with PAC AI RTK Tokensave"*
(Abhiram Sharma). Repo: `https://git.panasonic.aero/pac/pac-ai-rtk-tokensave`.

RTK is **built on Claude Code's hook system**:

- It is a **`PreToolUse` Bash hook** — `rtk hook claude` — that rewrites shell commands through
  a filtering proxy before output reaches the model (git/cargo/pytest/docker/grep, 100+ commands;
  ~60-90% token reduction; ~118K → ~24K tokens per 30-min session).
- `rtk init -g` patches `~/.claude/settings.json`, installs `~/.claude/hooks/rtk-rewrite.sh`,
  and adds an `@RTK.md` reference to `~/.claude/CLAUDE.md`.
- OpenCode is the **secondary** target (`rtk init -g --opencode`). The docs, diagrams, and
  troubleshooting are all written around Claude Code.

The settings.json patch it applies:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "rtk hook claude" }] }
    ]
  }
}
```

**Takeaway:** the token-saving tool you'd be "losing" by leaving OpenCode is actually a
Claude Code feature first. If anything it is better-supported on CC.

---

## 3. Claude Code release-notes research (it is open source)

Latest release: **2.1.187** (nixpkgs unstable lags at **2.1.92**). Source:
`anthropics/claude-code` `CHANGELOG.md`. The model-selection story has moved substantially and
directly closes the gap that pushed you to OpenCode:

| Capability | Version | What it gives you for CCv2/Bedrock |
|---|---|---|
| `ANTHROPIC_MODEL` / `--model` / `/model` accept arbitrary model IDs | long-standing | point CC at *any* gateway model ID, not just 3 picker slots |
| `ANTHROPIC_BASE_URL` + bearer/bedrock auth | long-standing | already wired in `claudework` + `_hm/lib.nix` |
| `availableModels` allowlist (managed setting); `enforceAvailableModels` | 2.1.172-175 | curate the CCv2 catalog you expose |
| `fallbackModel` (up to 3, tried in order) | 2.1.166 | **directly answers CCv2's per-model hourly limits** — auto-failover when rate-limited |
| Bedrock/Vertex/gateway model-ID fixes | 2.1.141-187 | correct Haiku for background side-queries on gateways; GovCloud profile fix |
| Org-configured model restrictions across picker/`--model`/`ANTHROPIC_MODEL` | 2.1.187 | enterprise-managed model governance |

`fallbackModel` is the standout: CCv2's headline V2 change is per-model rate limits, and CC now
has native multi-model failover for exactly that scenario.

---

## 4. Verdict — corrected after inspecting the actual model catalog

An earlier version of this doc concluded "the assumption is largely outdated; migration viable."
That was premature: it weighed the *token-saving* and *gateway-connectivity* pillars but not which
*models* you actually run. The work config settles it.

**Evidence — nixcfg-work `modules/home-manager/tim-corp-personal.nix` (branch `feat/darwin-support`):**

| Provider / endpoint | Models | Claude? |
|---|---|---|
| Bedrock `ai-platform-bedrockapis…/api/v1` | claude-opus-4-6, claude-sonnet-4-6, claude-sonnet-4, claude-haiku-4-5 | yes |
| Bedrock (same) | `meta.llama4-maverick-17b`, `zai.glm-5` | no |
| CCv2 `codecompanionv2…/v1` | `qwen-a3b`, `qwen35/36-a3b`, `qwen36-dense`, `qwen3-coder-next`, **`Auto-MoM`** | no |

- Default model is **`ai-proxy/Auto-MoM`** (CCv2 Mixture-of-Models, OpenAI `/v1`).
- `disabledProviders = [ "anthropic" "opencode" ]` — direct Anthropic is off; everything routes
  through the gateway, and the catalog is majority non-Claude.

**The decisive architectural fact:** Claude Code emits ONLY the Anthropic Messages API shape (or
Bedrock-InvokeModel / Vertex-rawPredict pass-throughs). It cannot speak the OpenAI-compatible
`/v1/chat/completions` the CCv2 endpoint serves. Its native gateway model discovery
(`CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY`, since 2.1.129) **filters to IDs starting with
`claude`/`anthropic`** — so Qwen / Llama 4 / GLM 5 / Auto-MoM would never appear in CC's picker.
(Correction to an earlier draft: CC *does* now have gateway `/v1/models` discovery — but only for
the Claude subset.)

So **what works in CC depends on the model**: Claude-on-Bedrock ✅; non-Claude via CCv2 ❌
(unless CCv2 also exposes an Anthropic-Messages endpoint — unverified, credential-blocked).

**Probe note (2026-06-24):** unauthenticated probing of `codecompanionv2.d-dp.nextcloud.aero`
(`server: uvicorn`) returns **401 on every path** (`/docs`, `/health`, `/v1/models`,
`/v1/messages`, `/anthropic/v1/messages`) — a global auth wall masks endpoint existence. The
decisive test needs a valid token (see §5 / plan T15).

---

## 5. What this implies for nixcfg — Claude-Code-centric (user decision, 2026-06-24)

The chosen direction is **not** "migrate to CC because it's now equal" (it isn't), and **not**
"parity" (the two tools have non-overlapping limits). It is: **go CC-centric, leave OpenCode
dormant, build around what CC can do today, and park what it can't.**

- **Foundation (build now, no probe needed):** Claude-on-Bedrock in CC + CC's richer harness
  (hooks, statusline, task-automation, skills) + **RTK-Tokensave** as a Nix-managed `PreToolUse`
  hook (never `rtk init -g` — it clobbers `~/.claude`; use `_hm/hooks.nix`, package the binary,
  deploy `RTK.md` declaratively). Wire `fallbackModel` for CCv2 rate limits and
  `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` for the Claude subset.
- **Parked (credential-gated) — the non-Claude models:** can CC reach `Auto-MoM`/Qwen/Llama/GLM?
  Only if CCv2 also speaks Anthropic Messages format. The probe is blocked because the CCv2 **V2**
  auth change invalidated old tokens — regenerate a unified token (Azure AD dashboard), then run
  the `POST /v1/messages` vs `/v1/chat/completions` test (plan T15). Outcomes: Anthropic-format
  works ⇒ curate those IDs into `availableModels` and you're CC-only with the full catalog;
  OpenAI-only ⇒ stand up a translating gateway (LiteLLM) or briefly revive OpenCode for those.

All of this is sequenced in **`.claude/user-plans/046-ai-tool-capability-upgrade.md`**
(active: T1/T3-T7/T11/T13/T14; dormant OC: T2/T8-T10/T12; blocked: T15). Deployment reaches the
work host via a nixcfg-work flake.lock bump.

---

## 6. Status: implemented (2026-06-24, Plan 046)

The CC-centric direction decided above is now **built in nixcfg** (branch
`plan-046-ai-tool-capability-upgrade`). What shipped:

- **CC pinned to 2.1.191** (vendored `pkgs/claude-code-pinned/`, T1) — clears every feature floor
  cited in §3 (`fallbackModel` 2.1.166, gateway discovery 2.1.129, org restrictions 2.1.187).
- **Full CC capability surface exposed in the Nix module** (T3-T7): a `settingsExtra` raw
  escape-hatch; the model/provider/auth surface (`fallbackModel`, `availableModels` +
  `enforceAvailableModels`, Fable, per-account Bedrock/Vertex/Mantle/Foundry env); extended hooks
  (new events + `http`/`mcp_tool`/`prompt`/`agent` entry types + gating); skill/subagent/plugin
  frontmatter; reliability/MCP-timeout/UX/sandbox/statusline/keybindings settings; and the
  NO-AI-attribution guarantee (`includeCoAuthoredBy` defaults `false`).
- **RTK-Tokensave as a Nix-managed `PreToolUse` Bash hook** (T11) — `hooks.rtk.{enable,package}`,
  never `rtk init -g`; graceful pass-through no-op when `rtk` is absent. The corporate binary is
  packaged privately in **nixcfg-work** (`pkgs/rtk`, rtk 0.42.3), wired on the `work` account.
- **Gateway model discovery** (T13) — opt-in per-account `discovery.enable` exporting
  `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1`; surfaces only the Claude/anthropic subset (by
  design, per §4).

**Final model (corrects the §5 "hybrid" framing into what was actually built):** it is
**CC-centric, OpenCode dormant** — not a CC-primary/OC-secondary hybrid. CC handles
Claude-on-Bedrock + the richer harness + RTK + Claude-subset gateway discovery. OpenCode was **not**
bumped or extended (its pin stays at 1.14.48; plan tasks T2/T8-T10/T12 are DEFERRED) and is revived
only if the parked non-Claude path forces it.

**Pin strategy:** CC tracks latest stable via the vendored pin (bump `manifest.json` or run
`update.sh [version]`, re-stage, rebuild), decoupled from nixpkgs-unstable's lag. OC keeps its
existing `pkgs/opencode-pinned/` pin, untouched.

**Still parked:** the non-Claude CCv2 question (Auto-MoM/Qwen/Llama/GLM) remains credential-gated
(plan T15) — the §4/§5 analysis is unchanged. **Deploy gate:** RTK + discovery reach the work host
only after a nixcfg-work flake.lock bump to a nixcfg revision carrying T11/T13.

Detail: `docs/ai-tool-feature-comparison.md` §13, plan `.claude/user-plans/046-ai-tool-capability-upgrade.md`.

## Sources

- `anthropics/claude-code` `CHANGELOG.md` (latest 2.1.187).
- Email: *Code Companion Upgrades - 30th May 2026* (CCv2 onboarding, per-model rate limits).
- Email: *Code Companion Updates - Introducing a New LLM Token Saving Tool* (RTK-Tokensave).
- Confluence PDF: *Saving LLM Tokens with PAC AI RTK Tokensave* (RTK = Claude Code PreToolUse hook).
- Repo: `https://git.panasonic.aero/pac/pac-ai-rtk-tokensave`.
- In-repo: `docs/ai-tool-feature-comparison.md`, `docs/opencode-model-discovery.md`,
  `modules/programs/claude-code/`, `modules/programs/opencode/`, `modules/flake-parts/lib.nix`.
