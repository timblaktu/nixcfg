# Plan 026: Team-Sharing Refactoring — Files, Username, CrowdStrike, Repo Split, Distribution

**Branch**: TBD (create from main at task start)
**Created**: 2026-03-14
**Predecessor**: Plan 023 (Distributable WSL Images — COMPLETE)
**Deferred from**: Plan 019 (Dendritic Migration — tasks F5, F1)

## Objective

Complete the remaining refactoring and feature work needed to make nixcfg's
shared modules cleanly consumable by dev-team members, including a
production-ready CrowdStrike Falcon integration. Culminates in a
demonstration to IT showing the team WSL image with Falcon baked in.

## Progress Table

| Task | Category | Status | Validation | Description |
|------|----------|--------|------------|-------------|
| 1 | Files Module | TASK:COMPLETE | `nix flake check --no-build` + HM dry-run | Refactor files module anti-patterns (F5) |
| 2 | Username DRY | TASK:COMPLETE | `nix flake check --no-build` + HM dry-run | Centralize hardcoded username refs (F1) |
| 3 | CrowdStrike | TASK:COMPLETE | Module evals, service activates in VM test | Build Falcon sensor dendritic module |
| 4 | Module Exports | TASK:COMPLETE | `nix flake check --no-build` passes | Export all modules, remove [nd] tags (Option A: no repo split) |
| 5 | Tarball Hosting | TASK:COMPLETE | Teammates can `nix build` or `wsl --import` | Establish distribution channel for team tarball |
| 6 | IT Demo | TASK:PENDING | IT provides CID + provisioning token | Demonstrate Falcon-enabled WSL image to IT |

---

## Task 1: Files Module Refactoring (F5)

**Status**: TASK:COMPLETE (2026-03-14)
**Priority**: HIGH — blocks clean repo separation (Task 4)

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

`config.meta.username` is `readOnly = true` at the flake level. For dev-team
distribution (generic user "dev"), `systemDefault.userName` is already the
correct dynamic mechanism — hosts override it. The meta option represents
the flake owner's identity, which is fine for personal configs.

For repo separation (Task 4), the shared flake would NOT have `meta.username`
set to "tim" — it would be set by each consumer.

### Definition of Done

- [ ] Zero instances of literal `"tim"` in host configs (use `config.meta.username`)
- [ ] Zero instances of literal `"tim"` in `vm-tests.nix` (use helper or meta)
- [ ] Zero instances of `users.users.tim` in `tests.nix` (use dynamic ref)
- [ ] `nix flake check --no-build` passes
- [ ] All host evaluations succeed
- [ ] All VM tests still evaluate (build check optional)

---

## Task 3: CrowdStrike Falcon Sensor Module

**Status**: TASK:COMPLETE (2026-03-14)
**Priority**: HIGH — key enterprise compliance feature for WSL image
**Depends on**: None (can proceed independently of Tasks 1-2)
**Commit**: `be207f8` on `feat/usb-jetson-pa161878`

### Problem Statement

The enterprise module has a CrowdStrike stub (`wsl-enterprise.nix:73-91`)
with options for `enable`, `cid`, and `serverUrl`, but only emits a warning
when enabled. We need a full dendritic module that packages the Falcon sensor,
runs its systemd service, and exposes all relevant configuration knobs —
without waiting for IT to tell us what their config is.

### WSL2-Specific Context

Two approaches exist for CrowdStrike on WSL2:

1. **Windows-side Falcon plugin** (CS official, Falcon v7.23+, June 2025):
   A Windows sensor plugin extends monitoring into WSL2 without installing
   anything inside the distribution. This is CrowdStrike's recommended path.

2. **Linux sensor inside WSL2** (problematic but sometimes required):
   WSL2 runs `microsoft-standard-WSL2` kernel, which is NOT on CS's supported
   kernel whitelist. Sensor enters **Reduced Functionality Mode (RFM)** — sends
   heartbeats only, no detections. Some enterprises still require installation
   for compliance inventory purposes.

**Our module supports Approach 2** (Linux sensor inside WSL) because:
- Enterprise compliance may mandate agent presence regardless of RFM
- The module is general-purpose NixOS, not WSL-specific
- Approach 1 is a Windows-side concern (outside our NixOS config)
- The module should clearly document the RFM limitation for WSL users

### Technical Architecture (proven community pattern)

```
Package layer:
  falcon-sensor-unwrapped    .deb extraction via dpkg-deb + autoPatchelfHook
                              Dependencies: openssl, libnl, zlib
  falcon-sensor              buildFHSEnv wrapper (unsharePid = false)
                              Exposes: falconctl, falcond, falcon-kernel-check

Service layer:
  systemd.tmpfiles.rules     Creates mutable /opt/CrowdStrike (0750 root root)
  falcon-sensor.service      ExecStartPre: symlink binaries + falconctl -s --cid
                              ExecStart: falcond (via FHS wrapper)
                              Type=forking, PIDFile=/run/falcond.pid

Config layer:
  services.falcon-sensor     NixOS module options (see below)
```

