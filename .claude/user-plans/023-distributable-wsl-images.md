# Plan 023: Distributable NixOS-WSL Images

**Status**: COMPLETE
**Branch**: `refactor/dendritic-pattern`
**Created**: 2026-02-13

## Context

Two parallel efforts require distributable NixOS-WSL `.wsl` tarball images:

1. **Tiger Team image**: A development-focused WSL image for the user's immediate team, including full dev stack (binfmt, Podman, Claude Code enterprise, OpenCode, Code Companion, GitLab panasonic.aero). Teammates have identical Windows 11 laptops (same model as pa161878-nixos).

2. **Enterprise base image**: A company-wide standard image coordinated with global IT, suitable for any employee using Windows laptops with daily Linux needs. Other teams (beyond tiger-team) will create their own team layers on top of this base.

Both efforts are active NOW. The architecture must support N teams each creating their own team module on top of the shared enterprise base.

## Architecture

Four-layer model using dendritic module pattern:

```
┌─────────────────────────────────────────────────────────┐
│ Layer 1: wsl-enterprise (MODULE)                        │
│   Company-wide base. Imports system-cli + wsl internally│
│   All team modules MUST import this.                    │
├─────────────────────────────────────────────────────────┤
│ Layer 2: wsl-tiger-team (MODULE)    wsl-other-team ...  │
│   Team-specific tools/config.       (future teams)      │
│   Imports wsl-enterprise.                               │
├─────────────────────────────────────────────────────────┤
│ Layer 3: nixos-wsl-tiger-team (HOST)                    │
│   Thin composition layer.                               │
│   Imports wsl-tiger-team module.                        │
│   Produces .wsl tarball image.                          │
├─────────────────────────────────────────────────────────┤
│ Layer 4: pa161878-nixos (HOST) - personal               │
│   Imports wsl-tiger-team + personal HM config.          │
│   NOT distributed. (deferred refactor)                  │
└─────────────────────────────────────────────────────────┘
```

**Key principle**: Team layers are MODULES (reusable, composable), not hosts. Hosts are thin composition layers that import modules and produce outputs (.wsl images). This enables:

```
wsl-enterprise (module)         -- required base for all
├── wsl-tiger-team (module)     -- your team
│   ├── nixos-wsl-tiger-team (host) → .wsl tarball
│   └── pa161878-nixos (host)       → personal machine
├── wsl-other-team (module)     -- another team (future)
│   └── nixos-wsl-other-team (host) → .wsl tarball
└── nixos-wsl-enterprise (host) -- IT-only base image (future)
    └── → .wsl tarball
```

### Home Manager Architecture (RESOLVED)

**Decision**: Option B -- Dual-registration modules. Enterprise and team modules each provide
both `flake.modules.nixos.*` and `flake.modules.homeManager.*` registrations.

**Key design principles**:
- Layers are **convenience bundles** of existing dendritic feature modules, not gatekeepers
- No exclusivity: importing `claude-code` in `home-tiger-team` does NOT prevent another team
  from independently importing `claude-code`
- Any host can compose layers + cherry-pick individual modules piecemeal
- Each layer only imports modules where it can set **meaningful shared defaults**
- Repo hosting (personal github vs org) is deferred -- architecture supports moving later

**HM Feature Module Assignment** (20 modules from current `tim@pa161878-nixos`):

Enterprise (`home-enterprise`) -- tools any Linux employee needs:
- `home-default` (base HM layer, includes home-minimal)
- `shell`, `git`, `tmux`, `neovim` (core CLI tools)
- `wsl-home`, `terminal`, `shell-utils`, `system-tools` (WSL/terminal baseline)
- `yazi`, `files`, `git-auth-helpers` (standard utilities)
- `onedrive` (corporate Microsoft 365 tool)

Tiger-team (`home-tiger-team`) -- team dev workflow:
- `claude-code`, `opencode` (AI dev tools with work account config)
- `gitlab-auth` (panasonic.aero GitLab instance)
- `podman` (container workflow with standard aliases)
- `development-tools` (team dev tools)
- `windows-terminal` (standardized terminal appearance)

Personal only (remain in `tim@pa161878-nixos`):
- `secrets-management` (personal bitwarden email)
- `github-auth` (personal GitHub PATs)
- `esp-idf` (personal embedded hobby)

