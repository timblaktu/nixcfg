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

---

### ✅ **Plan 013: Mikrotik Management Skill Enhancement** (COMPLETED - 2026-01-28)

**Branch**: `opencode`
**Status**: ✅ Skill v2.1.0 complete - DHCP/DNS + Configuration Management, ready for hardware deployment

**Objective**: Extend mikrotik-management skill to support complete L1.0 network configuration with immutable infrastructure approach.

**Completed Work**:

**Phase 1** (2026-01-27) - Service Configuration:
- ✅ DHCP server operations (6 functions): pool, server, network, leases, validation
- ✅ DNS configuration (6 functions): upstream servers, static entries, cache, validation
- ✅ L1.0 complete workflow (8-port bridge + DHCP + DNS)
- ✅ mikrotik_status() function for compact status display

**Phase 2** (2026-01-28) - Configuration Management:
- ✅ Fixed YAML frontmatter (skill registration bug - `/mikrotik` commands not appearing)
- ✅ Section 8: Configuration State Management
  - `config_backup()` - Binary backups (device flash + local ~/.config)
  - `config_export()` - Text exports (version-controllable, drift detection)
  - `config_inspect()` - Detect L1.0 vs factory vs unknown state
  - `config_restore()` - Restore from binary backup
- ✅ Section 9: Reset & Deploy Operations
  - `reset_to_factory()` - Factory reset with keep-users/no-defaults options
  - `reset_and_configure()` - Immutable workflow: inspect → backup → reset → deploy → validate
  - `apply_incremental_changes()` - Experimental incremental mode
- ✅ Section 10: Validation & Drift Detection
  - `validate_against_spec()` - Verify L1.0 compliance
  - `config_drift_report()` - Compare current vs baseline

**Phase 3** (2026-01-28) - Local Configuration Design:
- ✅ Section 11: Local Configuration Design & Deployment
  - `config_design_local()` - Generate .rsc files from specs (L1.0, custom) or templates
  - `config_parse_rsc()` - Parse and validate .rsc files locally (no device needed)
  - `config_deploy_from_rsc()` - Upload and import .rsc to device (replace/merge modes)
  - `config_template_list()` - Show available templates
  - `config_create_template()` - Save .rsc as reusable template
  - Complete workflow examples and .rsc format documentation
- ✅ Infrastructure-as-Code workflow: Design locally → Version control → Deploy to device
- ✅ Storage: `~/.config/mikrotik/local-designs/` for local configs and templates

**Design Philosophy**:
- **Immutable infrastructure** (preferred): reset → configure → validate
- **Local design first**: Create/edit .rsc locally before deploying to hardware
- **Version control**: .rsc files are text, git-friendly, infrastructure-as-code
- **Safety first**: Automatic backups before destructive operations
- **Template library**: Reusable configurations for common patterns

**Technical Details**:
- All operations include idempotency checks and dry-run mode
- RouterOS 7 integration: `/system backup`, `/export`, `/import`, `/system reset-configuration`
- Supports unknown firmware/config detection via `config_inspect()`
- Automatic safety backups before reset operations
- .rsc format: Plain text RouterOS scripting (human-readable, editable)
- .backup format: Binary (device flash only, disaster recovery)

**Files Modified**:
- `home/modules/claude-code/skills/mikrotik-management/SKILL.md` - v2.2.0 (2608 lines, +885 total additions)

**Network Configuration** (L1.0 ready to deploy):
```yaml
Bridge: bridge-attic (flat, no VLAN tagging)
Ports: ether1-ether8
Gateway: 10.0.0.1/24
DHCP Pool: 10.0.0.100-200
DHCP Domain: attic.local
DNS Upstream: 1.1.1.1, 8.8.8.8
NUC Static Lease: 10.0.0.10 (MAC-based)
DNS Entries: nux.attic.local, attic.local → 10.0.0.10
```

**Skill Version**: 2.2.0 (Local Design + Configuration Management)

**Commits**:
- `4c02117` - Fix YAML frontmatter for skill registration
- `94fcc2e` - Add configuration management (sections 8-10, +416 lines)
- `4a3f1f9` - Add local configuration design (section 11, +469 lines)

**Next Steps**:
1. Run `home-manager switch` to deploy skill v2.2.0
2. Restart claudepro to reload skill
3. Test local design workflow:
   - `config_design_local "test-L1.0" "L1.0"` (creates ~/.config/mikrotik/local-designs/test-L1.0.rsc)
   - `config_parse_rsc ~/.config/mikrotik/local-designs/test-L1.0.rsc` (validates locally)
4. At hardware: Deploy with `config_deploy_from_rsc 192.168.88.1 ~/.config/mikrotik/local-designs/test-L1.0.rsc "replace"`

**Key Files**:
- Skill: `home/modules/claude-code/skills/mikrotik-management/SKILL.md` (v2.2.0, 2608 lines)
- Workflows: Lines 606-778 (L1.0), 1842-1891 (reset-and-configure), 2077-2510 (local design)

---

### 🔧 **Pending Tasks**

#### ✅ **OpenCode Vision Support Configuration** (COMPLETED - 2026-01-20)

**Branch**: `opencode`
**Status**: ✅ Fixed, tested, and verified (commits c2ec743, ad71afc, 010f38f)

**Problem Resolved**:
- OpenCode was failing to read local image files with error "model may not be able to read images"
- Root cause: Missing `modalities` configuration for custom qwen-a3b model

**Investigation Journey**:
1. ✅ Permissions were already correctly configured (commit c2ec743)
2. ❌ Initially tried `supports_vision: true` (hallucinated from LiteLLM docs)
3. ✅ Found actual OpenCode requirement: `modalities` object via [issue #3084](https://github.com/anomalyco/opencode/issues/3084)

**Solution Implemented**:
- Added modalities to qwen-a3b model in codecompanion provider (base.nix:534-537):
```nix
modalities = {
  input = [ "text" "image" ];
  output = [ "text" ];
};
```

**Files Modified**:
- `home/modules/base.nix:534-537` - Added modalities configuration
- `opencode-runtime/.opencode-*/opencode.json` - Regenerated with modalities

**Verification & Testing**:
✅ **PASSED**: opencodework successfully read local JPG image and performed OCR to sum numbers correctly

**Key Learnings**:
1. OpenCode custom models require explicit modalities declarations, not `supports_vision` flags (LiteLLM-specific)
2. Qwen3-VL-30B-A3B is vision-language model: inputs images, outputs text only (not image generation)
3. Model is ready for mkb integration for PDF OCR workload

---

### 🔧 **DrawIO/Diagram Skill WSL2 Fix** (ACTIVE - 2026-02-02)

**Branch**: `opencode` (nixcfg), work in `~/src/drawio-svg-sync`
**Status**: Root cause identified, fix planned

**Problem**: `drawio-svg-sync` fails in WSL2 because `drawio-headless` unconditionally uses Xvfb, which can't create sockets in WSL2's `/tmp/.X11-unix`.

**Solution**: Bypass `drawio-headless`, use `drawio` directly with smart display detection:
- If `DISPLAY` is set and xdpyinfo works → use drawio directly (works with WSLg)
- If no display → fall back to xvfb-run

**Proof of Concept PASSED**: Direct `drawio -x -f svg` with `DISPLAY=:0` renders successfully.

**Plan**: `~/src/drawio-svg-sync/PLAN-WSL2-FIX.md`
**Related**: nixcfg Plan 016 (diagram skill) blocked until this is fixed.

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