### Module Options Interface

```nix
services.falcon-sensor = {
  enable = lib.mkEnableOption "CrowdStrike Falcon sensor";

  package = lib.mkOption {
    type = lib.types.package;
    description = "Falcon sensor package (.deb source)";
    # No default — user must provide the .deb path or fetchurl
  };

  cid = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "Customer ID (CID). Format: <hex>-<checksum>";
  };

  cidSecretFile = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = ''
      Path to file containing CID (alternative to plaintext cid option).
      Use with SOPS/agenix for secret management.
    '';
  };

  provisioningToken = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "Installation/provisioning token for host registration";
  };

  provisioningTokenSecretFile = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "Path to file containing provisioning token";
  };

  tags = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    example = [ "Environment/Development" "Team/DevTeam" ];
    description = "Sensor grouping tags (max 256 chars combined)";
  };

  backend = lib.mkOption {
    type = lib.types.enum [ "auto" "bpf" "kernel" ];
    default = "bpf";
    description = ''
      Sensor backend. "bpf" recommended for NixOS/WSL (looser kernel
      requirements). "kernel" requires supported kernel whitelist.
    '';
  };

  cloudRegion = lib.mkOption {
    type = lib.types.enum [ "us-1" "us-2" "eu-1" "us-gov-1" "us-gov-2" ];
    default = "us-1";
    description = "CrowdStrike cloud region";
  };

  proxy = {
    enable = lib.mkEnableOption "proxy for Falcon cloud communication";
    host = lib.mkOption { type = lib.types.str; default = ""; };
    port = lib.mkOption { type = lib.types.port; default = 8080; };
  };

  trace = lib.mkOption {
    type = lib.types.enum [ "none" "err" "warn" "info" "debug" ];
    default = "warn";
    description = "Sensor log/trace level";
  };

  autoRemoveAid = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Remove Agent ID (AID) on service start. Enable for golden image
      cloning so each instance gets a unique AID.
    '';
  };
};
```

### File Layout (dendritic pattern)

```
modules/programs/crowdstrike-falcon/
├── crowdstrike-falcon.nix       # Flake module registration
├── _nixos/
│   ├── module.nix               # NixOS service module (options + config)
│   └── package.nix              # Package derivation (.deb extract + FHS)
└── docs/
    └── WSL-LIMITATIONS.md       # RFM warning, Windows plugin recommendation
```

### Integration into Enterprise Layer

Update `wsl-enterprise.nix` to:
1. Replace the 3 stub options (`crowdStrike.{enable,cid,serverUrl}`) with
   imports of the new module: `inputs.self.modules.nixos.crowdstrike-falcon`
2. Set enterprise defaults:
   ```nix
   services.falcon-sensor = {
     enable = lib.mkDefault false;  # Opt-in per enterprise policy
     backend = lib.mkDefault "bpf";
     tags = lib.mkDefault [ "Environment/Enterprise" ];
   };
   ```
3. Remove the warning stub (lines 256-267)

Dev-team layer can add its own tag:
```nix
services.falcon-sensor.tags = [ "Team/DevTeam" ];
```

### Package Source Strategy

The `.deb` is not publicly downloadable (requires Falcon Console auth).
Three options for the `package` option:

1. **`requireFile`** (nixpkgs pattern for proprietary software):
   ```nix
   package = pkgs.requireFile {
     name = "falcon-sensor_7.18.0-17106_amd64.deb";
     sha256 = "...";
     url = "https://falcon.crowdstrike.com/hosts/sensor-downloads";
   };
   ```
   User must manually download and `nix-store --add-fixed` the `.deb`.

2. **Local path**: `package = /path/to/falcon-sensor.deb;`

3. **Corporate artifact server**: `package = builtins.fetchurl { ... };`

Option 1 is the most Nix-idiomatic for proprietary packages. The IT demo
(Task 6) will determine which approach the enterprise prefers.

### Definition of Done

- [ ] `modules/programs/crowdstrike-falcon/` exists with dendritic structure
- [ ] Package derivation extracts `.deb` and wraps with `buildFHSEnv`
- [ ] NixOS module creates systemd service, tmpfiles, falconctl config
- [ ] All options from interface above are implemented
- [ ] `cidSecretFile`/`provisioningTokenSecretFile` work with SOPS paths
- [ ] `autoRemoveAid = true` clears AID on start (golden image support)
- [ ] `wsl-enterprise.nix` stub replaced with real module import
- [ ] `docs/WSL-LIMITATIONS.md` documents RFM and Windows plugin alternative
- [ ] Module evaluates cleanly: `nix flake check --no-build`
- [ ] Service activates in VM test (even if sensor enters RFM)

