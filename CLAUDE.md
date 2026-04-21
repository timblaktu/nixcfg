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


## 📋 **ACTIVE WORK**

### ✅ **Dendritic Migration Complete** (2026-02-08)
**Branch**: `refactor/dendritic-pattern`
**Status**: Plan 019 complete - all Phases (0-6) done

The repository has been migrated from host-centric to feature-centric (dendritic) organization:

- **Pattern**: flake-parts + import-tree for auto-discovery
- **Structure**: All features in `modules/programs/`, hosts in `modules/hosts/`
- **System types**: 4-layer hierarchy (minimal → default → cli → desktop)
- **Documentation**: Updated ARCHITECTURE.md reflects new patterns

**Key Directories** (post-migration):
| Purpose | Location |
|---------|----------|
| Feature modules | `modules/programs/` (22 modules) |
| Host configs | `modules/hosts/` (7 hosts) |
| System types | `modules/system/types/` (4 layers) |
| Flake infrastructure | `modules/flake-parts/` (14 modules) |
| Shared libraries | `modules/lib/` |
| Custom packages | `pkgs/` |

**Two WSL Scenarios** (still applicable):
1. **NixOS-WSL** (`modules/system/settings/wsl/`) - Full NixOS distro on WSL
2. **Home Manager on ANY WSL** (`modules/system/settings/wsl-home/`) - Portable to vanilla distros

For migration details, see: `.claude/user-plans/019-dendritic-migration.md`

### ✅ **Distributable NixOS-WSL Images** (COMPLETED - 2026-02-14)
**Branch**: `refactor/dendritic-pattern`
**Plan**: `.claude/user-plans/023-distributable-wsl-images.md`
**Status**: Plan 023 complete - all Tasks (0-5) done

Four-layer architecture for distributable team WSL images:

```
Layer 1: wsl-enterprise (module)     -- Company-wide base (system-cli + WSL)
Layer 2: wsl-dev-team (module)        -- Team dev stack (Podman, Claude Code, GitLab)
Layer 3: nixos-wsl-dev-team (host)   -- Thin host producing .wsl tarball
Layer 4: <personal-host> (host)      -- Personal machine (uses team layers + personal config)
```

**Key modules created**:
- `modules/system/settings/wsl-enterprise/` -- NixOS (`wsl-enterprise`) + HM (`home-enterprise`)
- `modules/system/settings/wsl-dev-team/` -- NixOS (`wsl-dev-team`) + HM (`home-dev-team`)
- `modules/hosts/nixos-wsl-dev-team [N]/` -- Distributable host config

**Design principles**:
- Layers are convenience bundles, not gatekeepers (no exclusivity)
- Dual-registration: each layer provides both NixOS and HM modules
- Generic user `dev` with `setup-username` script for personalization
- Tarball security check validates no personal data leaks
- Personal host refactored to import `wsl-dev-team` + personal-only modules (migrated to nixcfg-work)

**Build**: `nix build '.#nixosConfigurations.nixos-wsl-dev-team.config.system.build.tarballBuilder'`
**Run** (requires sudo): `sudo ./result/bin/nixos-wsl-tarball-builder`
**Import**: `wsl --import nixos-wsl-dev-team <location> nixos.wsl`

### ✅ **OpenCode Branch Validation** (COMPLETED - 2026-01-17)

**Branch**: `opencode` (merged into dendritic migration)
**Status**: Completed - now part of dendritic module structure

**Key Technical Fix** (rbw command syntax):
```nix
# Before (BROKEN): rbw get "ITEM" "FIELD"
# After (FIXED):   rbw get "ITEM" --field "FIELD"
```

**Current File Locations** (post-dendritic migration):
- `modules/lib/rbw.nix` - Bitwarden CLI helpers
- `modules/programs/claude-code/` - Claude Code dendritic module
- `modules/programs/opencode/` - OpenCode dendritic module
- `modules/flake-parts/lib.nix` - Preset configurations (claudeCode, openCode)

**SOPS Integration Plan**: `docs/claude-opencode-sops-integration-plan.md`

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

**Current Location**: `modules/programs/claude-code/_hm/skills/mikrotik-management/SKILL.md`

**Skill Version**: 2.2.0 (Local Design + Configuration Management)

**Network Configuration** (L1.0 ready to deploy):
```yaml
Bridge: bridge-attic (flat, no VLAN tagging)
Ports: ether1-ether8
Gateway: 10.0.0.1/24
DHCP Pool: 10.0.0.100-200
```

---

### ✅ **Plan 024: Terminal Fragment Integration** (COMPLETED - 2026-02-16)

**Branch**: `refactor/dendritic-pattern`
**Plan**: `.claude/user-plans/024-terminal-fragment-integration.md`
**Status**: All tasks complete — 21 commits

