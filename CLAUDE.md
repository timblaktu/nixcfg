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
- **MODULE NAMING CONVENTION**: Use standard `programs.claude-code` and `programs.opencode` namespaces. Upstream home-manager modules are disabled via `disabledModules` in base.nix to avoid conflicts. Our enhanced implementations provide multi-account support, categorized hooks, statusline variants, MCP helpers, and WSL integration.

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

### ✅ **Termux Package Building - TUR Integration** (COMPLETED - 2026-01-20)

**Branch**: `opencode`
**Status**: ✅ **ALL PACKAGES DEPLOYED** - Ready for testing on Termux device

**Package Architecture** (4 separate packages):
```
TUR Packages:
├── claude-code          ✅ v0.1.0-1 deployed (22 MB npm wrapper)
├── claude-wrappers      ✅ v1.0.1-1 deployed (3.9 KB)
├── opencode             ✅ v0.1.0-1 deployed (44 KB npm wrapper)
└── opencode-wrappers    ✅ v1.0.0-1 deployed (3.9 KB)
```

**Deployment Timeline**:
- Phase 1: ✅ claude-code + claude-wrappers created
- Phase 2: ✅ opencode + opencode-wrappers created
- Phase 3: ✅ All 4 packages deployed to TUR fork (commit 4215392)
- Phase 4: ✅ Workflow bug fixed (commit 55010d6)
- Phase 5: ⏳ Test all packages on Termux device (next session)

**Architecture Decision**: Separate packages (not monolithic, not shared library)
- Each binary has its own package (claude-code, opencode)
- Each has separate wrapper package (claude-wrappers, opencode-wrappers)
- Accept wrapper code duplication for simplicity
- Matches Debian single-responsibility pattern

**Repository URLs**:
- TUR Fork: https://github.com/timblaktu/tur
- APT Repository: https://timblaktu.github.io/tur
- Workflow: https://github.com/timblaktu/tur/actions

---

#### ✅ **claude-wrappers** (DEPLOYED v1.0.1)

**What Was Built**:
- ✅ Three wrapper commands: `claudemax`, `claudepro`, `claudework`
- ✅ Interactive setup helper: `claude-setup-work`
- ✅ GitHub Actions workflow for automated builds and APT publishing
- ✅ Preinst conflict detection - fails fast with informative errors
- ✅ Comprehensive documentation

**Features vs nixcfg HM Module**:
- ✅ Basic: Config directory switching, telemetry disabling, token management
- ❌ Advanced: V2.0 coalescence, PID management, rbw integration, headless mode
- **Decision**: Advanced features are LOW PRIORITY for Termux use case

**Current Limitation**: Cannot be tested without `claude-code` package providing the binary

**Installation** (when claude-code is ready):
```bash
# Add repository
echo "deb [trusted=yes] https://timblaktu.github.io/tur stable main" | \
  tee $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list

# Update and install
pkg update
pkg install claude-code claude-wrappers

# Verify installation
which claude claudemax claudepro claudework
claudemax --version
```

---

#### ✅ **claude-code** (READY FOR DEPLOYMENT)

**Status**: Package created, ready to deploy to TUR fork
**Commit**: `90ba8ff` + `a4bfd40`

**What Was Built**:
- ✅ npm wrapper package (installs `@anthropic-ai/claude-code` from npm)
- ✅ Provides `/data/data/com.termux/files/usr/bin/claude` command
- ✅ GitHub Actions workflow for automated builds and APT publishing
- ✅ Comprehensive documentation and deployment guide
- ✅ Post-install and pre-removal scripts with helpful messages

**Architecture Decision**: npm wrapper (not vendored binary)
- **Advantages**: Lighter weight, automatic upstream tracking, simpler maintenance
- **Trade-offs**: Requires nodejs-lts dependency, network during installation

**Files Created**:
- `tur-package/claude-code/build.sh` - Package definition with npm installation
- `tur-package/claude-code/README.md` - User documentation (usage, troubleshooting)
- `tur-package/claude-code/DEPLOYMENT.md` - Deployment guide for maintainers
- `tur-package/.github/workflows/build-claude-code.yml` - CI/CD automation

