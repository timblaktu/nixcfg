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

### 🔨 **In Progress: Cross-Platform Architecture Planning** (2025-12-15)
**Branch**: `refactor/consolidate-wsl-config` (pending doc fixes before merge)
**Goal**: Design comprehensive platform support strategy for colleague sharing

**Context**: Recent WSL consolidation work (templates, base modules) is just ONE slice of a larger cross-platform vision. Need to ensure nixcfg provides solid foundation for extracting shareable components to separate flake repo(s).

**Platform Support Matrix**:
| Host Platform | Native nix develop | NixOS VM | Current Status |
|--------------|-------------------|-----------|----------------|
| Bare-metal Linux (x86_64, aarch64) | ✅ Excellent | ✅ Native KVM/QEMU | ✅ Working |
| Windows 11 + WSL2 (x86_64) | ✅ Via WSL | ✅ QEMU in WSL | ✅ Consolidated (recent work) |
| macOS Darwin (M3-4 aarch64) | ⚠️ Lagging/broken | ✅ Fallback option | 🟡 Template exists, needs VM config |

**Deployment Mode Decision Tree**:
- **Use nix develop when**: Fast iteration needed, CI/CD pipelines, lightweight tooling, host integration desired
- **Use NixOS VM when**: Full system isolation needed, Darwin workarounds required, consistent test environments, reproducible builds at OS level

**Architecture Phases**:
1. ✅ **WSL Consolidation** - Templates + base modules for WSL scenarios (DONE, pending doc fixes)
2. 📍 **Cross-Platform Documentation** - Platform matrix, decision tree, VM architecture (CURRENT)
3. 🔜 **NixOS VM Configurations** - Generic VMs for all platforms (headless + GUI variants, x86_64 + aarch64)
4. 🔜 **Extraction Planning** - Identify shareable vs personal components, design shared flake structure
5. 🔜 **Shared Flake Creation** - New repo with extracted components, colleague testing

**Key Architectural Insights**:
- **Layered Modularity**: Platform-agnostic base → Platform adapters → Personal configs → Colleague configs
- **Two Distinct WSL Scenarios**: NixOS-WSL (full distro) vs Home Manager on vanilla WSL (portable)
- **Hybrid Image Strategy**: Pre-built images for bootstrapping (WSL tarball CRITICAL) + live building for iteration
- **Image Matrix Building**: One config → multiple formats (WSL tarball, qcow2, ISO, Docker) via nixos-generators
- **CI/CD Consideration**: Dev shells must work headless on GitHub Actions (Linux x86_64, macOS Intel/Apple Silicon)

**Previous WSL Work** (2025-12-13):
- Templates committed (22aae74)
- Base modules generalized (6d81a00)
- `nix flake check` passes
- Review identified documentation fixes needed (see review findings below)

**Next**: Apply documentation fixes, update ARCHITECTURE.md with platform matrix, then merge to main

#### 📋 **REVIEW FINDINGS** (2025-12-13)

**Overall Grade**: Good - code works, documentation has naming inconsistencies

##### 🔴 CRITICAL: Naming Inconsistency in Documentation
The Home Manager module is exported as `homeManagerModules.wsl-home-base` but several docs incorrectly reference `homeManagerModules.wsl-base`:

| File | Line | Status |
|------|------|--------|
| `docs/CONSOLIDATION-PLAN.md` | 93 | ❌ Uses `wsl-base` |
| `docs/ARCHITECTURE.md` | 984, 1088 | ❌ Uses `wsl-base` |
| `docs/CONSOLIDATION-VALIDATION-REPORT.md` | 151 | ❌ Uses `wsl-base` |

##### 🟡 BUG: Darwin template hardcodes x86_64
`templates/darwin/flake.nix:50` hardcodes `x86_64-darwin` in systemPackages despite supporting Apple Silicon.

##### 🟡 OPPORTUNITY: tim@thinky-ubuntu doesn't use wsl-home-base
Could benefit from shared module instead of manual WSL config duplication.

##### 🟢 HARMLESS WARNING
`warning: unknown flake output 'homeManagerModules'` - flake-parts doesn't recognize this output but module works correctly.

#### 🎯 **ARCHITECTURAL INSIGHT**

**Key Finding**: TWO distinct WSL scenarios with different module requirements:

1. **NixOS-WSL** (`hosts/common/wsl-base.nix`) - NixOS system module
   - Requires: Full NixOS-WSL distribution
   - **Cannot work on vanilla Ubuntu/Debian/Alpine WSL**

2. **Home Manager on ANY WSL** (`home/common/wsl-home-base.nix`) - Home Manager module
   - Requires: ANY WSL distro + Nix + home-manager
   - **Works on NixOS-WSL AND vanilla Ubuntu/Debian/Alpine WSL** ✅

**Critical for Sharing**: Colleagues on vanilla WSL can use `homeManagerModules.wsl-home-base` but NOT `nixosModules.wsl-base`

For completed work history, see git log on `dev` and `main` branches.

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
