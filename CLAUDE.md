# ⚠️ CRITICAL PROJECT-SPECIFIC RULES ⚠️
- **SESSION CONTINUITY**: Update this CLAUDE.md file with task progress and provide end-of-response summary of changes made
- **COMPLETION STANDARD**: Tasks complete ONLY when: (1) `git add` all files, (2) `nix flake check` passes, (3) `nix run home-manager -- switch --flake '.#TARGET' --dry-run` succeeds, (4) end-to-end functionality demonstrated. **Writing code ≠ Working system**
- **NEVER WORK ON MAIN OR MASTER BRANCH**: ALWAYS ask user what branch to work on, and switch to or create it from main or master before starting work
- **MANDATORY GIT COMMITS AT INFLECTION POINTS**: ALWAYS `git add` and `git commit` ALL relevant changes before finalizing your response to user
- **CONSERVATIVE TASK COMPLETION**: NEVER mark tasks as "completed" prematurely. Err on side of leaving tasks "in_progress" or "pending" for review in next session.
- **VALIDATION ≠ FIXING**: Validation tasks should identify and document issues, not necessarily resolve them
- **STOP AND SUMMARIZE**: When discovering architectural issues during validation, STOP and provide a clear summary rather than attempting immediate fixes
- **DEPENDENCY ANALYSIS BOUNDARY**: When hitting build system complexity (Nix dependency injection, flake outputs), document the issue and recommend next steps rather than deep-diving into the build system
- **NIX FLAKE CHECK DEBUGGING**: When `nix flake check` fails, debug in-place using: (1) `nix log /nix/store/...` for detailed failure logs, (2) `nix flake check --verbose --debug --print-build-logs`, (3) `nix build .#checks.SYSTEM.TEST_NAME` for individual test execution, (4) `nix repl` + `:lf .` for interactive flake exploration. NEVER waste time on manual test reproduction - use Nix's built-in debugging tools.
- **RAPID ITERATION = FREQUENT CHECK-INS**: When user says "rapid iteration" or "quick/short responses", this means STOP AFTER EACH SMALL STEP and report back for guidance. Do NOT interpret as "work faster" - it means "communicate more frequently". After each change, explain what you did and ask what to do next.

# 🔧 **DEVELOPMENT ENVIRONMENT**
- Claude code may be running in the terminal or the web. Both use the same .claude/ and CLAUDE.md files in the repo.
- We define a session startup hook to ensure nix is installed in the environment.
  - **Web** environments are ephemeral, so nix will always need to be installed every session startup
  - **Local** environments already have nix, so hook should be a no-op (fast)
- **Environment config**: `flake-modules/dev-shells.nix` defines tooling

# CLAUDE-CODE CONFIGURATION AND STATE MANAGEMENT

**Local sessions:**
- Use `CLAUDE_CONFIG_DIR` → `claude-runtime/.claude-{account}/`
- Never touch `.claude/`
- Hook script at `home/files/bin/ensure-nix.sh` is fine (not web-specific)

**Web sessions:**
- Use `.claude/settings.json` for hooks
- Create runtime state in `.claude/` (all ignored except settings.json)
- Hook runs `bin/ensure-nix.sh` (same script, works in both contexts)

## Filesystem View of Claude Configuration and Runtime State

```
nixcfg/
├── home/files/bin/
│   └── ensure-nix.sh          # Shared hook script
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
nix build .#homeConfigurations."tim@thinky-nixos".activationPackage
home-manager switch --flake .#tim@thinky-nixos  # Test config switch
```

# 🔧 **IMPORTANT PATHS for LOCAL sessions**

1. `/home/tim/src/nixpkgs` - Local nixpkgs fork (active development: writers-auto-detection)
2. `/home/tim/src/home-manager` - Local home-manager fork (active development: autoValidate + fcitx5 fixes)  
3. `/home/tim/src/NixOS-WSL` - WSL-specific configurations (active development: plugin shim integration)
4. `/home/tim/src/git-worktree-superproject` - working tree for MY PROJECT implementing fast worktree switching for multi-repo and nix flake projects. We will eventually USE this here in nixcfg to facilitate multiple concurrent nix- development efforts


## 📋 **ACTIVE WORK**

For completed work history, see git log on `dev` and `main` branches.