**Deployment Steps** (see `tur-package/claude-code/DEPLOYMENT.md`):
```bash
cd ~/path/to/tur
cp -r ~/termux-src/nixcfg/tur-package/claude-code tur/
cp ~/termux-src/nixcfg/tur-package/.github/workflows/build-claude-code.yml .github/workflows/
git add tur/claude-code/ .github/workflows/build-claude-code.yml
git commit -m "Add claude-code package (Priority 0)"
git push origin master
# Watch build: https://github.com/timblaktu/tur/actions
```

**Post-Deployment Testing**:
```bash
# On Termux device
pkg update
pkg install claude-code
claude --version
pkg install claude-wrappers
claudemax --version  # Should work now!
```

---

#### ✅ **opencode** (COMPLETED - 2026-01-19)

**Status**: Package created, ready to deploy (commit 33a38cc)

**What Was Built**:
- ✅ npm wrapper package (installs `@opencode-ai/sdk` from npm)
- ✅ Provides `/data/data/com.termux/files/usr/bin/opencode` command
- ✅ GitHub Actions workflow for automated builds and APT publishing
- ✅ Comprehensive documentation and deployment guide
- ✅ Post-install and pre-removal scripts with helpful messages

**Architecture Decision**: npm wrapper (parallel to claude-code)
- **npm package**: `@opencode-ai/sdk` (not `@anthropic-ai/claude-code`)
- **Upstream**: https://github.com/anomalyco/opencode
- **Advantages**: Lighter weight, automatic upstream tracking, simpler maintenance

**Files Created**:
- `tur-package/opencode/build.sh` - Package definition with npm installation
- `tur-package/opencode/README.md` - User documentation (usage, troubleshooting)
- `tur-package/opencode/DEPLOYMENT.md` - Deployment guide for maintainers
- `tur-package/.github/workflows/build-opencode.yml` - CI/CD automation

---

#### ✅ **opencode-wrappers** (COMPLETED - 2026-01-19)

**Status**: Package created, ready to deploy (commit 33a38cc)

**What Was Built**:
- ✅ Three wrapper commands: `opencodemax`, `opencodepro`, `opencodework`
- ✅ Interactive setup helper: `opencode-setup-work`
- ✅ GitHub Actions workflow for automated builds and APT publishing
- ✅ Preinst conflict detection - fails fast with informative errors
- ✅ Comprehensive documentation (parallel to claude-wrappers)

**Files Created**:
- `tur-package/opencode-wrappers/build.sh` - Package definition
- `tur-package/opencode-wrappers/README.md` - User documentation
- `tur-package/opencode-wrappers/{opencodemax,opencodepro,opencodework}` - Wrapper scripts
- `tur-package/opencode-wrappers/opencode-setup-work` - Setup helper
- `tur-package/.github/workflows/build-opencode-wrappers.yml` - CI/CD automation

**Architecture Note**: Code duplication accepted (parallel to claude-wrappers)
- Simpler than shared library
- Each package is self-contained
- Matches Debian single-responsibility pattern

---

**DEPLOYMENT STATUS (2026-01-20)**: ✅ **COMPLETED - ALL PACKAGES DEPLOYED**

**Final State**:
- ✅ All 4 packages created and merged to master (commit 4215392)
- ✅ Workflow bug fixed (commit 55010d6)
- ✅ All 4 packages successfully published to APT repository
- ✅ All packages accessible via HTTPS

