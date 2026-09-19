# Plan 034: Private Corporate Overlay Flake

**Branch**: refactor/private-overlay (nixcfg), main (nixcfg-work)
**Created**: 2026-04-12
**Related**: Plan 026 (Team-Sharing Refactoring, Task 4 chose "no repo split")
**Related**: vte-cli Plan 002 (VTE CLI Agent Skill, Phase 2)

## Objective

Create a private overlay flake (`nixcfg-work`) hosted on git.panasonic.aero that:
1. Imports nixcfg (public) and corporate tool flakes (vtecli, etc.) as inputs
2. Owns all corporate host configurations (migrated from nixcfg)
3. Distributes corporate AI skills (vtecli skill, etc.) via claude-code/opencode modules
4. Optionally builds corporate-enhanced .wsl distribution images

This is NOT a repo split (Plan 026 Task 4 decided against that). nixcfg remains
the public module library. nix-corp is an additive composition layer that exists
because corporate tool references (git.panasonic.aero, bedrock URLs, artifactory
hostnames) must not appear in a public GitHub repository.

## Security Motivation

nixcfg is public at github.com/timblaktu/nixcfg. Today, thinky-nixos.nix
contains corporate infrastructure references that are visible to anyone:

- `git.panasonic.aero` (corporate GitLab hostname)
- `codecompanionv2.d-dp.nextcloud.aero` (AI proxy endpoint)
- `ai-platform-bedrockapis.d-dp.nextcloud.aero` (Bedrock proxy)
- `artifinity.nextcloud.aero` (Artifactory hostname)
- `timothy.black@panasonic.aero` (corporate email)
- Bitwarden item names revealing corporate credential structure

These are metadata, not secrets, but they expose internal infrastructure topology
to the public internet. The private overlay moves all corporate references to a
private repository while keeping nixcfg's module library fully public and functional.

## Current State Analysis

### What stays in nixcfg (public)

- All shared modules (system-*, home-*, wsl-*, dev-team)
- Module library exports (shared-modules.nix: 47 modules)
- Team distribution images (nixos-wsl-dev-team, nixos-dev-team, ec2, graviton)
- Personal NON-corporate hosts (thinky-nixos, mbp, potato, nuc-apt-repo, macbook-air, thinky-ubuntu)
- Claude Code/OpenCode module infrastructure (skills.nix, etc.)
- lib.nix presets (baseConfig, workAccount TEMPLATE, defaultMcpServers)

### What moves to nix-corp (private)

- thinky-nixos host config (the ONLY host with corporate references)
- Corporate tool integrations (vtecli skill registration, etc.)
- Corporate-specific module overrides (populated work account values)
- Any future corporate host configs

### Boundary rule

**If it contains a `*.panasonic.aero`, `*.nextcloud.aero`, or other corporate
hostname/URL, it belongs in nix-corp.** If it's structural (option definitions,
templates with unpopulated values), it stays in nixcfg.

## Progress Table

| Task | Category | Status | Description |
|------|----------|--------|-------------|
| 1 | Analysis | TASK:COMPLETE | Audit thinky-nixos.nix: classify every config block as corporate vs personal |
| 2 | Scaffold | TASK:COMPLETE | Create nixcfg-work flake skeleton on git.panasonic.aero/blackt1/nixcfg-work |
| 3 | Migration | TASK:COMPLETE | Move thinky-nixos to nix-corp, verify nixos-rebuild works |
| 4 | Validation | TASK:COMPLETE | Verify nixcfg builds cleanly without thinky-nixos |
| 5 | Integration | TASK:COMPLETE | Add vtecli as nix-corp input, register corporate skills |
| 6 | Distribution | TASK:COMPLETE | Build corporate-enhanced .wsl tarball from nix-corp (optional) |
| 7 | Documentation | TASK:COMPLETE | Document the three-repo architecture and onboarding |

## Task Details

### Task 1: Audit thinky-nixos.nix

Classify every configuration block in thinky-nixos.nix:

