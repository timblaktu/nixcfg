# 🔄 SESSION WORKFLOW PROTOCOL

## Starting a New Session
When user says **"resume"**, **"continue"**, or **"next task"**:
1. Check `.claude/user-plans/` for any plans with PENDING tasks
2. Find the first PENDING task (or continue IN_PROGRESS task)
3. State the task scope concisely and ask for confirmation before proceeding

## Task Execution Pattern (5 Steps)
Every task follows this pattern - adapt depth based on complexity:

### 1. **Research** (if needed)
- Review relevant files, understand current state
- Skip if prior session already documented findings
- Document any new discoveries in plan or CLAUDE.md

### 2. **Present**
- State task scope in 2-3 sentences
- List specific files to be modified/created
- Note any ambiguities or decision points
- **STOP and wait for user confirmation**

### 3. **Approve**
- User confirms scope OR asks for clarification
- Resolve any ambiguities before proceeding
- If scope changes significantly, update plan file first

### 4. **Execute**
- Make changes following completion standard
- Commit at logical inflection points
- Keep user informed of progress on longer tasks

### 5. **Validate**
- Run `nix flake check --no-build`
- For HM changes: `home-manager switch --flake '.#TARGET' --dry-run`
- Verify expected behavior
- **Only mark COMPLETE after validation passes**

## End of Session
Always provide continuation prompt:
```
Continue Plan 019.
Last completed: [task ID and brief description]
Next task: [task ID] - [one-line description]
Check: [relevant file path]
```

---

# ⚠️ CRITICAL PROJECT-SPECIFIC RULES ⚠️
- **SESSION CONTINUITY**: Update plan files (not CLAUDE.md) with task progress and provide end-of-response summary of changes made
- **COMPLETION STANDARD**: Tasks complete ONLY when: (1) `git add` all files, (2) `nix flake check` passes, (3) `nix run home-manager -- switch --flake '.#TARGET' --dry-run` succeeds, (4) end-to-end functionality demonstrated. **Writing code ≠ Working system**
- **NEVER WORK ON MAIN OR MASTER BRANCH**: ALWAYS ask user what branch to work on, and switch to or create it from main or master before starting work
- **MANDATORY GIT COMMITS AT INFLECTION POINTS**: ALWAYS `git add` and `git commit` ALL relevant changes before finalizing your response to user
- **CONSERVATIVE TASK COMPLETION**: NEVER mark tasks as "completed" prematurely. Err on side of leaving tasks "in_progress" or "pending" for review in next session.
- **VALIDATION ≠ FIXING**: Validation tasks should identify and document issues, not necessarily resolve them
- **STOP AND SUMMARIZE**: When discovering architectural issues during validation, STOP and provide a clear summary rather than attempting immediate fixes
- **DEPENDENCY ANALYSIS BOUNDARY**: When hitting build system complexity (Nix dependency injection, flake outputs), document the issue and recommend next steps rather than deep-diving into the build system
- **NIX FLAKE CHECK DEBUGGING**: When `nix flake check` fails, debug in-place using: (1) `nix log /nix/store/...` for detailed failure logs, (2) `nix flake check --verbose --debug --print-build-logs`, (3) `nix build .#checks.SYSTEM.TEST_NAME` for individual test execution, (4) `nix repl` + `:lf .` for interactive flake exploration. NEVER waste time on manual test reproduction - use Nix's built-in debugging tools.
- **RAPID ITERATION = FREQUENT CHECK-INS**: When user says "rapid iteration" or "quick/short responses", this means STOP AFTER EACH SMALL STEP and report back for guidance. Do NOT interpret as "work faster" - it means "communicate more frequently". After each change, explain what you did and ask what to do next.
- **DENDRITIC MODULE PATTERN**: All feature modules use `flake.modules.homeManager.*` namespace (e.g., `modules.homeManager.claude-code`). Upstream home-manager modules are disabled via `disabledModules` INSIDE each dendritic module's deferredModule content. Enhanced implementations provide multi-account support, categorized hooks, statusline variants, MCP helpers, and WSL integration.
- **HOME-MANAGER FILE CONFLICTS**: When `home-manager switch` reports "Existing file would be clobbered":
  1. **COMPARE**: Show both the existing file and the nix-generated file
  2. **ANALYZE**: Find the Nix config that generates it; determine if this is conventional (new Nix-managed file) or unexpected
  3. **INTEGRATE**: If conventional, ensure important content from manual file is added to Nix config BEFORE proceeding
  4. **PROCEED**: Only then use `-b backup` flag. If not conventional, STOP and report findings to user.