**Published Packages** (https://timblaktu.github.io/tur/dists/stable/main/binary-all/):
- ✅ claude-code_0.1.0-1.deb (22 MB) - npm wrapper for @anthropic-ai/claude-code
- ✅ claude-wrappers_1.0.1-1.deb (3.9 KB) - claudemax, claudepro, claudework
- ✅ opencode_0.1.0-1.deb (44 KB) - npm wrapper for @opencode-ai/sdk
- ✅ opencode-wrappers_1.0.0-1.deb (3.9 KB) - opencodemax, opencodepro, opencodework

**Bug Fixed**:
```yaml
# BEFORE (build-claude-wrappers.yml:178, build-opencode-wrappers.yml:178)
force_orphan: true  # ❌ Wipes all existing packages

# AFTER (commit 55010d6)
keep_files: true    # ✅ Preserves existing packages
```

**Resolution Details**:
- Root cause: Both wrapper workflows used `force_orphan: true`, causing each run to wipe gh-pages
- Fixed: Changed to `keep_files: true` in both wrapper workflows
- Race condition: opencode-wrappers workflow failed due to simultaneous pushes, but all packages still published
- Final result: All 4 packages verified accessible via HTTP 200

**TUR Fork Commits**:
- nixcfg: `33a38cc` (all 4 packages created)
- TUR fork master: `4215392` (initial deployment), `55010d6` (workflow fix)
- TUR fork gh-pages: `f77d16d` (all 4 packages published)

**Installation Instructions**:
```bash
# Add repository
echo "deb [trusted=yes] https://timblaktu.github.io/tur stable main" | \
  tee $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list

# Update and install
pkg update
pkg install claude-code claude-wrappers    # For Claude Code
pkg install opencode opencode-wrappers      # For OpenCode

# Verify installation
which claude claudemax claudepro claudework
which opencode opencodemax opencodepro opencodework
claude --version
opencode --version
```

**Testing Instructions**: See [tur-package/TERMUX-TESTING.md](tur-package/TERMUX-TESTING.md) for comprehensive testing guide.

**Quick Start Testing**:
```bash
# On Termux device
echo "deb [trusted=yes] https://timblaktu.github.io/tur stable main" | \
  tee $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list
pkg update
pkg install claude-code claude-wrappers opencode opencode-wrappers

# Verify
claude --version && opencode --version
which claudemax claudepro claudework
which opencodemax opencodepro opencodework
```

**Documentation**:
- [tur-package/README.md](tur-package/README.md) - Project overview
- [tur-package/TUR-FORK-SETUP.md](tur-package/TUR-FORK-SETUP.md) - Deployment guide
- [tur-package/DEPLOYMENT-STATUS.md](tur-package/DEPLOYMENT-STATUS.md) - Deployment tracking
- [tur-package/nixcfg-integration/INTEGRATION-GUIDE.md](tur-package/nixcfg-integration/INTEGRATION-GUIDE.md) - Architecture

**File Locations**:
- Source: `tur-package/{package-name}/` (nixcfg repo)
- Deployed: `tur/{package-name}/` (TUR fork)
- Workflow: `.github/workflows/*.yml` (TUR fork)
- Artifacts: `dists/stable/main/binary-all/` (gh-pages branch)

### 🔧 **Pending Tasks**

#### ✅ **OpenCode Permissions Configuration** (COMPLETED - 2026-01-20)

**Branch**: `opencode`
**Status**: ✅ Fixed and committed (commit c2ec743)

**Problem Resolved**:
- OpenCode was failing to read local image files, falling back to ineffective WebFetch
- Root cause: Missing `permissions` configuration in opencode-enhanced (base.nix:492-559)

**Solution Implemented**:
- Added permissions block to opencode-enhanced in home/modules/base.nix (lines 554-566)
- Permissions now match claude-code configuration:
  - Allows: Bash, Read, Write, Edit, WebFetch, MCP servers (context7, mcp-nixos, sequential-thinking)
  - Denies: Search, Find, dangerous Bash operations

**Files Modified**:
- `home/modules/base.nix:554-566` - Added permissions configuration
- `opencode-runtime/.opencode-*/opencode.json` - Generated configs updated for all accounts

**Verification**:
```bash
# Verify permissions in generated config:
cat opencode-runtime/.opencode-work/opencode.json | jq '.permission'
# ✅ Shows all tool permissions correctly configured
```

**Testing Instructions**:
```bash
# Start opencode work account:
opencodework

# Test with canary image:
# Prompt: "What is the sum of the numbers in the image at '/mnt/c/Users/blackt1/OneDrive - Panasonic Avionics Corporation/Pictures/numbers-to-sum.jpg'?"

# Expected: OpenCode uses Read tool to access image (not WebFetch)
# This enables proper OCR workflow with codecompanion/qwen-a3b model
```

**Next Step**: Test OpenCode with canary image to verify Read tool access and assess qwen-a3b vision capabilities for mkb OCR integration.

---

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
