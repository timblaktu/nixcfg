# Claude Code Skill Authoring Standard

This is the convention for authoring Claude Code skills in this repository. It adopts
Anthropic's official Agent Skills guidance verbatim where it exists, and defines one
addition Anthropic is silent on: how to structure a **modular skill** that has a shared
core plus swappable environment-specific parts.

Skills are registered in [`modules/programs/claude-code/_hm/skills.nix`](../modules/programs/claude-code/_hm/skills.nix)
and deployed by home-manager. `disk-doctor` is the reference implementation of this standard.

## Part A - Anthropic's rules (adopted as-is)

Sources: [Claude Code skills](https://code.claude.com/docs/en/skills),
[Agent Skills best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices),
[overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview).

1. **Frontmatter.** `name` (lowercase/digits/hyphens, <=64 chars, matches the skill directory,
   never contains `claude`/`anthropic` or angle brackets). `description` is the trigger - write
   it third-person with **what it does AND when to use it, key use case first**, concrete
   keywords, no time-sensitive text. `description` + `when_to_use` are truncated at **1,536
   characters** in the listing. Use optional fields deliberately: `allowed-tools` (pre-approve
   only read-only/safe commands), `disable-model-invocation` (for side-effecting skills),
   `metadata`, `compatibility`, `paths`.
2. **Progressive disclosure.** Three levels: metadata (always loaded) -> `SKILL.md` body (on
   trigger) -> bundled reference files and scripts (on demand, ~0 tokens until read). Keep
   `SKILL.md` **under 500 lines** and concise - every line is a recurring token cost; state
   *what to do*, not narration.
3. **Scripts vs references.** Deterministic, fragile, or reusable work -> an executable
   **script** ("run X"). Detailed knowledge -> a **reference file** ("see X"). Reference bundled
   scripts with the `${CLAUDE_SKILL_DIR}` path variable, never a hard-coded path. Reference
   files stay one level deep; forward slashes only.
4. **Degrees of freedom.** Match latitude to fragility: low-freedom "run exactly this" for
   fragile or destructive operations; high-freedom prose where judgment applies.
5. **Single responsibility + naming.** One focused capability per skill; clear, consistent
   names (gerund or plain noun); never `helper`/`utils`.
6. **Evaluation-driven.** Author **>=3 evaluation scenarios before** the prose, each listing the
   expected behavior. Store them under `evals/` (dev-only; not deployed).

## Part B - This repo's addition: the modular shared-core + environment-module pattern

Anthropic documents two ways to be modular - several composable skills, or one skill with
conditional-workflow branches - but gives no pattern for a single capability whose
implementation genuinely differs by environment (OS, platform, backend). Splitting such a
capability into N separate skills fragments it; inlining every variant bloats `SKILL.md`. The
standard here:

1. **One focused skill.** `SKILL.md` is the **shared core**: the procedure, the decision
   framework, the safety model, and a **dispatch step** ("detect the environment -> load
   `references/<env>.md`, run `scripts/os/<env>.sh`").
2. **Deterministic core work is a Nix-pinned script.** The OS-agnostic heavy lifting is one
   script whose toolset is **nix-managed** - either a `pkgs.writeShellApplication` with pinned
   `runtimeInputs`, or a plain script plus the tools added to `home.packages` gated on the
   skill's toggle (what `disk-doctor` does: `dust`/`duf`/`ncdu`). Never assume tools are on
   `PATH`; degrade gracefully to `coreutils` where reasonable.
3. **Environment parts are swappable modules, loaded on demand.** `references/<env>.md`
   (knowledge) + `scripts/os/<env>.sh` (actions). **Ship all of them** - progressive disclosure
   makes unused modules cost ~0 tokens, so there is **no build-time per-environment trimming**.
   Selection happens at **runtime** (the dispatch step), which keeps the skill portable.
4. **Every module self-asserts its environment.** Each `scripts/os/<env>.sh` begins with a
   one-line guard (e.g. `uname -s` / WSL detection) and exits non-zero if run in the wrong
   environment, so a mis-dispatch fails loud instead of producing wrong output.
5. **home-manager's role is to pin toolsets and gate environment-specific Nix dependencies -
   not to trim progressively-disclosed resources.**

### Directory layout (reference: `disk-doctor`)

```
skills/<name>/
  SKILL.md                      # shared core: procedure + safety + dispatch (<500 lines)
  scripts/analyze.sh            # OS-agnostic core work; nix-managed toolset
  scripts/os/<env>.sh           # per-environment action module; self-asserts env
  references/<env>.md           # per-environment knowledge; loaded on demand
  evals/*.json                  # >=3 scenarios; dev-only, not in the skills.nix `files` set
```

### skills.nix registration

Add a `builtinSkillDefs.<name>` entry whose `files` ship `SKILL.md`, the core script, and
every environment module/reference (but **not** `evals/`), plus a `builtins.<name>` bool
toggle (default `true`). Gate any tool closures in `home.packages` on that toggle.

## Checklist

- [ ] `name` valid; `description` has what + when, key use first, <=1,536 chars with `when_to_use`
- [ ] `SKILL.md` < 500 lines; detail pushed to `references/`
- [ ] Deterministic work in a script; toolset nix-managed; `${CLAUDE_SKILL_DIR}` for paths
- [ ] Destructive steps are low-freedom, proposed-and-confirmed, `sudo` handed to the user
- [ ] All environment modules ship; runtime dispatch; each module self-asserts its environment
- [ ] `>= 3` evals authored before the prose; not deployed
- [ ] `builtins.<name>` toggle added; tool closures gated on it
