# Plan 026: Team-Sharing Refactoring — Files Module, Username DRY, Repo Separation

**Branch**: TBD (create from main at task start)
**Created**: 2026-03-14
**Predecessor**: Plan 023 (Distributable WSL Images — COMPLETE)
**Deferred from**: Plan 019 (Dendritic Migration — tasks F5, F1)

## Objective

Complete the remaining refactoring needed to make nixcfg's shared modules
cleanly consumable by tiger-team members. Addresses internal anti-patterns
first (Tasks 1-2), then structural separation and team infrastructure (Tasks 3-5).

## Progress Table

| Task | Category | Status | Validation | Description |
|------|----------|--------|------------|-------------|
| 1 | Files Module | TASK:PENDING | `nix flake check --no-build` + HM dry-run | Refactor files module anti-patterns (F5) |
| 2 | Username DRY | TASK:PENDING | `nix flake check --no-build` + HM dry-run | Centralize hardcoded username refs (F1) |
| 3 | Repo Separation | TASK:PENDING | Both flakes pass `nix flake check --no-build` | Split shared modules into separate flake |
| 4 | CrowdStrike | TASK:PENDING | Enterprise module activates without warnings | Fill CrowdStrike stub when IT provides package |
| 5 | Tarball Hosting | TASK:PENDING | Teammates can `nix build` or `wsl --import` | Establish distribution channel for team tarball |

---

## Task 1: Files Module Refactoring (F5)

**Status**: TASK:PENDING
**Priority**: HIGH — blocks clean repo separation (Task 3)

### Problem Statement

The files module (`modules/programs/files [nd]/`) has three anti-patterns
that make it fragile and expensive:

1. **Exclusion list** (`_completion-generator.nix:315-338`): A manual list of
   23 script names that are "installed elsewhere" and must be excluded from
   auto-completion generation and symlink installation. Adding/moving scripts
   requires remembering to update this list.

2. **Hardcoded relative path** (`_completion-generator.nix:9`): `filesDir = ./files;`
   creates tight coupling. Used at lines 360, 379, 401, 409, 416 for bin/lib paths.

3. **Eval-time completion generation** (`_completion-generator.nix:11-275`):
   `generateAutoZshCompletion` (158 lines) and `generateAutoBashCompletion`
   (103 lines) run shell scripts during Nix evaluation to parse `--help` output
   and generate completions. This runs on every `nix flake check`.

### Current Module Structure

```
modules/programs/files [nd]/
├── files.nix                    # Entry point (minimal wrapper)
├── _completion-generator.nix    # 17,290 LOC — completion + installation logic
├── _homefiles-module.nix        # 15,046 LOC — HM integration with autoWriter
└── files/
    ├── bin/                     # 34 executable scripts
    └── lib/                     # 11 utility libraries
```

### Exclusion List Contents (lines 315-338)

Scripts currently tracked as "installed elsewhere":
```
simple-test, hello-validated, smart-nvimdiff,
bootstrap-secrets.sh, bootstrap-ssh-keys.sh, build-wsl-tarball,
esp-idf-install, esp-idf-shell, esp-idf-export, idf.py,
claude-code-wrapper, claude-code-update,
onedrive-force-sync, colorfuncs, mergejson,
onedrive-status, tmux-session-picker
```

### Modules That Import files Module (7 consumers)

- `modules/system/settings/wsl-enterprise/wsl-enterprise.nix`
- `modules/hosts/mbp [N]/mbp.nix`
- `modules/hosts/thinky-ubuntu [nd]/thinky-ubuntu.nix`
- `modules/hosts/macbook-air [D]/macbook-air.nix`
- `modules/hosts/thinky-nixos/thinky-nixos.nix`
- `modules/hosts/potato [N]/potato.nix`
- `modules/flake-parts/tests.nix` (lines 180, 562-625)

### Refactoring Strategy

**1a. Distribute script ownership to feature modules**
- Each dendritic module that provides scripts should declare them via a
  standard interface (e.g., `homeFiles.scripts.${name} = ./path`)
- The central files module becomes a thin aggregator or disappears
- Eliminates the exclusion list entirely

**1b. Replace relative paths with flake-rooted paths**
- Change `filesDir = ./files;` to `filesDir = inputs.self + "/modules/programs/files [nd]/files";`
- Or pass `filesDir` as a module argument

**1c. Move completion generation to build-time derivations**
- Replace `generateAutoZshCompletion`/`generateAutoBashCompletion` string
  interpolation with `pkgs.runCommand` derivations
- Completions become derivation outputs, cached by Nix store
- Only rebuild when source script actually changes

### Definition of Done

- [ ] No `validatedScriptNames` exclusion list exists
- [ ] No hardcoded `./files` relative path in completion generator
- [ ] Completions generated as derivations (build-time), not eval-time strings
- [ ] `nix flake check --no-build` passes
- [ ] `home-manager switch --flake ".#${USER}@$(hostname)" --dry-run` succeeds
- [ ] All 7 consumers still work (test each host config evaluation)