## Decisions Record

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Username | Generic 'dev' + setup-username script | Avoids boot-time detection edge cases (domain prefixes, timing) |
| Enterprise base | system-cli + WSL | Users are "people who use linux daily" |
| Team features | Full dev stack minus ESP-IDF | binfmt, Podman, Claude Code enterprise, OpenCode, Code Companion, GitLab |
| CrowdStrike | Stubbed option, disabled | Server/auth details TBD from IT |
| Proxy/VPN | Not needed | User confirmed |
| Layer boundary | Shared modules + thin hosts | Supports N teams; hosts just compose modules |
| allowUnfree | false in enterprise, true in tiger-team | Enterprise FOSS-clean; teams override |
| Team naming | "tiger-team" | User's team identifier |
| HM in layers | Option B: dual-registration | Layers are convenience bundles of dendritic modules; no exclusivity |
| OneDrive | Enterprise layer | Corporate M365 tool, not personal |
| Repo hosting | Deferred | Architecture supports moving shared bits to org repo later |

## Progress

| Task | Status | Description |
|------|--------|-------------|
| Task 0 | `TASK:COMPLETE` | Resolve HM architecture question |
| Task 1 | `TASK:COMPLETE` | Create wsl-enterprise module (NixOS + HM) |
| Task 2 | `TASK:COMPLETE` | Create wsl-tiger-team module (NixOS + HM) |
| Task 3 | `TASK:COMPLETE` | Create nixos-wsl-tiger-team host + registration |
| Task 4 | `TASK:COMPLETE` | Refactor pa161878-nixos to use new layers |
| Task 5 | `TASK:COMPLETE` | Build tarball + validate + document |

---

## Task 0: Resolve Home Manager Architecture -- COMPLETE

**Decision**: Option B -- Dual-registration. See "Home Manager Architecture" section above.

Resolved 2026-02-13. Tasks 1-5 updated with HM specs.

---

## Task 1: Create wsl-enterprise Module (NixOS + HM)

**Scope**: New dendritic settings module providing company-wide WSL base.
Dual-registration: provides both NixOS system config and HM user config bundle.

### Files to Create

- `modules/system/settings/wsl-enterprise/wsl-enterprise.nix`

### NixOS Specification (`flake.modules.nixos.wsl-enterprise`)

**Internal imports** (teams get these automatically):
- `inputs.self.modules.nixos.system-cli` (chain: minimal -> default -> cli)
- `inputs.self.modules.nixos.wsl` (WSL integration, SOPS, systemd fix)

**Options namespace** (`enterprise.*`):
```nix
enterprise = {
  crowdStrike = {
    enable = mkOption { type = bool; default = false; };
    cid = mkOption { type = str; default = ""; };
    serverUrl = mkOption { type = str; default = ""; };
  };
  welcomeMessage.enable = mkOption { type = bool; default = true; };
};
```

**Defaults set via `mkDefault`** (overridable by team modules):
- `systemDefault.userName = "dev"`
- `wsl-settings.hostname = "nixos-wsl"`
- `wsl-settings.defaultUser = "dev"`
- `wsl-settings.sshPort = 22`
- `wsl-settings.userGroups = ["wheel"]`
- `wsl-settings.sshAuthorizedKeys = []`
- `wsl-settings.sops.enable = false`
- `wsl-settings.cuda.enable = false`
- `wsl-settings.binfmt.enable = false`
- `wsl-settings.systemdUserSession.fixRuntimeDir = true`
- `wsl-settings.tarballChecks.enable = true`
- `wsl-settings.tarballChecks.personalIdentifiers = []` (no personal names)
- `security.sudo.wheelNeedsPassword = false`
- `system.stateVersion = "24.11"`
- CrowdStrike stub: warning when enabled but no package available
- First-login welcome message (pattern from nixos-wsl-minimal)

**Does NOT set** (left to team modules/hosts):
- `nixpkgs.config.allowUnfree`
- `systemCli.enableClaudeCodeEnterprise`
- `systemCli.enablePodman` / `systemCli.enableDocker`
- `wsl-settings.binfmt.enable`

### HM Specification (`flake.modules.homeManager.home-enterprise`)

**Purpose**: Convenience bundle of HM feature modules any enterprise employee would use.
This is NOT included in the .wsl tarball -- it's for users who use this flake for their HM config.

**Imports** (the bundle):
- `inputs.self.modules.homeManager.home-default` (base: includes home-minimal)
- `inputs.self.modules.homeManager.shell`
- `inputs.self.modules.homeManager.git`
- `inputs.self.modules.homeManager.tmux`
- `inputs.self.modules.homeManager.neovim`
- `inputs.self.modules.homeManager.wsl-home`
- `inputs.self.modules.homeManager.terminal`
- `inputs.self.modules.homeManager.shell-utils`
- `inputs.self.modules.homeManager.system-tools`
- `inputs.self.modules.homeManager.yazi`
- `inputs.self.modules.homeManager.files`
- `inputs.self.modules.homeManager.git-auth-helpers`
- `inputs.self.modules.homeManager.onedrive`