---

## Task 4: Module Exports & Tag Cleanup (was: Repository Separation)

**Status**: TASK:COMPLETE (2026-03-14)
**Priority**: HIGH — the core enabler for team consumption
**Depends on**: Tasks 1-3 (clean state + CrowdStrike module in place)
**Commit**: `6e5da5e` on `feat/usb-jetson-pa161878`

### Decision: Option A (No Repo Split)

After analysis, decided against repository separation in favor of expanding
exports from the existing single repo. Rationale:

- **Team size**: ~5 people, all direct communication — clean API boundary
  adds overhead without proportional benefit
- **Integration testing**: Personal hosts serve as free integration tests
  for shared modules — single-repo keeps this advantage
- **Maintenance**: No cross-repo lock file coordination, no two-CI-pipeline
  overhead
- **Module consumption works today**: Deferred modules carry their own
  `inputs.self` context, so `inputs.nixcfg.nixosModules.wsl-dev-team`
  resolves its internal import chain correctly
- **Revisit trigger**: Team grows beyond ~10 people, modules consumed by
  teams outside direct communication, or compliance requires separation

### What Was Done

**1. Removed `[nd]` bracket tags from 8 directories**:
- `files [nd]` → `files`
- `git-auth-helpers [nd]` → `git-auth-helpers`
- `github-auth [nd]` → `github-auth`
- `gitlab-auth [nd]` → `gitlab-auth`
- `podman [nd]` → `podman`
- `secrets-management [NDnd]` → `secrets-management`
- `windows-terminal [nd]` → `windows-terminal`
- `thinky-ubuntu [nd]` → `thinky-ubuntu`

The `[nd]` (no-distribute) tag was an obsolete distribution policy marker.
Distribution policy is now determined by presence in `shared-modules.nix`.

**2. Expanded shared-modules.nix from 5 to 47 exports**:
- NixOS: 13 modules (system types, WSL settings, feature modules)
- Home Manager: 25 modules (system type layers, bundles, feature modules)
- Darwin: 9 modules (system types, cross-platform features)

**3. Fixed 2 hardcoded path references** that would break from renames:
- `tests.nix:589`: `"/files [nd]/_homefiles-module.nix"` → `"/files/_homefiles-module.nix"`
- `default.nix:465`: `"/modules/programs/files [nd]/files/glow.yml"` → `"/modules/programs/files/files/glow.yml"`

### Teammate Consumption

```nix
# In teammate's flake.nix:
inputs.nixcfg.url = "github:timblaktu/nixcfg";

# NixOS system config:
imports = [ inputs.nixcfg.nixosModules.wsl-dev-team ];

# Home Manager config:
imports = [ inputs.nixcfg.homeManagerModules.home-dev-team ];

# Or cherry-pick individual modules:
imports = [ inputs.nixcfg.homeManagerModules.shell ];
```

### Definition of Done

- [x] All modules exported in `shared-modules.nix` (47 total)
- [x] `[nd]` tags removed from all directories
- [x] Hardcoded path references fixed
- [x] `nix flake check --no-build` passes
- [x] Pre-commit hooks pass

---

## Task 5: Tarball/Flake Hosting & Distribution

**Status**: TASK:COMPLETE (2026-03-18)
**Priority**: MEDIUM — enables teammate self-service
**Depends on**: Task 4 (shared flake must exist first)
**Commit**: `20d1c00` on `feat/usb-jetson-pa161878`

### Decisions Made

- **Repo**: Public GitHub (`github:timblaktu/nixcfg`)
- **Tarball**: GitHub Releases (GH Actions builds on tag push or manual dispatch)
- **Internal ref cleanup**: COMPLETE (commit `66fb5ca`)
  - All PAC/Code Companion/panasonic.aero refs removed from shared modules
  - lib.nix presets are now deployment-agnostic templates
  - Deployment values moved to pa161878-nixos.nix personal host config
  - GitLab host is now a required option (no default) in dev-team
  - Plan files gitignored, internal-ref docs archived
- **Private flake input**: Deferred — will create `nixcfg-private` repo for
  team deployment values (URLs, BW items) as a follow-up

### What Was Done

1. **release.yml**: Updated to attach `Import-NixOSWSL.ps1` as release asset
   alongside the `.wsl` tarball — teammates get both files from one release page
2. **docs/WSL-TEAM-QUICKSTART.md**: Rewrote acquisition section to point at
   GitHub Releases, added build-from-source and flake-input alternatives,
   removed "received from team lead" language
