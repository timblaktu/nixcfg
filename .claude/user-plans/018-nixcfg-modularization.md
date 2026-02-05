# Plan 018: Nixcfg Modularization for Team Sharing

**Status**: DESIGN PHASE
**Branch**: `opencode`
**Created**: 2026-02-01
**Last Updated**: 2026-02-01

---

## Overview

Refactor the nixcfg repository to extract reusable components into shareable flake inputs, enabling teammates to adopt Nix-based developer shells, Claude/OpenCode tooling, and other infrastructure without inheriting personal configuration.

**Goal**: Transform from monolithic personal config → composable library + personal config that imports it.

---

## Progress Tracking

| Phase | Task | Status | Date |
|-------|------|--------|------|
| **0** | **Design Discovery** | | |
| 0.1 | Audience and scope | `TASK:COMPLETE` | 2026-02-01 |
| 0.2 | Extraction priorities | `TASK:COMPLETE` | 2026-02-01 |
| 0.3 | Architecture decision | `TASK:COMPLETE` | 2026-02-01 |
| — | **SESSION BOUNDARY** | | |
| 0.4 | Naming conventions | `TASK:COMPLETE` | 2026-02-01 |
| 0.5 | Design sign-off | `TASK:PENDING` | |
| — | **SESSION BOUNDARY** | | |
| **1** | **Foundation** | | |
| 1.1 | Create shared flake | `TASK:PENDING` | |
| 1.2 | Extract MCP servers | `TASK:PENDING` | |
| — | **SESSION BOUNDARY** | | |
| 1.3 | Extract secrets helpers | `TASK:PENDING` | |
| 1.4 | Validate: import into nixcfg | `TASK:PENDING` | |
| — | **SESSION BOUNDARY** | | |
| **2** | **Modules** | | |
| 2.1 | Extract Claude Code | `TASK:PENDING` | |
| — | **SESSION BOUNDARY** | | |
| 2.2 | Extract OpenCode | `TASK:PENDING` | |
| — | **SESSION BOUNDARY** | | |
| 2.3 | Extract dev shells | `TASK:PENDING` | |
| 2.4 | Validate: home-manager switch | `TASK:PENDING` | |
| — | **SESSION BOUNDARY** | | |
| **3** | **Documentation** | | |
| 3.1 | Getting-started guide | `TASK:PENDING` | |
| 3.2 | Customization docs | `TASK:PENDING` | |
| 3.3 | Example flake | `TASK:PENDING` | |
| — | **SESSION BOUNDARY** | | |
| **4** | **WSL Image Distribution** | | |
| 4.1 | Create nix-wsl-builder repo | `TASK:PENDING` | |
| 4.2 | Extract wsl-common module | `TASK:PENDING` | |
| — | **SESSION BOUNDARY** | | |
| 4.3 | Extract wsl-tarball-checks | `TASK:PENDING` | |
| 4.4 | Add CI/CD for tarball builds | `TASK:PENDING` | |
| — | **SESSION BOUNDARY** | | |
| 4.5 | Create dev-team configuration | `TASK:PENDING` | |
| 4.6 | WSL onboarding documentation | `TASK:PENDING` | | |

---

## Phase 0: Design Discovery

### Task 0.1: Identify Sharing Scope and Audience

**Status**: `TASK:COMPLETE` (2026-02-01)

**Answers**:

| Question | Answer |
|----------|--------|
| Audience | Work teammates + eventual open source |
| Nix level | Beginners |
| Existing config | Starting fresh |
| Platforms | All: NixOS-WSL, macOS, Linux, WSL |
| Visibility | Split (some private, some public) |
| AI tools | Full modules + skills + all MCP servers |
| Namespace | Shadow upstream (programs.claude-code) |

**Delivery Model**:
- NixOS-WSL machines for opinionated users
- Nix-only solutions for macOS/Linux users
- Dev shells for all platforms
- Claude/OpenCode tooling for AI workflows