**Defaults set via `mkDefault`** (overridable by team/host):
- `homeFiles.enable = true`
- `oneDriveUtils.enable = true`
- `wsl-home-settings.distroName = "nixos"` (sensible default, overridable)

**Does NOT configure** (left to team/host):
- `homeMinimal.username` / `homeMinimal.homeDirectory` (must be set by host)
- `secretsManagement.*` (personal)
- `gitAuth.*` (team or personal)

### Definition of Done
1. File at `modules/system/settings/wsl-enterprise/wsl-enterprise.nix`
2. Both registrations present: `flake.modules.nixos.wsl-enterprise` + `flake.modules.homeManager.home-enterprise`
3. `nix flake check --no-build` passes
4. Committed

---

## Task 2: Create wsl-tiger-team Module (NixOS + HM)

**Scope**: Team-specific dendritic module layered on enterprise base.
Dual-registration: provides both NixOS system config and HM user config bundle.

### Files to Create

- `modules/system/settings/wsl-tiger-team/wsl-tiger-team.nix`

### NixOS Specification (`flake.modules.nixos.wsl-tiger-team`)

**Internal imports**:
- `inputs.self.modules.nixos.wsl-enterprise`

**Overrides on enterprise defaults** (via `mkDefault`):
- `wsl-settings.hostname = "nixos-wsl-tiger"` (overridable by host)
- `wsl-settings.binfmt.enable = true`
- `systemCli.enablePodman = true`
- `systemCli.enableClaudeCodeEnterprise = true`
- `nixpkgs.config.allowUnfree = true`

**Team-specific additions**:
- `setup-username` script (writeShellScriptBin in environment.systemPackages)
- GitLab panasonic.aero system-level git credential config
- Claude Code managed-settings.json with Code Companion (lib.mkForce override)
- OpenCode system-level config (if applicable at NixOS level)

### HM Specification (`flake.modules.homeManager.home-tiger-team`)

**Purpose**: Convenience bundle of HM feature modules the tiger team uses.
Imports enterprise HM bundle + adds team-specific AI dev tools and workflow.

**Imports** (the bundle):
- `inputs.self.modules.homeManager.home-enterprise` (gets all enterprise HM modules)
- `inputs.self.modules.homeManager.claude-code`
- `inputs.self.modules.homeManager.opencode`
- `inputs.self.modules.homeManager.gitlab-auth`
- `inputs.self.modules.homeManager.podman`
- `inputs.self.modules.homeManager.development-tools`
- `inputs.self.modules.homeManager.windows-terminal`

**Defaults set via `mkDefault`** (overridable by host):
- Claude Code work account config (from `inputs.self.lib.claudeCode.workAccount`)
- OpenCode work provider config (from `inputs.self.lib.openCode.workProvider`)
- GitLab panasonic.aero auth defaults (`gitAuth.gitlab.host = "git.panasonic.aero"`)
- Podman aliases (`docker = "podman"`, `d = "podman"`, `dc = "podman-compose"`)
- `programs.podman-tools = { enable = true; enableCompose = true; }`
- `programs.tmux.autoReload.enable = true`
- Windows Terminal standard font/keybindings

**Does NOT configure** (left to host):
- `homeMinimal.username` / `homeMinimal.homeDirectory`
- `secretsManagement.*` (personal bitwarden)
- `gitAuth.github.*` (personal GitHub PATs)
- `gitAuth.gitlab.bitwarden.*` (personal credential details)
- `gitAuth.gitlab.mode` (bitwarden vs token -- personal choice)

### Definition of Done
1. File at `modules/system/settings/wsl-tiger-team/wsl-tiger-team.nix`
2. Both registrations present: `flake.modules.nixos.wsl-tiger-team` + `flake.modules.homeManager.home-tiger-team`
3. `nix flake check --no-build` passes
4. Committed

---

## Task 3: Create nixos-wsl-tiger-team Host + Registration

**Scope**: Thin host config, hardware config, flake registration, shared module export.

### Files to Create

- `modules/hosts/nixos-wsl-tiger-team [N]/nixos-wsl-tiger-team.nix`
- `modules/hosts/nixos-wsl-tiger-team [N]/_hardware-config.nix` (copy from nixos-wsl-minimal)

### Files to Modify