---

## Task 2: Username Centralization (F1)

**Status**: TASK:PENDING
**Priority**: MEDIUM — reduces noise, prepares for repo separation

### Problem Statement

`config.meta.username` already exists (`modules/meta/options.nix:22-35`,
default `"tim"`, readOnly) but is underutilized. Instead, 6 host configs
define `username = "tim"` in local `let` blocks, and 18+ VM test configs
hardcode `systemDefault.userName = "tim"`.

### Audit Results

**Host configurations** (6 files, each with `username = "tim"` in let block):
| Host File | Line |
|-----------|------|
| `modules/hosts/thinky-nixos/thinky-nixos.nix` | 19 |
| `modules/hosts/thinky-ubuntu [nd]/thinky-ubuntu.nix` | 12 |
| `modules/hosts/macbook-air [D]/macbook-air.nix` | 13 |
| `modules/hosts/mbp [N]/mbp.nix` | 13 |
| `modules/hosts/pa161878-nixos [N]/pa161878-nixos.nix` | 22 |
| `modules/hosts/potato [N]/potato.nix` | 13 |

**VM test configurations** (`modules/flake-parts/vm-tests.nix`):
18 separate test blocks hardcode `systemDefault.userName = "tim"` and
`homeMinimal.username = "tim"` + `homeMinimal.homeDirectory = "/home/tim"`.
Lines: 117, 188, 222, 268, 276, 518, 670, 770, 877, 1005, 1193, 1332, 1445, 1669, 1809.

**Test references** (`modules/flake-parts/tests.nix`):
Lines 339-340 hardcode `users.users.tim` in config assertions.

**Home config registration** (`modules/flake-parts/home-configurations.nix`):
Lines 91-92 hardcode `username = "tim"`.

**Already correct** (no changes needed):
- System types (`system-default`, `system-cli`, `system-desktop`) use
  `config.systemDefault.userName` dynamically
- `config.meta.username` exists with `readOnly = true`

### Refactoring Strategy

**2a. Host configs**: Replace `username = "tim"` with `username = config.meta.username`
in each host's `let` block. The local variable is still useful for interpolation;
just source it from the meta option.

**2b. VM tests**: Create a helper in `vm-tests.nix` that provides default
test user config, eliminating per-test hardcoding:
```nix
defaultTestUser = {
  systemDefault.userName = config.meta.username;
  homeMinimal.username = config.meta.username;
  homeMinimal.homeDirectory = "/home/${config.meta.username}";
};
```

**2c. Test assertions**: Update `tests.nix:339-340` to use
`users.users.${config.meta.username}` instead of `users.users.tim`.

**2d. Home config registration**: Update `home-configurations.nix:91-92`.

### Constraint

`config.meta.username` is `readOnly = true` at the flake level. For tiger-team
distribution (generic user "dev"), `systemDefault.userName` is already the
correct dynamic mechanism — hosts override it. The meta option represents
the flake owner's identity, which is fine for personal configs.

For repo separation (Task 3), the shared flake would NOT have `meta.username`
set to "tim" — it would be set by each consumer.

### Definition of Done

- [ ] Zero instances of literal `"tim"` in host configs (use `config.meta.username`)
- [ ] Zero instances of literal `"tim"` in `vm-tests.nix` (use helper or meta)
- [ ] Zero instances of `users.users.tim` in `tests.nix` (use dynamic ref)
- [ ] `nix flake check --no-build` passes
- [ ] All host evaluations succeed
- [ ] All VM tests still evaluate (build check optional)

---

## Task 3: Repository Separation

**Status**: TASK:PENDING
**Priority**: HIGH — the core enabler for team consumption
**Depends on**: Tasks 1-2 (clean internal state first)

### Problem Statement

Everything lives in one repo. Teammates cannot consume `wsl-enterprise` or
`wsl-tiger-team` without also pulling personal configs, secrets references,
and personal host definitions.

### Current Export Surface

`modules/flake-parts/shared-modules.nix` currently exports only 4 modules:
```nix
nixosModules = { wsl-base, wsl-enterprise, wsl-tiger-team };
homeManagerModules = { wsl-home-base };
```

But 22+ feature modules (claude-code, opencode, shell, git, tmux, neovim,
development-tools, etc.) remain private despite being consumed by tiger-team.

### Cross-Reference Counts

- 251 `inputs.self` references across modules
- 182 internal `inputs.self.modules` cross-references within shared modules
- 367 total `self.modules` or `self.lib` references

### Module Classification

**Would move to shared flake**:
- `modules/system/types/` (minimal, default, cli, desktop)
- `modules/system/settings/wsl/`, `wsl-enterprise/`, `wsl-tiger-team/`
- `modules/programs/` sharable subset: shell, git, tmux, neovim,
  claude-code, opencode, development-tools, system-tools, awscli,
  onedrive, shell-utils, yazi, terminal