**Summary**: Import-NixOSWSL.ps1 creates Terminal fragment files to work around WSL bugs
(microsoft/WSL#13064, #13129, #13339) where `wsl --import` fails to create fragments.

**Key Discoveries**:
- Two-tier GUID system: Terminal's `WslDistroGenerator` (Tier 1) vs WSL's `Microsoft.WSL` (Tier 2)
- WSL Tier 2 namespace: `{BE9372FE-...}` + UTF-16LE(registryGuidString)
- Ghost profile root cause: `wsl --import` re-adds to state.json; orphan sweep needed post-import
- Tarball size: Mesa/LLVM (~800 MiB) unnecessary for CLI-only WSL; disabled via conditional override

**Tarball optimization** (commit `7743bc5`):
- `hardware.graphics.enable = lib.mkOverride 90 config.wsl-settings.cuda.enable;`
- Closure: 2.6 GiB → 1.8 GiB (31% reduction)
- CUDA auto-enables graphics + `wsl.useWindowsDriver` when `wsl-settings.cuda.enable = true`

**Source repos**: `~/src/terminal` (Tier 1), `~/src/WSL` (Tier 2)

---

### ✅ **System Monitoring Dashboard** (COMPLETED - 2026-04-05)

**Branch**: `feat/usb-jetson`
**Plan**: `.claude/user-plans/030-tmux-monitoring-dashboard.md`
**Status**: All T1-T8 complete. Deployed and validated.

**Module**: `modules/programs/monitoring/monitoring.nix` (dual HM + NixOS registration)

**Home Manager** (`monitoring.enable = true`):
- Tier 1: btop, bandwhich, sysstat (iostat/sar), iotop-c, nvtop, below, trippy
- Tier 2 (`enableTier2 = true`): gping, nload, dool, iftop
- btop: gruvbox_dark_v2 theme, iowait graphs, 2s interval, io_mode
- tmuxp dashboard: 4 windows (overview, io, network, extra)
- `monitor` launcher: creates/attaches to tmux session

**NixOS** (`monitoring.enable = true`):
- security.wrappers: bandwhich (cap_net_admin), iotop-c (cap_sys_ptrace), trip (cap_net_raw)
- Optional below daemon (`monitoring.below.enable`, off by default — WSL2 eBPF uncertain)
- Optional sysstat collection (`monitoring.sysstat.enable`, off by default)

**Quick start**: Run `monitor` to launch the dashboard.

**Commits**: `12327e8` (initial), `6d6c4e8` (YAML fix)

---

### ✅ **Plan 031b: Nix Guard flock→cgroup Migration** (COMPLETED - 2026-04-14)

**Branch**: `refactor/private-overlay`
**Status**: All T1-T11 complete. Commits: `5109df3`, `2ca5756`, `461d4db`, `71e512f`.

**What was done**: Replaced flock-based nix serialization (which caused fd-leak blocking
from long-lived daemons like mcp-nixos) with systemd cgroup memory limits.

- **T1-T3**: Wrapper rewritten to `systemd-run --user --scope`, nix-eval.slice deployed via HM
- **T4**: systemd-oomd + earlyoom enabled in system-default NixOS layer
- **T5**: Removed NIX_NO_GUARD=1 workaround from mcp-server-defs.nix
- **T6**: Updated docs + CLAUDE.md
- **T7**: Concurrent eval test — both scopes created, cgroup OOM killed correctly (exit 137)
- **T8**: No fd-leak blocking — consecutive commands in 0.1s
- **T9**: NIX_NO_GUARD=1 bypass verified
- **T10**: Graceful fallback verified (invalid DBUS/XDG_RUNTIME_DIR)
- **T11**: Removed /tmp/nix-eval-guard.lock, updated flock-era comments

**WSL fix**: NixOS-WSL hardcodes `oomd.enable = false` — overridden with mkForce in
`modules/system/settings/wsl/wsl.nix`. Upstream PR branch: `fix/oomd-psi-available` at
`~/src/NixOS-WSL` (changes bare `false` → `lib.mkDefault false`).

### ✅ **Plan 031: Claude Code ↔ OpenCode Nix Module Parity** (COMPLETED - 2026-04-06)

**Branch**: `feat/usb-jetson`
**Status**: All T0-T9 complete. Commit `0e83352`.

**What was done**:
- **T0**: Package version overlays — claude-code 2.1.87, opencode 1.3.2 via pinned nixpkgs
- **T1**: Feature comparison document at `docs/ai-tool-feature-comparison.md`
- **T2**: File-based command deployment sub-module (`_hm/file-commands.nix`) + `/plans` command
- **T3**: Agent file deployment sub-module (`_hm/agent-files.nix`)
- **T4**: Skill configuration & deployment sub-module (`_hm/skills.nix`)
- **T5**: Fixed compaction serialization (options existed but were not in JSON output)
- **T6**: Added `cliMcpServer` to OC MCP server options (parity with CC)
- **T7**: Instruction content audit — shared lib already comprehensive, no gaps
- **T8**: Updated lib.nix presets + all 6 host configs + wsl-dev-team
- **T9**: Validation passed — `nix flake check --no-build` + HM dry-run

**OC module structure after**:
```
modules/programs/opencode/
├── opencode.nix              # Core (3 new imports, skills/compaction in JSON)
└── _hm/
    ├── mcp-servers.nix       # +cliMcpServer
    ├── file-commands.nix     # NEW
    ├── agent-files.nix       # NEW
    ├── skills.nix            # NEW (shares CC's adr-writer skill files)
    └── commands/planning/
        └── plans.md          # NEW
```

---

### 🚧 **USB/IP + Jetson Orin Nano Development** (IN PROGRESS)

**Branch**: `feat/usb-jetson`
**Status**: USB infrastructure complete, CI/CD + nixos-dev-team config added (2026-03-14)

**What's implemented locally** (15 commits on branch):
- `wsl-settings.usbip` options in `modules/system/settings/wsl/wsl.nix` (enable, autoAttach, snippetIpAddress)
- Activation script checking for `usbipd.exe` on Windows side (with corrected PATH)
- Jetson Recovery Mode (APX) udev rule: VID:0955 PID:7523 (active)
- Jetson L4T running udev rule: VID:0955 PID:7020 (commented out, needs verification)
- `usbip.autoAttach = [ ]` placeholder in personal host config (migrated to nixcfg-work)
- `usbutils` + `kmod` in dev-team layer
- WSL environment capture for systemd-spawned shells
- `wsl-recover-mounts` script with 4 trigger points (boot, switch, shell, devshell)
- `restart-usb` + `restart-usb-v4.ps1` recovery scripts
- GitHub Actions CI/CD pipeline (ci.yml + release.yml) with versioned releases
- Pure NixOS `nixos-dev-team` host module (non-WSL, system-cli + binfmt + podman)
- Tarball builder eval tests for all 3 WSL configs
- VM test `vm-dev-team-stack` for the non-WSL dev-team config

**Windows-side confirmed working** (2026-03-14):
- usbipd-win v5.3.0 installed, policy configured for non-admin attach
- Manual `usbipd attach --wsl --hardware-id VID:PID --auto-attach` works
- Devices: FTDI USB-UART (0403:6001), Jetson APX (0955:7523)

**Upstream contribution opportunity** (HIGH PRIORITY):
NixOS-WSL's `modules/usbip.nix` is outdated — fetches `auto-attach.sh` from usbipd-win
v4.2.0 (removed in v5.3.0). Module needs modernization for v5.x + hardware-ID auto-attach.
Full research documented in `docs/NIXOS-WSL-BARE-MOUNT-CONTRIBUTION-PLAN.md` under
"usbip.nix: Modernize for usbipd-win v5.x + hardware-ID auto-attach".

**Remaining work**:
1. Implement `autoAttachByHardwareId` locally in `wsl.nix` + dev-team module (interim)
2. Prepare upstream PR for NixOS-WSL `modules/usbip.nix` modernization
3. Verify Jetson L4T PID 7020 when hardware boots into Linux
4. Jetson flashing workflow (sdkmanager or initrd flash via WSL)

---

### 🔧 **Pending Tasks**

#### ✅ **OpenCode Vision Support Configuration** (COMPLETED - 2026-01-20)

**Status**: Merged into dendritic migration

**Solution** (vision modalities for custom models):
```nix
modalities = {
  input = [ "text" "image" ];
  output = [ "text" ];
};
```

**Current location**: `modules/flake-parts/lib.nix` (openCode.workProvider)

**Key Learning**: OpenCode custom models require explicit `modalities` declarations

---

### ✅ **DrawIO/Diagram Skill WSL2 Fix** (RESOLVED - 2026-02-02)

**Branch**: `wsl2-fix` in `~/src/drawio-svg-sync`
**Status**: COMPLETE - root cause was invalid test fixtures, NOT a drawio/WSL2/GPU issue

**Root Cause**: Test fixtures contained invalid compressed data. Draw.io compression format is `URL encode → raw deflate → Base64`. The fixtures were created with invalid/corrupted compression.

**Resolution** (commit `2764f26`):
- Regenerated all test fixtures with valid draw.io compression
- Added `scripts/regenerate-fixtures.py` for future fixture creation
- Smart display detection (commit `8cd5e88`) still provides WSLg optimization

**Key Finding**: GPU/Vulkan warnings in WSL2 are **cosmetic** - exports succeed despite errors.

**Future Work** (in drawio-svg-sync repo):
- TASK:FUTURE-1: Add fixture validation in CI
- TASK:FUTURE-2: Document compression format
- TASK:FUTURE-3: Add real-file round-trip tests
- TASK:FUTURE-4: Add compression validation function

**Related**: nixcfg Plan 016 (diagram skill) is now UNBLOCKED.

---

### 🚧 **Deferred Tasks**

#### **Fork Development Work** (DEFERRED)
**Status**: On hold pending git-worktree-superproject implementation

**Active Forks Requiring Upstream Coordination**:
1. **nixpkgs** (`writers-auto-detection` branch): autoWriter implementation
2. **home-manager** (custom fork): autoValidate + fcitx5 fixes
3. **NixOS-WSL** (`plugin-shim-integration` branch): VSOCK + bare mount

#### **Claude Code Upstream Contributions** (PLANNED)
**Location**: `modules/programs/claude-code/_hm/` (create UPSTREAM-CONTRIBUTION-PLAN.md when ready)
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
