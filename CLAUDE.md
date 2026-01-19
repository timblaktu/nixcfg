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

### ✅ **OpenCode Branch Validation** (COMPLETED - 2026-01-17)

**Branch**: `opencode`
**Status**: All validation tests passed, ready for merge or SOPS integration

**Completed Work**:
- ✅ Fixed Bitwarden configuration (item: "PAC Code Companion v2", field: "API Key")
- ✅ Fixed CRITICAL BUG: Missing `--field` flag in rbw get command (lib.nix + opencode.nix)
- ✅ Removed file fallback logic (requires rbw, fails fast with clear error if not available)
- ✅ Fixed wrapper naming: `opencodework`, `opencodemax`, `opencodepro` (no hyphens, matches claude pattern)
- ✅ Updated authentication to use ANTHROPIC_AUTH_TOKEN (not ANTHROPIC_API_KEY) per Code-Companion docs
- ✅ Added explicit ANTHROPIC_API_KEY="" to prevent conflicts with bearer auth
- ✅ Documented SOPS integration plan (docs/claude-opencode-sops-integration-plan.md)
- ✅ **VALIDATED**: Both `claudework` and `opencodework` successfully connect to Code-Companion proxy

**Key Technical Fix**:
```nix
# Before (BROKEN): rbw get "ITEM" "FIELD"
# After (FIXED):   rbw get "ITEM" --field "FIELD"
```

**Files Modified**:
- `home/modules/claude-code/lib.nix:65` - Added `--field` flag to rbw command
- `home/modules/opencode.nix:539` - Already had correct syntax
- `home/modules/base.nix:376-379,529-532` - Fixed Bitwarden item/field references
- `home/common/development.nix:135-142` - Fixed claudework wrapper config
- `docs/claude-opencode-sops-integration-plan.md` - Comprehensive 3-week SOPS plan
- `opencode-runtime/.opencode-work/*` - Generated work account configurations

**Commit**: `9530a1f` - "Fix rbw command syntax and add opencode-work configuration"

**Decision Point**: Choose next action:
- **Option A**: Merge `opencode` branch to `main` (validation complete, working system)
- **Option B**: Continue with SOPS integration on `opencode` branch (3-week plan ready)
- **Option C**: Test additional scenarios before deciding

**SOPS Integration Plan** (ready when approved):
- Plan: `docs/claude-opencode-sops-integration-plan.md`
- Features: Dual-mode (runtime rbw + build-time sops-nix)
- Timeline: 3 weeks (module options, SOPS setup, docs, testing)
- Benefit: No rbw unlock required, faster launch, offline support

### ✅ **Termux Package Building - TUR Integration** (COMPLETED - 2026-01-19)

**Branch**: `opencode` (implementation complete, ready for new branch/commit)
**Status**: Production-ready package definition and CI/CD, ready for TUR fork deployment

**What Was Built**:
- ✅ Complete Termux package definition for claude-wrappers
- ✅ Three wrapper commands: `claudemax`, `claudepro`, `claudework`
- ✅ Interactive setup helper: `claude-setup-work`
- ✅ GitHub Actions workflow for automated builds and APT publishing
- ✅ Setup script for end users: `setup-termux-repos.sh`
- ✅ Comprehensive documentation (3 guides, README, integration architecture)

**Location**: `tur-package/` directory

**Key Files**:
- `tur-package/claude-wrappers/build.sh` - Package definition following TUR conventions
- `tur-package/claude-wrappers/{claudemax,claudepro,claudework}` - Wrapper scripts
- `tur-package/.github/workflows/build-claude-wrappers.yml` - CI/CD automation
- `tur-package/TUR-FORK-SETUP.md` - Complete deployment guide
- `tur-package/nixcfg-integration/setup-termux-repos.sh` - One-command user setup
- `tur-package/README.md` - Project overview

**Architecture**: Producer-Consumer Pattern
```
TUR Fork (timblaktu/tur)           nixcfg Repository
├─ Produces .deb packages     ←─   ├─ Package definitions (tur-package/)
├─ GitHub Actions builds           ├─ Setup scripts
├─ APT repository (Pages)          └─ Documentation
└─ Distribution                →   End Users: pkg install claude-wrappers
```

**Features**:
- Platform-independent package (no compilation needed)
- Follows TUR best practices and conventions
- Automated building and publishing via GitHub Actions
- APT repository hosted on GitHub Pages
- Separate config directories per account (max, pro, work)
- Bearer token authentication for Code-Companion proxy
- Security-conscious (chmod 600 for secrets)
- Extensive error handling and user feedback

**Next Steps**:
1. **Choose branch strategy**: Create `termux-packages` branch or work on current `opencode`?
2. **Commit changes**: Stage tur-package/ directory and commit
3. **Fork TUR**: Fork https://github.com/termux-user-repository/tur
4. **Deploy**: Copy package definition to TUR fork, enable Actions/Pages
5. **Test**: Install on Termux device and validate end-to-end

**Advantages Over Previous Approach**:
- ✅ `pkg install claude-wrappers` (vs manual copy)
- ✅ `pkg upgrade` for updates (vs manual sync)
- ✅ Proper versioning and dependency tracking
- ✅ Discoverable via `pkg search`
- ✅ Integrated with Termux ecosystem
- ✅ Automated CI/CD pipeline

**Documentation**:
- [tur-package/README.md](tur-package/README.md) - Project overview
- [tur-package/TUR-FORK-SETUP.md](tur-package/TUR-FORK-SETUP.md) - Deployment guide
- [tur-package/nixcfg-integration/INTEGRATION-GUIDE.md](tur-package/nixcfg-integration/INTEGRATION-GUIDE.md) - Architecture

**Research Findings**:
- Studied TUR (Termux User Repository) structure and conventions
- Analyzed existing packages for best practices
- Confirmed Docker-based builds are standard for TUR
- Native on-device builds possible but not used by TUR community
- GitHub Actions + GitHub Pages is proven TUR deployment pattern

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