| Block | Classification | Destination |
|-------|---------------|-------------|
| NixOS imports (wsl-dev-team, monitoring) | Team-generic | Stays as import refs |
| wsl-settings (hostname, SSH keys) | Machine-specific | nix-corp host config |
| systemDefault.userName = "tim" | Personal | nix-corp host config |
| USBIP Jetson rules (0955:7523) | Corporate device | nix-corp host config |
| HM imports (home-dev-team, esp-idf, etc.) | Mixed | nix-corp host config |
| gitAuth.gitlab (git.panasonic.aero) | CORPORATE | nix-corp host config |
| jfrogCli (artifinity.nextcloud.aero) | CORPORATE | nix-corp host config |
| git.includes (timothy.black@panasonic.aero) | CORPORATE | nix-corp host config |
| claude-code work account (bedrock, codecompanion) | CORPORATE | nix-corp host config |
| opencode work account (bedrock, ai-platform) | CORPORATE | nix-corp host config |
| claude-code personal accounts (max, pro) | Personal | nix-corp host config |
| github-auth (timblaktu@gmail.com) | Personal | nix-corp host config |
| ESP-IDF, Pulumi | Personal | nix-corp host config |
| secrets-management | Personal | nix-corp host config |
| monitoring | Personal | nix-corp host config |

**Decision**: Move the entire host config to nix-corp. It contains both corporate
and personal config, but ALL of it is deployment-specific (not reusable as a module).
Splitting corporate from personal within a single host config adds complexity
without benefit — the host config is already private once it's in nix-corp.

### Definition of Done (Task 1)

- [ ] Every config block classified
- [ ] Decision confirmed: full host migration vs partial extraction

### Task 2: Create nix-corp Flake Skeleton

Create the private overlay flake on git.panasonic.aero:

```
nix-corp/
├── flake.nix
├── flake.lock
├── CLAUDE.md
├── .gitignore
├── hosts/
│   └── thinky-nixos/
│       ├── thinky-nixos.nix
│       └── _hardware-config.nix
├── modules/
│   └── (corporate module overrides if needed)
└── overlays/
    └── (corporate package overlays if needed)
```

**flake.nix structure:**

```nix
{
  description = "Corporate overlay for nixcfg — private infrastructure config";

  inputs = {
    nixcfg.url = "github:timblaktu/nixcfg";
    # Follows nixcfg's nixpkgs to avoid version conflicts
    nixpkgs.follows = "nixcfg/nixpkgs";
    home-manager.follows = "nixcfg/home-manager";
    sops-nix.follows = "nixcfg/sops-nix";
    nixos-wsl.follows = "nixcfg/nixos-wsl";

    # Corporate tool flakes
    vtecli.url = "git+ssh://git@git.panasonic.aero/platform/projects/converix/vte/vte-cli?ref=nix";
  };

  outputs = { self, nixcfg, nixpkgs, home-manager, sops-nix, nixos-wsl, vtecli, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [
        nixcfg.overlays.default
        # Add vtecli to pkgs
        (final: prev: { vtecli = vtecli.packages.${system}.default; })
      ];
    };
  in {
    nixosConfigurations.thinky-nixos = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./hosts/thinky-nixos/thinky-nixos.nix
        nixos-wsl.nixosModules.default
        sops-nix.nixosModules.sops
      ];
      specialArgs = {
        inherit (nixcfg) lib;
        inputs = nixcfg.inputs // { inherit vtecli; self = nixcfg; corp = self; };
      };
    };

    homeConfigurations."tim@thinky-nixos" = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        ./hosts/thinky-nixos/home.nix
        sops-nix.homeManagerModules.sops
      ];
      extraSpecialArgs = {
        inputs = nixcfg.inputs // { inherit vtecli; self = nixcfg; corp = self; };
        hostname = "thinky-nixos";
      };
    };
  };
}
```