# 🔧 **DEVELOPMENT ENVIRONMENT**
- Claude code may be running in the terminal or the web. Both use the same .claude/ and CLAUDE.md files in the repo.
- We define a session startup hook to ensure nix is installed in the environment.
  - **Web** environments are ephemeral, so nix will always need to be installed every session startup
  - **Local** environments already have nix, so hook should be a no-op (fast)
- **Environment config**: `modules/flake-parts/dev-shells.nix` defines tooling

## Nix Concurrency Guard

Agent wrapper scripts (claudemax, opencodepro, etc.) prepend a `nix` wrapper to PATH
that runs each nix invocation inside a systemd cgroup scope with memory limits. This
prevents OOM kills from runaway nix evaluations without the fd-leak problems of the
previous flock-based approach.

- **Mechanism**: `systemd-run --user --scope` under `nix-eval.slice`
- **Baseline**: `nix flake check --no-build` peaks at ~16.6G RSS on 27.4G RAM (measured 2026-04-18)
- **Per-eval limits** (each nix invocation):
  - MemoryHigh=65% — soft ceiling; kernel throttles (swaps aggressively) above this but doesn't kill
  - MemoryMax=75% — hard ceiling; kernel OOM-kills the process immediately if reached
- **Slice ceiling** (aggregate for all concurrent evals):
  - MemoryHigh=80% — aggregate soft ceiling for all scopes in nix-eval.slice
  - MemoryMax=90% — aggregate hard ceiling
- **Adaptive killing**: `ManagedOOMMemoryPressure=kill` on slice registers with systemd-oomd. When memory pressure (PSI) exceeds 80% for 60s, oomd kills a process within the slice
- **System safety nets**: `systemd-oomd` (pressure-based) + `earlyoom` (5% free threshold) enabled in system-default NixOS layer
- **Bypass**: `NIX_NO_GUARD=1 nix <command>` skips the guard
- **Tuning**: `NIX_GUARD_MEM_HIGH=70% NIX_GUARD_MEM_MAX=80%` for per-session overrides
- **Graceful degradation**: If `systemd-run --user` fails (containers, CI), nix runs unguarded
- **Source**: `claude-runtime/bin/nix-guarded.sh` (template), `modules/lib/nix-guarded.nix` (Nix package)
- **Scope**: Only agent sessions — regular user `nix` commands are unaffected
- **Diagnostics**: `systemctl --user status nix-eval.slice`, `systemd-cgtop`
- **History**: See `docs/nix-guarded-fd-leak.md` for the flock-era fd-leak analysis and resolution

# CLAUDE-CODE CONFIGURATION AND STATE MANAGEMENT

**Local sessions:**
- Use `CLAUDE_CONFIG_DIR` → `claude-runtime/.claude-{account}/`
- Never touch `.claude/`
- Hook script at `.claude/SessionStart` (web sessions only)

**Web sessions:**
- Use `.claude/settings.json` for hooks
- Create runtime state in `.claude/` (all ignored except settings.json)
- Hook runs `.claude/SessionStart` (installs nix in ephemeral web environments)

## Filesystem View of Claude Configuration and Runtime State

