# 🔄 SESSION WORKFLOW PROTOCOL

## Starting a New Session
When user says **"resume"**, **"continue"**, or **"next task"**:
1. Check `user-plans/` for any plans with PENDING tasks
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

## End of Session (MANDATORY - NO EXCEPTIONS)
Write `.session-state/active-plan` (plan file path) and `.session-state/HANDOFF.md` (self-contained: what was done, what's next, blockers). Per-worktree file channel - concurrent sessions cannot clobber it. Print "Handoff written: ..." to confirm. NEVER end a session without doing this.

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

Agent wrappers (`claudemax`, `claudepro`, etc.) wrap `nix` in a systemd cgroup scope with memory limits (MemoryHigh=65%/Max=75% per-eval; 80%/90% aggregate slice). Bypass: `NIX_NO_GUARD=1`. Source: `claude-runtime/bin/nix-guarded.sh`, `modules/lib/nix-guarded.nix`. Diagnostics: `systemctl --user status nix-eval.slice`.

# CLAUDE-CODE CONFIGURATION AND STATE MANAGEMENT

**Local sessions:**
- Use `CLAUDE_CONFIG_DIR` → `claude-runtime/.claude-{account}/`
- Never touch `.claude/`
- Hook script at `.claude/SessionStart` (web sessions only)

**Web sessions:**
- Use `.claude/settings.json` for hooks
- Create runtime state in `.claude/` (all ignored except settings.json)
- Hook runs `.claude/SessionStart` (installs nix in ephemeral web environments)

**Account-agnostic file-based memory (plan 064):** Claude Code's memory store is keyed by
the git-common-dir (main-worktree) path, so it is *repo* knowledge, not account knowledge.
Each account's `projects/<key>/memory` is a symlink to one canonical per-repo-key store at
`claude-runtime/shared-memory/<key>/`, so switching accounts (e.g. Max -> Pro) does NOT drop
accumulated memory. The account wrapper (`_hm/lib.nix` -> `_cc_share_memory`) establishes this
lazily on each launch for the repo being opened. Transcripts/todos stay per-account. If MORE
than one account already holds a non-empty store for a key, the wrapper STOPS and warns rather
than auto-merging `MEMORY.md` (resolve by hand, then relaunch). `shared-memory/` is gitignored
runtime state.

## Filesystem View of Claude Configuration and Runtime State

```
nixcfg/
├── claude-runtime/
│   ├── .claude-default/
│   │   ├── settings.json      # ❌ Ignored (Nix build output, regenerated by switch)
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

Dendritic module pattern: `modules/programs/` (22+ features), `modules/hosts/` (7 hosts), `modules/system/types/` (minimal/default/cli/desktop), `modules/flake-parts/` (14), `modules/lib/`, `pkgs/`.
WSL: NixOS-WSL (`settings/wsl/`) = full NixOS distro; HM-on-any-WSL (`settings/wsl-home/`) = portable.
Image layers: `wsl-enterprise -> wsl-dev-team -> nixos-wsl-dev-team (host) -> personal (host)`.

Plans live in `user-plans/` (completed in `user-plans/archive/`). Check for `TASK:PENDING` to find next work.