### 🔍 **OpenCode Branch Validation** (IN PROGRESS - 2026-01-16)

**Branch**: `opencode`
**Status**: Secrets handling fixes completed, environment variable naming needs clarification

**Completed**:
- ✅ Fixed Bitwarden configuration (item: "PAC Code Companion v2", field: "API Key")
- ✅ Fixed CRITICAL BUG: opencode.nix wrapper now uses --field parameter in rbw get call
- ✅ Removed file fallback logic (requires rbw, fails fast with clear error if not available)
- ✅ Fixed wrapper naming: `opencodework`, `opencodemax`, `opencodepro` (no hyphens, matches claude pattern)
- ✅ Updated authentication to use ANTHROPIC_AUTH_TOKEN (not ANTHROPIC_API_KEY) per Code-Companion docs
- ✅ Added explicit ANTHROPIC_API_KEY="" to prevent conflicts with bearer auth
- ✅ Researched OpenCode auth - confirmed it uses same ANTHROPIC_* variables as Claude Code
- ✅ Documented SOPS integration plan (docs/claude-opencode-sops-integration-plan.md)

**Pending Validation**:
- ⏳ Test claudework command with Code-Companion proxy (uses ANTHROPIC_AUTH_TOKEN)
- ⏳ Test opencodework command with Code-Companion proxy (uses ANTHROPIC_AUTH_TOKEN)
- ⏳ Verify both tools connect to codecompanionv2.d-dp.nextcloud.aero successfully

**Files Modified** (opencode branch):
- `home/modules/base.nix:376-379,529-532`: Fixed Bitwarden item/field (both claude-code + opencode)
- `home/common/development.nix:135-142`: Fixed claudework wrapper Bitwarden config
- `home/modules/claude-code/lib.nix:54-87`: Uses ANTHROPIC_AUTH_TOKEN, blanks ANTHROPIC_API_KEY, removed file fallback
- `home/modules/opencode.nix:545-562`: Uses ANTHROPIC_AUTH_TOKEN, blanks ANTHROPIC_API_KEY, fixed rbw --field bug
- `docs/claude-opencode-sops-integration-plan.md`: Comprehensive 3-week SOPS integration plan

**Next Steps**:
1. Run: `home-manager switch --flake .#tim@thinky-nixos`
2. Test: `claudework` - verify Bitwarden token fetch and Code-Companion proxy connection
3. Test: `opencodework` - verify Bitwarden token fetch and Code-Companion proxy connection
4. If tests pass: Continue with SOPS integration on same branch OR merge opencode branch

**SOPS Integration Plan** (ready when approved):
- Plan documented at `docs/claude-opencode-sops-integration-plan.md`
- Dual-mode: Runtime (rbw, current) + Build-time (sops-nix, new)
- Timeline: 3 weeks (module options, SOPS setup, docs, testing)
- User preference: Continue on opencode branch for simplicity

### 🚧 **Deferred Tasks**

#### **Fork Development Work** (DEFERRED)
**Status**: On hold pending git-worktree-superproject implementation

**Active Forks Requiring Upstream Coordination**:
1. **nixpkgs** (`writers-auto-detection` branch): autoWriter implementation
2. **home-manager** (custom fork): autoValidate + fcitx5 fixes
3. **NixOS-WSL** (`plugin-shim-integration` branch): VSOCK + bare mount

#### **Claude Code Upstream Contributions** (PLANNED)
**See**: `home/modules/claude-code/UPSTREAM-CONTRIBUTION-PLAN.md`
- Phase 2 (2-4 weeks): Statusline styles, MCP helpers PRs
- Phase 3 (1-2 months): Categorized hooks PR
- Phase 4 (quarter): Multi-account RFC

#### **PDF-to-Markdown GPU Optimization** (IDENTIFIED)
**Problem**: marker-pdf runs on CPU despite CUDA availability
**Status**: Documented but not implemented

## MANDATORY: Next Session Prompt Template
After EVERY response, provide this format:
```
Continue working on [SPECIFIC TASK]. Current status: [WHAT WAS JUST DONE].
Next step: [SPECIFIC ACTION].
Key context: [CRITICAL INFO].
Check: [FILE/LOCATION TO VERIFY].
```
