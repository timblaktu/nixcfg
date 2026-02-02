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
| 0.2 | Extraction priorities | `TASK:PENDING` | |
| 0.3 | Architecture decision | `TASK:PENDING` | |
| — | **SESSION BOUNDARY** | | |
| 0.4 | Naming conventions | `TASK:PENDING` | |
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

**Status**: `TASK:PENDING`

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

**Discussion Questions**:

1. **Which components have the highest teammate demand?**
   - "I just want Claude Code working" → wrapper library + module
   - "I want your dev shell" → dev-shells.nix
   - "I want MCP servers" → mcp-server-defs.nix

2. **What's the minimum viable extraction?**
   - Could be just `lib.nix` functions exposed in a flake
   - Or full modules with options

3. **Are there components you explicitly DON'T want to share?**
   - Personal CLAUDE.md content?
   - Specific aliases/workflows?

**Deliverable**: Prioritized extraction list with rationale

---

### Task 0.3: Define Flake Architecture

**Status**: `TASK:PENDING`

**Purpose**: Decide HOW to organize extracted components.

**Option A: Single Library Flake (Mono-Repo)**

```
github.com/timblaktu/nix-ai-tools/
├── flake.nix
├── lib/
│   ├── mcp-servers.nix
│   ├── wrapper-scripts.nix
│   └── secrets-helpers.nix
├── modules/
│   ├── claude-code.nix
│   └── opencode.nix
└── templates/
    └── minimal/
```

**Pros**: Single import, versioned together, easier maintenance
**Cons**: Monolithic, all-or-nothing adoption

**Option B: Multiple Focused Flakes (Multi-Repo)**

```
github.com/timblaktu/nix-mcp-servers/     # Just MCP definitions
github.com/timblaktu/nix-claude-code/     # Claude module + lib
github.com/timblaktu/nix-opencode/        # OpenCode module + lib
github.com/timblaktu/nix-dev-shells/      # Dev shell templates
```

**Pros**: Pick-and-choose, independent versioning, smaller imports
**Cons**: More repos to maintain, coordination overhead

**Option C: Hybrid (Library + Modules Separate)**

```
github.com/timblaktu/nix-ai-lib/          # Shared library (MCP, secrets, helpers)
github.com/timblaktu/nix-ai-modules/      # Home Manager modules (imports lib)
```

**Pros**: Lib can be used without home-manager, modules build on lib
**Cons**: Two repos, version coordination

**Discussion Questions**:

1. **How do you prefer to manage shared code?**
   - Single repo with everything?
   - Multiple focused repos?
   - Something else?

2. **Do teammates need just library functions, or full modules?**
   - Library: `lib.mkClaudeWrapper { ... }`
   - Module: `programs.claude-code.enable = true;`

3. **Version strategy?**
   - Follow nixpkgs releases?
   - Semantic versioning?
   - Rolling (always use main)?

**Deliverable**: Architecture decision with rationale

---

### Task 0.4: Establish Naming Conventions and Namespaces

**Status**: `TASK:PENDING`

**Purpose**: Define consistent naming for extracted components.

**Current Namespaces in nixcfg**:
- `programs.claude-code.*` (shadows upstream, uses `disabledModules`)
- `programs.opencode.*` (shadows upstream)
- `homeBase.*` (personal config options)

**Questions**:

1. **Should extracted modules use different namespaces?**
   - Keep `programs.claude-code` (requires disabledModules in consumer)?
   - Use `programs.claude-code-enhanced` or `tim.claude-code`?
   - Follow upstream conventions?

2. **Library function naming?**
   - `lib.mkClaudeWrapper` vs `lib.claude.mkWrapper` vs `claude-lib.mkWrapper`?

3. **Flake output naming?**
   - `homeManagerModules.claude-code`?
   - `lib.claude-code`?
   - `overlays.claude-code`?

**Deliverable**: Naming convention document

---

### Task 0.5: Design Discussion Sign-Off

**Status**: `TASK:PENDING`

**Purpose**: Confirm design decisions before implementation.

**Sign-off Checklist**:
- [ ] Audience and scope defined (0.1)
- [ ] Extraction priorities set (0.2)
- [ ] Architecture chosen (0.3)
- [ ] Naming conventions established (0.4)
- [ ] User approves proceeding to Phase 1

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