**Architecture Preference**: Option C (two repos)
- Public repo with shared components
- Private nixcfg imports public repo as flake input
- Both user and teammates consume same shared code

**Public/Private Audit Summary**:

| Tier | Content | Action |
|------|---------|--------|
| 1 | flake-modules, pkgs, overlays | Publish as-is |
| 2 | claude/opencode modules | Redact names |
| 3 | nixos auth modules | Rework first |
| 4 | secrets, hosts | Never publish |

---

### Task 0.2: Catalog Extraction Candidates with Priorities

**Status**: `TASK:COMPLETE` (2026-02-01)

**Purpose**: Prioritize what to extract first based on Task 0.1 answers.

**Current Candidate Inventory** (from codebase analysis):

| Component | Location | LOC | Reusability | Complexity |
|-----------|----------|-----|-------------|------------|
| MCP server definitions | `shared/mcp-server-defs.nix` | 6632 | HIGH | LOW |
| Wrapper script library | `claude-code/lib.nix` | 238 | HIGH | LOW |
| Claude Code module | `claude-code.nix` + submodules | 4681 | HIGH | MEDIUM |
| OpenCode module | `opencode.nix` + submodules | 8338 | HIGH | MEDIUM |
| Secrets helpers | `secrets-management.nix` | 235 | MEDIUM | LOW |
| GitHub auth | `github-auth.nix` | 495 | MEDIUM | LOW |
| Dev shell | `flake-modules/dev-shells.nix` | 102 | MEDIUM | LOW |
| Test infrastructure | `flake-modules/tests.nix` | 779 | MEDIUM | HIGH |
| AI instructions | `shared/ai-instructions.nix` | 3878 | LOW | LOW |
| Skills | `claude-code/skills/` | ~5000 | LOW | MEDIUM |

**Priority Decision** (based on Task 0.1: beginners, fresh start, want AI tools):

| Priority | Component | Rationale |
|----------|-----------|-----------|
| **P0** | MCP server definitions | Foundation for both Claude and OpenCode; teammates explicitly want this |
| **P0** | Wrapper script library | Core building block; enables account switching without full module |
| **P1** | Claude Code module | Primary AI tool; high teammate demand |
| **P1** | OpenCode module | Alternative AI tool; shares MCP infrastructure |
| **P2** | Dev shells | Nice-to-have; teammates can use simple `nix develop` without this |
| **P3** | Secrets helpers | Only needed if using rbw/SOPS; beginners may use env vars instead |
| **P3** | GitHub auth | Can be simplified; not core to AI workflow |
| **SKIP** | AI instructions | Too personal; teammates should write their own CLAUDE.md |
| **SKIP** | Skills | Too specialized (mikrotik, diagram); offer as opt-in examples |
| **SKIP** | Test infrastructure | Internal; not needed by consumers |

**Minimum Viable Extraction (MVE)**:
- P0 components only: MCP servers + wrapper library
- Provides: `lib.mkMcpServer`, `lib.mkClaudeWrapper`, server definitions
- Enables: basic Claude Code with MCP servers, without full module complexity
- Complexity: LOW (library functions, no module options)

**Full Extraction Target**:
- P0 + P1: MCP servers + wrapper library + Claude/OpenCode modules
- Provides: `programs.claude-code.enable = true` experience
- Enables: multi-account, hooks, statusline, all features
- Complexity: MEDIUM (module options, but well-documented)