- `modules/flake-parts/shared-modules.nix`, `lib.nix` (preset helpers)
- `modules/meta/` (with `readOnly` removed from username, or made configurable)

**Would stay in personal flake**:
- `modules/hosts/pa161878-nixos [N]/` and all other personal hosts
- `modules/programs/` personal subset: secrets-management, github-auth,
  esp-idf, pulumi, files (post-refactor), windows-terminal, git-auth-helpers,
  podman, gitlab-auth
- `modules/flake-parts/nixos-configurations.nix`, `home-configurations.nix`
- Personal test suite

### Key Decisions Required (at task start)

1. **Shared repo location**: GitHub public vs internal GitLab?
2. **Flake input name**: `nixcfg-shared`? `nixcfg-team`?
3. **Versioning**: Pin to tags or follow main?
4. **Which feature modules are shared vs personal?** (bracket tags help:
   `[nd]` = no-distribute, but some `[nd]` modules like podman/gitlab-auth
   ARE in tiger-team bundle — need reclassification)
5. **Lib presets**: Do `claudeCode.personalAccounts` stay in personal flake?
   (Yes — only `baseConfig` and `workAccount` go to shared)

### Refactoring Strategy

**3a. Create shared flake** with import-tree structure mirroring current layout
**3b. Move classified modules** (copy, not git-filter-branch — history stays)
**3c. Update personal flake** to consume shared as `inputs.nixcfg-team`
**3d. Update cross-references**: `inputs.self.modules.nixos.wsl-tiger-team`
     becomes `inputs.nixcfg-team.modules.nixos.wsl-tiger-team`
**3e. Split test infrastructure**: Shared flake gets module-level tests,
     personal flake keeps host integration tests

### Definition of Done

- [ ] Shared flake exists in separate repository
- [ ] `nix flake check --no-build` passes on shared flake
- [ ] Personal flake consumes shared flake as input
- [ ] `nix flake check --no-build` passes on personal flake
- [ ] `nixos-wsl-tiger-team` tarball builds from shared flake
- [ ] `pa161878-nixos` builds from personal flake (consumes shared)
- [ ] No personal data (email, PATs, hostnames) in shared flake

---

## Task 4: CrowdStrike Integration

**Status**: TASK:PENDING
**Priority**: LOW — blocked on IT providing package
**Depends on**: Task 3 (should be in shared flake)

### Current State

Enterprise module has options defined (`enterprise.crowdStrike.{enable,cid,serverUrl}`)
at `wsl-enterprise.nix:73-91`. Implementation shows a warning when enabled
(lines 256-267) because no package exists yet.

### What's Needed (when IT provides)

1. Package derivation (or fetchurl of binary)
2. Systemd service unit for falcon-sensor
3. Configuration file generation (/etc/crowdstrike/)
4. Sensor binary path integration

### Definition of Done

- [ ] `enterprise.crowdStrike.enable = true` activates sensor
- [ ] Warning message removed
- [ ] Service starts and reports healthy
- [ ] CID and serverUrl configure sensor correctly

---

## Task 5: Tarball/Flake Hosting & Distribution

**Status**: TASK:PENDING
**Priority**: MEDIUM — enables teammate self-service
**Depends on**: Task 3 (shared flake must exist first)

### Problem Statement

Plan 023 noted "Repo hosting: Deferred." Teammates need a way to:
1. Get the shared flake as a Nix input (for customization)
2. Download a pre-built `.wsl` tarball (for quick onboarding)
3. Know where to file issues and contribute

### Options to Evaluate

| Channel | Audience | Mechanism |
|---------|----------|-----------|
| Git repo (GitLab internal) | Nix-savvy teammates | `inputs.nixcfg-team.url = "git+ssh://..."` |
| Git repo (GitHub) | Broader team | `inputs.nixcfg-team.url = "github:org/repo"` |
| CI artifact | Non-Nix teammates | GitLab CI builds tarball, stores as job artifact |
| Shared drive | Air-gapped | Manual copy of `.wsl` file |

### Definition of Done

- [ ] Shared flake hosted and accessible to team members
- [ ] Pre-built tarball available via documented channel
- [ ] `docs/WSL-TEAM-QUICKSTART.md` updated with new URLs
- [ ] Team member can go from zero to working WSL in documented steps

---

## Execution Notes

- **One task per session** per session workflow protocol
- Tasks 1-2 are independent of each other (could parallelize across sessions)
- Task 3 depends on Tasks 1-2 being complete
- Task 4 is externally blocked (IT) — skip if package unavailable
- Task 5 depends on Task 3

### Dependency Graph

```
Task 1 (Files) ──┐
                  ├──> Task 3 (Repo Sep) ──> Task 5 (Hosting)
Task 2 (Username)─┘
                        Task 4 (CrowdStrike) ← blocked on IT
```