3. **docs/SHARED-MODULES.md**: Full rewrite — now documents all 47 exports
   (13 NixOS + 25 HM + 9 Darwin) with tables, bundle composition diagram,
   and usage examples for WSL/vanilla/server/Proxmox scenarios
4. CI/CD pipeline already complete from prior sessions:
   - `ci.yml`: Tarball builds on every PR (3 configs)
   - `release.yml`: Builds + releases `nixos-wsl-dev-team` tarball on version tag
   - `auto-tag.yml`: Creates tag when VERSION changes on main

### Definition of Done

- [x] Shared flake hosted and accessible to team members
- [x] Pre-built tarball available via documented channel (GitHub Releases)
- [x] `docs/WSL-TEAM-QUICKSTART.md` updated with download URLs
- [x] `docs/SHARED-MODULES.md` reflects current module interfaces
- [x] Team member can go from zero to working WSL in documented steps

---

## Task 6: IT Demonstration & CrowdStrike Handoff

**Status**: TASK:PENDING
**Priority**: HIGH — gates production CrowdStrike activation
**Depends on**: Tasks 3-5 (module built, image distributable)

### Objective

Demonstrate the Falcon-enabled NixOS-WSL dev-team image to IT security.
Show them what we've built and collect the enterprise-specific configuration
they need to provide for production activation.

### What We Demonstrate

1. **The NixOS-WSL image** with CrowdStrike module baked in
2. **Declarative configuration**: Show how `services.falcon-sensor.*` options
   work — CID, tags, backend, proxy, provisioning token
3. **Golden image support**: `autoRemoveAid = true` ensures unique AID per clone
4. **SOPS integration**: CID and provisioning token can be encrypted at rest
5. **Sensor grouping tags**: Team/environment tagging for policy assignment
6. **RFM transparency**: Explain that WSL2's custom kernel causes RFM,
   recommend their Windows-side Falcon plugin (v7.23+) for actual detection
7. **The alternative**: Windows Falcon plugin approach for WSL2 visibility

### What We Need From IT

Prepare this checklist for the IT meeting:

| Item | Description | How We Use It |
|------|-------------|---------------|
| **CID** | Customer ID for our Falcon tenant | `services.falcon-sensor.cid` or SOPS secret |
| **Provisioning token** | Token for host registration | `services.falcon-sensor.provisioningToken` or SOPS |
| **Cloud region** | Which CS cloud (us-1, us-2, eu-1, gov) | `services.falcon-sensor.cloudRegion` |
| **Proxy config** | If CS traffic must traverse proxy | `services.falcon-sensor.proxy.*` |
| **Sensor `.deb`** | Download URL or artifact path | `services.falcon-sensor.package` |
| **Sensor version policy** | Pin to specific version or auto-update? | Package version in derivation |
| **Tag conventions** | Required tags for compliance grouping | `services.falcon-sensor.tags` |
| **Backend preference** | bpf vs kernel vs auto | `services.falcon-sensor.backend` |
| **Windows plugin status** | Is Falcon v7.23+ deployed on Windows hosts? | Determines if Linux sensor is compliance-only |
| **Maintenance token** | Anti-tamper token (v7.20+ if enabled) | Future option addition |

### Preparation Artifacts

- [ ] Slide deck or live-demo script showing the configuration flow
- [ ] Running WSL instance with Falcon service active (even in RFM)
- [ ] `falconctl -g --rfm-state --version --aid` output to show IT
- [ ] `docs/WSL-LIMITATIONS.md` polished for IT audience
- [ ] Configuration template showing what IT needs to fill in

### Definition of Done

- [ ] IT meeting completed
- [ ] CID and provisioning token received (or SOPS-encrypted path agreed)
- [ ] Cloud region and proxy config confirmed
- [ ] Sensor `.deb` download path established
- [ ] Tag conventions documented
- [ ] Any follow-up items captured as new tasks

---

## Execution Notes

- **One task per session** per session workflow protocol
- Tasks 1-2 are independent of each other (could parallelize across sessions)
- Task 3 can start during Tasks 1-2 (no hard dependency on files/username for module creation)
- Task 4 depends on Tasks 1-3 being complete
- Task 5 depends on Task 4
- Task 6 depends on Tasks 3-5

### Dependency Graph

```
Task 1 (Files) ──────┐
                      ├──> Task 4 (Repo Sep) ──> Task 5 (Hosting) ──┐
Task 2 (Username) ────┘                                              ├──> Task 6 (IT Demo)
                                                                     │
Task 3 (CrowdStrike) ── integrates into enterprise layer ───────────┘
```

Task 3 (CrowdStrike) has no dependency on Tasks 1-2. It can proceed in
parallel. However, the module must be in place before repo separation
(Task 4) so it moves to the shared flake with everything else.