**Components NOT Shared**:
- Personal CLAUDE.md content (ai-instructions.nix)
- Custom skills (mikrotik-management, diagram)
- hosts/* and secrets/* (obviously)
- home/common/* (too personal: aliases, zsh config, etc.)

**Deliverable**: ✅ Prioritized extraction list with rationale

---

### Task 0.3: Define Flake Architecture

**Status**: `TASK:COMPLETE` (2026-02-01)

**Purpose**: Decide HOW to organize extracted components.

**Architecture Decision**: **Option A (Single Library Flake)** with modular internal structure

**Rationale**:
- Task 0.1 indicated Option C preference (public shared + private nixcfg)
- However, splitting library vs modules into two repos adds coordination overhead
- A single repo with good internal modularity achieves the same goals:
  - Public shared repo for teammates
  - Private nixcfg imports it as single flake input
  - Beginners only need one import to learn

**Chosen Structure**:

```
github.com/timblaktu/nix-ai-dev/
├── flake.nix                    # Main entry point
├── lib/
│   ├── default.nix              # lib.ai-dev.* namespace
│   ├── mcp-servers.nix          # mkMcpServer, server definitions
│   └── wrappers.nix             # mkClaudeWrapper, account helpers
├── modules/
│   ├── home-manager/
│   │   ├── claude-code/         # programs.claude-code module
│   │   └── opencode/            # programs.opencode module
│   └── nixos/                   # Future: system-level modules
├── templates/
│   ├── minimal/                 # Just lib functions
│   ├── home-manager/            # Full HM integration
│   └── flake-parts/             # For existing flake-parts users
├── examples/
│   ├── simple-claude.nix        # Single account, basic config
│   ├── multi-account.nix        # Max/Pro/Work pattern
│   └── with-mcp-servers.nix     # Custom MCP server setup
└── docs/
    ├── getting-started.md
    ├── customization.md
    └── architecture.md
```

**Flake Outputs**:

```nix
{
  # Library functions (no home-manager required)
  lib.ai-dev = {
    mkMcpServer = ...;
    mkClaudeWrapper = ...;
    mcpServers = { nixos = ...; context7 = ...; };
  };

  # Home Manager modules
  homeManagerModules = {
    claude-code = ./modules/home-manager/claude-code;
    opencode = ./modules/home-manager/opencode;
    default = { ... }: {
      imports = [ self.homeManagerModules.claude-code ];
    };
  };

  # Templates for new users
  templates = {
    minimal = { ... };
    home-manager = { ... };
    flake-parts = { ... };
  };

  # Overlay for custom packages
  overlays.default = final: prev: { ... };
}
```

**Consumer Usage Examples**:

```nix
# Minimal: just library functions
{
  inputs.ai-dev.url = "github:timblaktu/nix-ai-dev";
  outputs = { ai-dev, ... }: {
    # Use lib directly
    myWrapper = ai-dev.lib.ai-dev.mkClaudeWrapper { ... };
  };
}

# Full: Home Manager module
{
  inputs.ai-dev.url = "github:timblaktu/nix-ai-dev";
  outputs = { ai-dev, home-manager, ... }: {
    homeConfigurations.user = home-manager.lib.homeManagerConfiguration {
      modules = [
        ai-dev.homeManagerModules.claude-code
        {
          programs.claude-code.enable = true;
          programs.claude-code.accounts.default = { ... };
        }
      ];
    };
  };
}
```

**Version Strategy**:
- **Rolling** (always use main) for teammates during development
- **Tags** for stable releases (v1.0.0, v1.1.0) when ready
- **No nixpkgs coupling** - works with any nixpkgs version

**Migration Path for nixcfg**:
1. Create `github.com/timblaktu/nix-ai-dev` repo
2. Extract P0 components (MCP servers, wrapper lib)
3. Add as flake input to nixcfg: `ai-dev.url = "github:timblaktu/nix-ai-dev";`
4. Refactor nixcfg to import from ai-dev instead of local paths
5. Gradually move P1 components (modules)

**Deliverable**: ✅ Architecture decision with rationale

---

### Task 0.4: Establish Naming Conventions and Namespaces

**Status**: `TASK:COMPLETE` (2026-02-01)

**Purpose**: Define consistent naming for extracted components.

**Current Namespaces in nixcfg**:
- `programs.claude-code.*` (shadows upstream, uses `disabledModules`)
- `programs.opencode.*` (shadows upstream)
- `homeBase.*` (personal config options)

**Decision Summary**:

#### Q1: Module Namespaces

**Choice**: Keep `programs.claude-code` and `programs.opencode` (shadow upstream)

**Rationale**:
- Upstream compatibility: consumers can switch between our module and upstream easily
- Option familiarity: users already know `programs.claude-code.enable = true`
- Superset design: our module provides ALL upstream options plus enhancements
- Documentation: upstream docs still apply for basic usage

**Trade-off Accepted**:
- Consumers MUST use `disabledModules` to shadow upstream
- Our module docs must explain this clearly
- We commit to maintaining option compatibility with upstream

**Consumer Pattern**:
```nix
# Consumer's home.nix
{ ... }: {
  disabledModules = [ "programs/claude-code.nix" ];
  imports = [ inputs.ai-dev.homeManagerModules.claude-code ];

  programs.claude-code = {
    enable = true;
    accounts.default = { ... };  # Our extension
  };
}
```

#### Q2: Library Function Naming

**Choice**: `lib.ai-dev.*` namespace with descriptive function names

**Structure**:
```nix
lib.ai-dev = {
  # MCP server helpers
  mkMcpServer = { ... }: { ... };
  mcpServers = {
    nixos = mkMcpServer { ... };
    context7 = mkMcpServer { ... };
    sequentialThinking = mkMcpServer { ... };
    # ...
  };

  # Wrapper helpers
  mkClaudeWrapper = { ... }: { ... };
  mkOpenCodeWrapper = { ... }: { ... };

  # Secrets helpers (P3)
  secrets = {
    mkRbwCommand = { ... }: { ... };
    mkSopsSecret = { ... }: { ... };
  };
};
```

**Rationale**:
- `ai-dev` matches repo name (nix-ai-dev)
- Flat namespace is simpler than deeply nested (`lib.claude.mcp.mkServer`)
- Descriptive function names (`mkClaudeWrapper` not just `mkWrapper`)
- Grouped by concern (`mcpServers.*`, `secrets.*`)

#### Q3: Flake Output Naming

**Chosen Structure**:
```nix
{
  # Follows home-manager convention
  homeManagerModules = {
    claude-code = ./modules/home-manager/claude-code;
    opencode = ./modules/home-manager/opencode;
    default = self.homeManagerModules.claude-code;
  };

  # Library under flake lib output
  lib.ai-dev = { ... };  # NOT lib.claude-code

  # Overlay for any custom packages
  overlays.default = final: prev: { ... };

  # Templates for beginners
  templates = {
    minimal = { path = ./templates/minimal; description = "Library-only usage"; };
    home-manager = { path = ./templates/home-manager; description = "Full HM module"; };
  };
}
```

**Rationale**:
- `homeManagerModules` matches home-manager flake convention
- `lib.ai-dev` avoids conflict with `lib.claude-code` (could be confusing)
- `overlays.default` is standard pattern
- Templates provide copy-paste starting points

#### Internal Naming Conventions

**File Naming**:
- Kebab-case for directories: `home-manager/`, `mcp-servers/`
- Kebab-case for files: `claude-code.nix`, `mcp-server-defs.nix`
- Exception: `lib.nix`, `default.nix` (Nix conventions)

**Option Naming**:
- camelCase for option names: `enableMcpIntegration`, `defaultModel`
- Matches upstream home-manager patterns
- Matches current nixcfg patterns

**Internal Variable Naming**:
- `cfg = config.programs.claude-code` (standard pattern)
- Descriptive let bindings: `mcpServerConfig`, `wrapperScript`

**Deliverable**: ✅ Naming convention document complete

---

### Task 0.5: Design Discussion Sign-Off

**Status**: `TASK:PENDING`

**Purpose**: Confirm design decisions before implementation.

**Sign-off Checklist**:
- [x] Audience and scope defined (0.1)
- [x] Extraction priorities set (0.2)
- [x] Architecture chosen (0.3)
- [x] Naming conventions established (0.4)
- [ ] User approves proceeding to Phase 1

**Design Summary for Review**:

| Decision | Choice |
|----------|--------|
| **Target Audience** | Work teammates (Nix beginners) + eventual open source |
| **Repo Structure** | Single flake: `github.com/timblaktu/nix-ai-dev` |
| **P0 Extraction** | MCP server defs + wrapper library |
| **P1 Extraction** | Claude Code + OpenCode modules |
| **Module Namespace** | `programs.claude-code` (shadow upstream with disabledModules) |
| **Library Namespace** | `lib.ai-dev.*` |
| **Flake Outputs** | `homeManagerModules.{claude-code,opencode}`, `lib.ai-dev`, `templates.*` |

**User Action Required**: Review decisions above and confirm to proceed to Phase 1 (Foundation).

---

## Phase 1: Foundation Extraction

*(Tasks defined after Phase 0 completion)*

### Task 1.1: Create Shared Library Flake Structure

**Status**: `TASK:PENDING`

**Depends On**: Tasks 0.1-0.5

**Scope**: TBD based on architecture decision

---

### Task 1.2: Extract MCP Server Definitions

**Status**: `TASK:PENDING`

**Current Location**: `home/modules/shared/mcp-server-defs.nix` (6632 LOC)

**Extraction Notes**:
- `mkMcpServer` helper function
- Individual server definitions (nixos, sequentialThinking, context7, etc.)
- Currently used by both claude-code and opencode modules

---

### Task 1.3: Extract Secrets Management Helpers

**Status**: `TASK:PENDING`

**Current Locations**:
- `home/modules/secrets-management.nix` (235 LOC)
- `home/modules/github-auth.nix` (495 LOC)
- `home/modules/claude-code/lib.nix` (rbw commands)

**Extraction Notes**:
- rbw (Bitwarden CLI) integration
- SOPS-nix patterns
- GitHub/GitLab token retrieval

---

### Task 1.4: Validation - Import Library into nixcfg

**Status**: `TASK:PENDING`

**Purpose**: Prove extraction works by consuming it in original repo.

**Success Criteria**:
- nixcfg imports extracted library as flake input
- `nix flake check` passes
- `home-manager switch` succeeds
- No functionality regression

---

## Phase 2: Module Extraction

*(Tasks defined after Phase 1 completion)*

---

## Phase 3: Documentation & Onboarding

*(Tasks defined after Phase 2 completion)*

---

## Phase 4: WSL Image Distribution Infrastructure

**Purpose**: Enable automated building and distribution of pre-configured NixOS-WSL tarballs for team onboarding.

**Architecture Decision**: Separate `nix-wsl-builder` repository (not bundled with nix-ai-dev)

**Rationale**:
- Clear separation between AI tooling and infrastructure
- Focused scope for WSL-specific concerns
- Independent release cycle for WSL images
- Teammates who want WSL images may not want AI tooling (and vice versa)

### Task 4.1: Create nix-wsl-builder Repository

**Status**: `TASK:PENDING`

**Scope**: Initialize new repository with flake structure

**Target Structure**:
```
github.com/timblaktu/nix-wsl-builder/
├── flake.nix
├── lib/
│   ├── default.nix
│   └── tarball.nix           # mkWslConfiguration helper
├── modules/
│   ├── wsl-common.nix        # Extracted from nixcfg
│   ├── wsl-tarball-checks.nix
│   └── wsl-cuda.nix          # Optional CUDA support
├── configurations/
│   ├── minimal.nix           # Generic distribution config
│   └── dev-team.nix          # Team's opinionated config
├── templates/
│   └── basic/                # Simple WSL NixOS config
└── docs/
    └── getting-started.md
```

**Flake Outputs**:
```nix
{
  nixosModules = {
    wsl-common = ./modules/wsl-common.nix;
    wsl-tarball-checks = ./modules/wsl-tarball-checks.nix;
    wsl-cuda = ./modules/wsl-cuda.nix;
  };

  nixosConfigurations = {
    minimal = ...;
    dev-team = ...;
  };

  packages.x86_64-linux = {
    tarball-minimal = ...;
    tarball-dev-team = ...;
  };

  templates.basic = { ... };
}
```

**Definition of Done**:
- [ ] Repository created on GitHub
- [ ] Basic flake.nix with nixos-wsl input
- [ ] Empty module structure in place
- [ ] `nix flake check` passes

---

### Task 4.2: Extract wsl-common Module

**Status**: `TASK:PENDING`

**Current Location**: `modules/wsl-common.nix` (143 LOC)

**Extraction Notes**:
- Parameterized options for hostname, defaultUser, interop settings
- SSH configuration
- Windows PATH integration
- Runtime assertions for validation

**Definition of Done**:
- [ ] Module copied to nix-wsl-builder
- [ ] Any nixcfg-specific references removed
- [ ] Test configuration using extracted module
- [ ] `nix flake check` passes

---

### Task 4.3: Extract wsl-tarball-checks Module

**Status**: `TASK:PENDING`

**Current Location**: `modules/wsl-tarball-checks.nix`

**Extraction Notes**:
- Security validation for distribution tarballs
- Personal identifier detection
- Sensitive environment variable checking
- Bypass mechanism for development

**Definition of Done**:
- [ ] Module copied to nix-wsl-builder
- [ ] Configurable personal identifiers (not hardcoded)
- [ ] Test security check script generation
- [ ] `nix flake check` passes

---

### Task 4.4: Add CI/CD for Tarball Builds

**Status**: `TASK:PENDING`

**Scope**: GitHub Actions workflow for automated tarball building

**Workflow Design**:
```yaml
name: Build WSL Tarballs
on:
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      configuration:
        description: 'Configuration to build'
        required: true
        default: 'minimal'
        type: choice
        options: [minimal, dev-team]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: DeterminateSystems/nix-installer-action@v9
      - uses: DeterminateSystems/magic-nix-cache-action@v2
      - name: Build tarball
        run: nix build .#tarball-${{ inputs.configuration }}
      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: nixos-wsl-${{ inputs.configuration }}
          path: result/nixos.wsl
```

**Definition of Done**:
- [ ] Workflow file created
- [ ] Manual trigger works
- [ ] Tag-based releases work
- [ ] Artifacts downloadable from Actions

---

### Task 4.5: Create dev-team Configuration

**Status**: `TASK:PENDING`

**Scope**: Opinionated NixOS-WSL configuration for your team

**Configuration Features**:
- Standard dev tools (git, vim, curl, htop)
- Nix flakes enabled
- Optional: CUDA support
- Optional: Import nix-ai-dev for Claude/OpenCode tooling
- Generic user setup (teammates customize after import)

**Definition of Done**:
- [ ] Configuration builds successfully
- [ ] Tarball imports into WSL
- [ ] Basic functionality verified
- [ ] Documentation for customization

---

### Task 4.6: WSL Onboarding Documentation

**Status**: `TASK:PENDING`

**Scope**: Getting-started guide for teammates

**Content Outline**:
1. Prerequisites (Windows 11, WSL2 enabled)
2. Download tarball from GitHub releases
3. Import into WSL: `wsl --import NixOS C:\wsl\NixOS .\nixos.wsl`
4. First login and password change
5. Customization options
6. Upgrading to newer releases

**Definition of Done**:
- [ ] docs/getting-started.md complete
- [ ] Tested by someone unfamiliar with NixOS
- [ ] Screenshots/examples included

---

## Design Session Log

*(Record outcomes of each design discussion session here)*

### Session 1 (2026-02-01): Initial Plan Creation

**Topics**: Repository structure analysis, extraction candidate identification

**Codebase Analysis Summary**:

```
nixcfg structure:
├── flake-modules/     # 9 files, 1736 LOC (flake-parts outputs)
├── home/modules/      # 21 files, ~4700 LOC (Home Manager modules)
├── home/common/       # 13 files, ~190 KB (shared home config)
├── modules/           # 16 files (NixOS/HM mixins)
├── pkgs/              # 4 custom packages
└── overlays/          # 2 overlay files
```

**Key Findings**:
1. Already has good separation: `shared/` directory with MCP defs and AI instructions
2. Multi-account pattern well-designed in both claude-code and opencode
3. `disabledModules` pattern used to shadow upstream modules
4. Library functions isolated in `lib.nix` files
5. Repeated patterns could be abstracted (account module type, secrets access)

**Identified Extraction Tiers**:

| Tier | Components | Rationale |
|------|------------|-----------|
| 1 (High) | MCP servers, wrapper lib, account module pattern | Already library-like, high reuse |
| 2 (Medium) | Secrets helpers, dev shells, test infra | Useful but needs abstraction |
| 3 (Low) | Personal configs (nixvim, tmux, zsh) | Too customized for generic use |

**Next Session**: Answer Task 0.1 questions (audience, scope)

---

### Session 2 (2026-02-04): WSL Builder Research & Phase 4 Design

**Topics**: NixOS WSL build capabilities research, Phase 4 task definition

**Branch**: `research/nixos-wsl-build` (worktree: `/home/tim/src/nixcfg-wsl-research`)

**Research Findings**:

1. **NixOS-WSL is the primary mechanism** for building WSL tarballs
   - `system.build.tarballBuilder` attribute
   - Supports `--extra-files` and `--chown` options
   - Requires sudo for tarball creation

2. **nixos-generators does NOT support WSL format**
   - 32 formats available, but no WSL
   - WSL requires specific boot config that NixOS-WSL handles internally

3. **Current nixcfg already has working infrastructure**
   - `nixos-wsl-minimal` configuration for generic distribution
   - `wsl-tarball-checks.nix` for security validation
   - `wsl-common.nix` with parameterized options (143 LOC)

**Architecture Decision**: Separate `nix-wsl-builder` repository

**Rationale**:
- Clear separation between AI tooling (nix-ai-dev) and infrastructure
- Focused scope for WSL-specific concerns
- Independent release cycle for WSL images
- Teammates can use WSL images without AI tooling

**Artifacts Created**:
- `docs/NIXOS-WSL-BUILD-CAPABILITIES.md` - Comprehensive research documentation
- Phase 4 tasks added to this plan (6 tasks with definitions of done)

**Next Session**: Begin Task 4.1 (create nix-wsl-builder repo) or continue with Phase 0.5 sign-off

---

## Reference: Current Repository Structure

```
nixcfg/
├── flake.nix                           # Main entry (flake-parts)
├── flake-modules/
│   ├── systems.nix                     # x86_64-linux, aarch64-linux
│   ├── overlays.nix                    # Custom overlays
│   ├── packages.nix                    # Custom packages
│   ├── dev-shells.nix                  # Development environments
│   ├── home-configurations.nix         # 5 home-manager configs
│   ├── nixos-configurations.nix        # NixOS systems
│   ├── darwin-configurations.nix       # macOS systems
│   ├── termux-outputs.nix              # Termux scripts
│   ├── tests.nix                       # Test suite
│   └── github-actions.nix              # CI/CD
├── home/
│   ├── modules/
│   │   ├── base.nix                    # Root module (735 LOC)
│   │   ├── claude-code.nix             # Claude wrapper (866 LOC)
│   │   ├── claude-code/                # Submodules (3815 LOC)
│   │   ├── opencode.nix                # OpenCode wrapper (708 LOC)
│   │   ├── opencode/                   # Submodules (7630 LOC)
│   │   ├── shared/
│   │   │   ├── mcp-server-defs.nix     # MCP definitions (6632 LOC)
│   │   │   └── ai-instructions.nix     # AI prompts (3878 LOC)
│   │   ├── secrets-management.nix      # SOPS/Bitwarden (235 LOC)
│   │   ├── github-auth.nix             # Auth helpers (495 LOC)
│   │   └── ...                         # Other modules
│   └── common/                         # Shared config (aliases, git, etc.)
├── modules/                            # NixOS/HM mixins
├── pkgs/                               # Custom packages
├── overlays/                           # Nixpkgs overlays
└── docs/                               # Documentation
```