- `modules/flake-parts/nixos-configurations.nix` -- add nixos-wsl-tiger-team
- `modules/flake-parts/systems.nix` -- add to hosts map
- `modules/flake-parts/shared-modules.nix` -- export wsl-enterprise + wsl-tiger-team

### Host Config Specification

**Thin composition** -- the host should be minimal:
```nix
flake.modules.nixos.nixos-wsl-tiger-team = { config, lib, pkgs, ... }: {
  imports = [
    ./_hardware-config.nix
    inputs.self.modules.nixos.wsl-tiger-team
  ];
  # Host-specific overrides only (if any)
};
```

### Definition of Done
1. All files created/modified
2. `nix flake check --no-build` passes
3. `nix build '.#nixosConfigurations.nixos-wsl-tiger-team.config.system.build.tarballBuilder' --dry-run` succeeds
4. Shared module exports visible
5. Committed

---

## Task 4: Refactor pa161878-nixos to Use New Layers

**Scope**: Replace the 20 individual HM imports in `tim@pa161878-nixos` with the new layer
modules, keeping only personal-specific imports and config.

### Files to Modify

- `modules/hosts/pa161878-nixos [N]/pa161878-nixos.nix`

### NixOS Side Changes

Replace direct imports of `system-cli` + `wsl` with `wsl-tiger-team`:
```nix
# BEFORE:
imports = [
  ./_hardware-config.nix
  inputs.self.modules.nixos.system-cli
  inputs.self.modules.nixos.wsl
];

# AFTER:
imports = [
  ./_hardware-config.nix
  inputs.self.modules.nixos.wsl-tiger-team
];
```
Keep all personal overrides (hostname, ssh keys, cuda, etc.) -- they override mkDefault values.

### HM Side Changes

Replace 20 individual imports with layer + personal-only modules:
```nix
# BEFORE: 20 individual imports (home-default, shell, git, tmux, ...)

# AFTER:
imports = [
  inputs.self.modules.homeManager.home-tiger-team  # enterprise + team bundle
  inputs.self.modules.homeManager.secrets-management  # personal
  inputs.self.modules.homeManager.github-auth         # personal
  inputs.self.modules.homeManager.esp-idf             # personal
];
```
Keep all personal config options (bitwarden email, GitHub PATs, personal overrides).
Remove config that is now set by the team layer (podman aliases, tmux autoReload,
windows-terminal defaults, etc.) -- only keep personal OVERRIDES of team defaults.

### Definition of Done
1. `pa161878-nixos.nix` uses `wsl-tiger-team` (NixOS) and `home-tiger-team` (HM)
2. Personal-only modules remain as direct imports
3. `nix flake check --no-build` passes
4. `home-manager switch --flake '.#tim@pa161878-nixos' --dry-run` succeeds
5. No functional changes to the resulting system (refactor only)
6. Committed

---

## Task 5: Build Tarball + Validate + Document

**Scope**: Actual tarball build, content validation, CLAUDE.md update.

### Actions

1. Build: `nix build '.#nixosConfigurations.nixos-wsl-tiger-team.config.system.build.tarballBuilder'`
2. Verify no personal data in output
3. Run tarball security check
4. Update CLAUDE.md with new architecture documentation

### Definition of Done
1. Tarball builds successfully (or issues documented)
2. Security check passes
3. CLAUDE.md updated
4. Committed

---

## Critical File Paths

| Purpose | Path |
|---------|------|
| Pattern: WSL module | `modules/system/settings/wsl/wsl.nix` |
| Pattern: dist host | `modules/hosts/nixos-wsl-minimal [N]/nixos-wsl-minimal.nix` |
| Flake registration | `modules/flake-parts/nixos-configurations.nix` |
| Host map | `modules/flake-parts/systems.nix` |
| Shared exports | `modules/flake-parts/shared-modules.nix` |
| Claude Code presets | `modules/flake-parts/lib.nix` |
| System-cli options | `modules/system/types/3-cli/cli.nix` |
| HW config source | `modules/hosts/nixos-wsl-minimal [N]/_hardware-config.nix` |

## Verification

```bash
# Evaluate (fast)
nix flake check --no-build

# Build tarball
nix build '.#nixosConfigurations.nixos-wsl-tiger-team.config.system.build.tarballBuilder'

# Security check
./result/bin/wsl-tarball-security-check nixos-wsl-tiger-team
```

## Future Work (Not in This Plan)

- CrowdStrike Falcon sensor integration (when IT provides CID/server)
- IT-only enterprise host config (no team tools)
- Binary cache for faster builds across team (relates to Plan 013)
- Other team modules following tiger-team pattern
- Move shared modules to org repo (when hosting decision is made)
