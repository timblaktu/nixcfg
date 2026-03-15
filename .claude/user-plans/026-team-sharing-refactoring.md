# Plan 026: Team-Sharing Refactoring — Files, Username, CrowdStrike, Repo Split, Distribution

**Branch**: TBD (create from main at task start)
**Created**: 2026-03-14
**Predecessor**: Plan 023 (Distributable WSL Images — COMPLETE)
**Deferred from**: Plan 019 (Dendritic Migration — tasks F5, F1)

## Objective

Complete the remaining refactoring and feature work needed to make nixcfg's
shared modules cleanly consumable by tiger-team members, including a
production-ready CrowdStrike Falcon integration. Culminates in a
demonstration to IT showing the team WSL image with Falcon baked in.

## Progress Table

| Task | Category | Status | Validation | Description |
|------|----------|--------|------------|-------------|
| 1 | Files Module | TASK:COMPLETE | `nix flake check --no-build` + HM dry-run | Refactor files module anti-patterns (F5) |
| 2 | Username DRY | TASK:COMPLETE | `nix flake check --no-build` + HM dry-run | Centralize hardcoded username refs (F1) |
| 3 | CrowdStrike | TASK:COMPLETE | Module evals, service activates in VM test | Build Falcon sensor dendritic module |
| 4 | Repo Separation | TASK:PENDING | Both flakes pass `nix flake check --no-build` | Split shared modules into separate flake |
| 5 | Tarball Hosting | TASK:PENDING | Teammates can `nix build` or `wsl --import` | Establish distribution channel for team tarball |
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

`config.meta.username` is `readOnly = true` at the flake level. For tiger-team
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
    example = [ "Environment/Development" "Team/TigerTeam" ];
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

Tiger-team layer can add its own tag:
```nix
services.falcon-sensor.tags = [ "Team/TigerTeam" ];
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

## Task 4: Repository Separation

**Status**: TASK:PENDING
**Priority**: HIGH — the core enabler for team consumption
**Depends on**: Tasks 1-3 (clean state + CrowdStrike module in place)

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
  onedrive, shell-utils, yazi, terminal, crowdstrike-falcon
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

**4a. Create shared flake** with import-tree structure mirroring current layout
**4b. Move classified modules** (copy, not git-filter-branch — history stays)
**4c. Update personal flake** to consume shared as `inputs.nixcfg-team`
**4d. Update cross-references**: `inputs.self.modules.nixos.wsl-tiger-team`
     becomes `inputs.nixcfg-team.modules.nixos.wsl-tiger-team`
**4e. Split test infrastructure**: Shared flake gets module-level tests,
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

## Task 5: Tarball/Flake Hosting & Distribution

**Status**: TASK:PENDING
**Priority**: MEDIUM — enables teammate self-service
**Depends on**: Task 4 (shared flake must exist first)

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

## Task 6: IT Demonstration & CrowdStrike Handoff

**Status**: TASK:PENDING
**Priority**: HIGH — gates production CrowdStrike activation
**Depends on**: Tasks 3-5 (module built, image distributable)

### Objective

Demonstrate the Falcon-enabled NixOS-WSL tiger-team image to IT security.
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