```
nixcfg/
├── claude-runtime/
│   ├── .claude-default/
│   │   ├── settings.json      # ✅ Checked in (Nix-managed)
│   │   ├── .claude.json       # ❌ Ignored (runtime)
│   │   └── .mcp.json          # ❌ Ignored (runtime)
│   ├── .claude-max/
│   │   └── ... (same)
│   └── .claude-pro/
│       └── ... (same)
└── .claude/                   # Web sessions ONLY
    ├── settings.json          # ✅ Checked in (web hooks)
    ├── .claude.json           # ❌ Ignored (runtime)
    ├── .mcp.json              # ❌ Ignored (runtime)
    └── logs/                  # ❌ Ignored (runtime)
```

# Common Nix Development Workflow Commands
```bash
nixpkgs-fmt <file>              # Format Nix files
nix flake check                 # Validate entire flake (MANDATORY before commits)
nix flake update                # Update flake inputs
# Use $(hostname) to get correct config - NEVER assume hostname from examples:
nix build ".#homeConfigurations.\"${USER}@$(hostname)\".activationPackage"
home-manager switch --flake ".#${USER}@$(hostname)"
```

# 🔧 **IMPORTANT PATHS for LOCAL sessions**

1. `/home/tim/src/nixpkgs` - Local nixpkgs fork (active development: writers-auto-detection)
2. `/home/tim/src/home-manager` - Local home-manager fork (active development: autoValidate + fcitx5 fixes)  
3. `/home/tim/src/NixOS-WSL` - WSL-specific configurations (active development: plugin shim integration)
4. `/home/tim/src/git-worktree-superproject` - working tree for MY PROJECT implementing fast worktree switching for multi-repo and nix flake projects. We will eventually USE this here in nixcfg to facilitate multiple concurrent nix- development efforts


## Architecture Overview

Repository uses **dendritic module pattern** (since 2026-02-08):
- Feature modules: `modules/programs/` (22+ modules)
- Host configs: `modules/hosts/` (7 hosts)
- System types: `modules/system/types/` (minimal/default/cli/desktop)
- Flake infrastructure: `modules/flake-parts/` (14 modules)
- Shared libraries: `modules/lib/`
- Custom packages: `pkgs/`

**Two WSL scenarios**:
1. **NixOS-WSL** (`modules/system/settings/wsl/`) - Full NixOS distro on WSL
2. **Home Manager on ANY WSL** (`modules/system/settings/wsl-home/`) - Portable to vanilla distros

**WSL image layers** (distributable team images):
```
wsl-enterprise (module) -> wsl-dev-team (module) -> nixos-wsl-dev-team (host) -> personal (host)
```

## Active Work

### USB/IP + Jetson Orin Nano Development
**Status**: USB infrastructure merged to main, needs hardware verification
**Remaining**: NixOS-WSL usbip.nix upstream PR, Jetson flashing workflow
**Details**: `modules/system/settings/wsl/wsl.nix` (usbip options), `docs/NIXOS-WSL-BARE-MOUNT-CONTRIBUTION-PLAN.md`

## Deferred Work

- **Fork upstream PRs**: nixpkgs (autoWriter), home-manager (autoValidate), NixOS-WSL (VSOCK + bare mount) - on hold pending git-worktree-superproject
- **Claude Code upstream**: statusline styles, MCP helpers, categorized hooks, multi-account RFC
- **marker-pdf GPU**: runs on CPU despite CUDA availability

## Active Plans

Plans live in `.claude/user-plans/`. Completed plans are in `.claude/user-plans/archive/`.
Check plans for TASK:PENDING to find next work items.

## MANDATORY: Next Session Prompt Template
After EVERY response, provide this format:
```
Continue working on [SPECIFIC TASK]. Current status: [WHAT WAS JUST DONE].
Next step: [SPECIFIC ACTION].
Key context: [CRITICAL INFO].
Check: [FILE/LOCATION TO VERIFY].
```