**Key design decisions:**
- `follows` nixcfg's nixpkgs/home-manager/sops-nix to avoid duplicate evaluations
- `inputs` passed to modules includes BOTH nixcfg's inputs AND corporate inputs
- `self` in specialArgs points to nixcfg (so `inputs.self.modules.*` still works in host config)
- `corp` added for nix-corp-specific references

### Definition of Done (Task 2)

- [ ] Repo created on git.panasonic.aero
- [ ] flake.nix evaluates (`nix flake check --no-build`)
- [ ] Follows nixcfg's nixpkgs (no duplicate nixpkgs in lock)
- [ ] Can reference nixcfg modules via `inputs.self.modules.*`
- [ ] CLAUDE.md documents the architecture

### Task 3: Migrate thinky-nixos

1. Copy `nixcfg/modules/hosts/thinky-nixos [N]/` to `nix-corp/hosts/thinky-nixos/`
2. Update imports to reference nixcfg modules via the input path
3. Add vtecli integration (programs.vtecli.enable, skill registration)
4. Test: `nixos-rebuild switch --flake '/home/tim/src/nix-corp#thinky-nixos'`
5. Test: `home-manager switch --flake '/home/tim/src/nix-corp#tim@thinky-nixos'`

**Import path changes:**

```nix
# Before (in nixcfg):
imports = [ inputs.self.modules.nixos.wsl-dev-team ];

# After (in nix-corp, where inputs.self = nixcfg):
imports = [ inputs.self.modules.nixos.wsl-dev-team ];
# Same! Because specialArgs maps self -> nixcfg
```

### Definition of Done (Task 3)

- [ ] `nixos-rebuild switch` works from nix-corp flake
- [ ] `home-manager switch` works from nix-corp flake
- [ ] All services running (claude-code, opencode, gitlab-auth, etc.)
- [ ] SSH, secrets, bitwarden all functional
- [ ] vtecli installed and skill available as `/vtecli`

### Task 4: Clean nixcfg

1. Remove `modules/hosts/thinky-nixos [N]/` from nixcfg
2. Remove thinky-nixos entry from `nixos-configurations.nix`
3. Remove `tim@thinky-nixos` entry from `home-configurations.nix`
4. Run `nix flake check --no-build` to verify nixcfg still evaluates cleanly
5. Verify all other hosts still build
6. Verify team distribution images still build

### Definition of Done (Task 4)

- [ ] thinky-nixos directory removed from nixcfg
- [ ] `nix flake check --no-build` passes on nixcfg
- [ ] All remaining host configs evaluate (spot check 2-3)
- [ ] `nixos-wsl-dev-team` tarball still buildable
- [ ] No `panasonic.aero` or `nextcloud.aero` strings remain in nixcfg

### Task 5: Corporate Skill Integration

With vtecli as a nix-corp input and thinky-nixos in nix-corp:

1. vtecli's HM module (Plan 002 T11) auto-registers skill when both
   `programs.vtecli.enable` and `programs.claude-code.enable` are true
2. Alternatively, register skill directly in nix-corp's host HM config:
   ```nix
   programs.claude-code.skills.custom.vtecli = {
     description = "VTE CLI command reference...";
     skillContent = builtins.readFile "${inputs.vtecli.skill}";
     # or: builtins.readFile "${inputs.vtecli}/.ai/skills/vtecli.md";
   };
   ```
3. Verify `/vtecli` works in Claude Code from any project directory on thinky-nixos

**Prefer approach 1** (vtecli HM module self-registers) because:
- Skill stays coupled to the tool version
- Any host that enables vtecli gets the skill automatically
- nix-corp host config just says `programs.vtecli.enable = true`

### Definition of Done (Task 5)

- [ ] `programs.vtecli.enable = true` in thinky-nixos HM config
- [ ] `/vtecli` slash command available in Claude Code from any project
- [ ] Skill content matches `.ai/skills/vtecli.md` from vtecli repo

### Task 6: Corporate Distribution Image (OPTIONAL)

If the team needs a .wsl tarball with corporate tools pre-installed:

1. Define `nixosConfigurations.corp-wsl-dev-team` in nix-corp that extends
   nixcfg's `wsl-dev-team` module with corporate additions
2. Build corporate tarball: `nix build '.#nixosConfigurations.corp-wsl-dev-team.config.system.build.tarballBuilder'`

This is optional — teammates can also just import nix-corp's modules
into their own host configs.

### Definition of Done (Task 6)

- [ ] Corporate tarball builds (if pursued)
- [ ] Tarball includes vtecli + other corporate tools
- [ ] Tarball does NOT include personal credentials

### Task 7: Documentation

1. Add architecture diagram to nix-corp's CLAUDE.md showing three-repo relationship
2. Document the rebuild commands:
   ```bash
   # From nix-corp (corporate machine):
   sudo nixos-rebuild switch --flake '/home/tim/src/nix-corp#thinky-nixos'
   home-manager switch --flake '/home/tim/src/nix-corp#tim@thinky-nixos'

   # From nixcfg (personal machines, unchanged):
   sudo nixos-rebuild switch --flake '/home/tim/src/nixcfg#thinky-nixos'
   home-manager switch --flake '/home/tim/src/nixcfg#tim@thinky-nixos'
   ```
3. Document how to add a new corporate host to nix-corp
4. Document how to add a new corporate tool + AI skill

### Definition of Done (Task 7)

- [ ] CLAUDE.md in nix-corp has architecture overview
- [ ] Rebuild commands documented
- [ ] New-host and new-tool procedures documented

## Architecture Diagram

```
github.com/timblaktu/nixcfg (PUBLIC)
├── Exported modules (47)
│   ├── system-cli, system-desktop, ...
│   ├── wsl-base, wsl-enterprise, wsl-dev-team
│   ├── claude-code, opencode (infrastructure)
│   └── dev-team (structural templates)
├── Team distribution images
│   └── nixos-wsl-dev-team (generic, no corp refs)
├── Personal hosts (no corp refs)
│   ├── thinky-nixos
│   ├── mbp, potato, macbook-air, ...
│   └── thinky-ubuntu
├── lib presets
│   ├── baseConfig, workAccount (template, no URLs)
│   └── defaultMcpServers, defaultSubAgents
└── overlays/

git.panasonic.aero/.../nix-corp (PRIVATE)
├── flake.nix
│   inputs: { nixcfg, vtecli, ... }
│   follows: nixpkgs, home-manager, sops-nix
├── hosts/
│   └── thinky-nixos/     ← migrated from nixcfg
│       ├── NixOS: imports nixcfg.modules.nixos.wsl-dev-team
│       ├── HM: imports nixcfg.modules.homeManager.home-dev-team
│       ├── CORPORATE: git.panasonic.aero, bedrock, artifactory
│       ├── PERSONAL: github PATs, ESP-IDF, SSH keys
│       └── programs.vtecli.enable = true (gets skill automatically)
└── (future corporate hosts)

git.panasonic.aero/.../vte-cli (PRIVATE)
├── .ai/skills/vtecli.md   ← source of truth
├── flake.nix               ← exports: skill, packages, HM module
└── nix/modules/home-manager.nix
    └── programs.vtecli.enable → installs binary + registers skill
```

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| `inputs.self` confusion (nixcfg vs nix-corp) | specialArgs maps `self = nixcfg`, `corp = self` |
| Module option conflicts between nixcfg versions | nix-corp follows nixcfg's nixpkgs/HM exactly |
| Breaking nixcfg when removing thinky-nixos | Task 4 validates all other configs still evaluate |
| Losing thinky-nixos git history | Keep git history via `git filter-branch` or note the source commit |
| Teammate confusion about which flake to use | Task 7 documents everything clearly |

## Relationship to Plan 026

Plan 026 Task 4 chose "Option A: no repo split" — that was about splitting the
module library itself. This plan is different: nixcfg's module library stays
intact. nix-corp is a composition layer that CONSUMES nixcfg modules, not a
fork or split. The decision in Plan 026 remains valid.
