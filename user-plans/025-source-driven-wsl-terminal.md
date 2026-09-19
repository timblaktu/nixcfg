# Plan 025: Source-Driven WSL Terminal Integration

**Created**: 2026-02-15 19:48 PST
**Branch**: `refactor/dendritic-pattern`
**Status**: PLANNING
**Depends on**: Plan 024 (immediate fixes), Plan 023 (distributable images)

## Vision

All WSL/Terminal integration artifacts — Import script, fragment templates, GUID computation,
Terminal profile configs — are **generated from Microsoft's open-source Terminal and WSL
repositories** via Nix derivations. Build-time extraction + validation ensures correctness.
Constants never silently diverge from upstream.

## Problem Statement

Current state has six categories of fragility:

1. **Wrong namespace GUID** — Import script uses Terminal's `{2bde4a90-...}` but WSL uses
   `{BE9372FE-...}` for Tier 2 profile GUIDs
2. **Wrong computation input** — Script computes GUID from distro name but WSL computes from
   registry GUID (random, assigned at import time)
3. **Scattered constants** — GUIDs, encodings, and format strings are hardcoded across
   Import-NixOSWSL.ps1, wsl-enterprise.nix, windows-terminal.nix, and architecture docs
4. **Unvalidated fragment structure** — Fragment JSON is hand-authored, not verified against
   what `_CreateTerminalProfile` actually writes
5. **Fork divergence risk** — NixOS-WSL fork and HM fork have WSL features that could drift
   from upstream source behavior
6. **No build-time validation** — Errors only discovered at runtime on actual Windows machines

## Progress

| Task | Status | Commit | Description |
|------|--------|--------|-------------|
| Phase 0: Constants package | TASK:PENDING | | Extract, cross-validate, test-vector-verify |
| Phase 1: Script generation | TASK:PENDING | | Template Import-NixOSWSL.ps1 from constants |
| Phase 2: Tarball integration | TASK:PENDING | | Upstream [windowsterminal] to NixOS-WSL fork |
| Phase 3: HM Terminal module | TASK:PENDING | | Refine windows-terminal module with schema |
| Phase 4: Validation check | TASK:PENDING | | Cross-repo nix flake check |

## Architecture

### Flake Input Additions

```nix
# Read-only source inputs (non-flake, pinned by flake.lock)
terminal-src = { url = "github:microsoft/terminal"; flake = false; };
wsl-src = { url = "github:microsoft/WSL"; flake = false; };
```

### Dependency Graph

```
terminal-src ─┐
              ├──▶ [Phase 0] wsl-terminal-constants ──┬──▶ [Phase 1] import-nixos-wsl (script)
wsl-src ──────┘                                        ├──▶ [Phase 2] tarball integration
                                                       ├──▶ [Phase 3] HM terminal module
                                                       └──▶ [Phase 4] validation check
```

### Integration Surface (current state)

**nixcfg-dendritic** (this repo):
- `modules/system/settings/wsl-enterprise/` — Tarball builder override, [windowsterminal]
- `modules/programs/windows-terminal [nd]/` — HM settings.json merging
- `docs/tools/Import-NixOSWSL.ps1` — Import script (hardcoded wrong GUIDs)
- `docs/tools/TERMINAL-PROFILE-ARCHITECTURE.md` — Architecture doc

**NixOS-WSL fork** (`github:timblaktu/NixOS-WSL/plugin-shim-integration`):
- `modules/build-tarball.nix` — Tarball builder (no [windowsterminal] support)
- `modules/wsl-distro.nix` — Core WSL module
- `modules/wsl-bare-mount.nix` — Bare disk mounting (fork feature)
- `modules/wsl-plugin-config.nix` — Plugin config (fork feature)

**home-manager fork** (`github:timblaktu/home-manager/wsl-windows-terminal`):
- `modules/targets/wsl/default.nix` — Windows env, tools, path conversion
- `modules/targets/wsl/bind-mount-root.nix` — WSL bind mount
- Terminal settings management (feat commits)

**Microsoft sources** (to become flake inputs):
- `~/src/terminal` — GUIDs in DynamicProfileUtils, WslDistroGenerator, Profile.cpp
- `~/src/WSL` — WslTerminalNamespace in wslutil.h, _CreateTerminalProfile in LxssUserSession.cpp

---

## Phase 0: Constants Package

**Goal**: Single source of truth for all GUID constants, extracted from Microsoft source.

**Package**: `pkgs/wsl-terminal-constants/`

### What to Extract

From `wsl-src/src/windows/common/wslutil.h`:
- `WslTerminalNamespace` = `{BE9372FE-59E1-4876-BDA9-C33C8F2F1AF1}`
- `GeneratedProfilesTerminalNamespace` = `{2bde4a90-d05f-401c-9492-e40884ead1d8}`

From `terminal-src` (locations TBD during implementation):
- `TERMINAL_PROFILE_NAMESPACE_GUID` (should match WSL's GeneratedProfilesTerminalNamespace)
- `RUNTIME_GENERATED_PROFILE_NAMESPACE_GUID` (for fragment-sourced profiles)
- Fragment JSON schema fields

From `wsl-src/src/shared/inc/stringshared.h`:
- `GUID_FORMAT_STRING` = `{%08x-%04hx-%04hx-%02x%02x-%02x%02x%02x%02x%02x%02x}`

### Cross-Validation Rules

1. WSL's `GeneratedProfilesTerminalNamespace` == Terminal's `TERMINAL_PROFILE_NAMESPACE_GUID`
2. Both repos use same UUIDv5 algorithm (SHA1-based, RFC 4122)
3. Both use UTF-16LE encoding for input strings (no null terminator)

### Test Vectors

Empirically verified GUIDs (must pass build-time validation):

**Tier 1 (name-based, Terminal namespace)**:
- Input: UTF-16LE("NixOS"), NS: `{2bde4a90-...}` → Expected: (capture from thinky)
- Input: UTF-16LE("archlinux"), NS: `{2bde4a90-...}` → Expected: (capture from thinky)

**Tier 2 (registry-GUID-based, WSL namespace)**:
- These require knowing the registry GUID, so we need to capture test data from a
  real system. Format: `UUIDv5({BE9372FE-...}, UTF-16LE("{registry-guid}"))` → profile GUID.

### Output

`$out/constants.json`:
```json
{
  "wslTerminalNamespace": "BE9372FE-59E1-4876-BDA9-C33C8F2F1AF1",
  "generatedProfilesNamespace": "2bde4a90-d05f-401c-9492-e40884ead1d8",
  "guidFormat": "lowercase-braces",
  "inputEncoding": "UTF-16LE",
  "tier2Input": "registry-guid-string",
  "tier1Input": "distro-name",
  "terminalSourceRev": "<commit-sha>",
  "wslSourceRev": "<commit-sha>"
}
```

`$out/validate.py` — standalone validator for offline use

### Definition of Done
- [ ] Constants extracted from source headers via grep/sed
- [ ] Cross-validation passes (matching constants)
- [ ] Test vector validation passes
- [ ] `nix build '.#wsl-terminal-constants'` succeeds
- [ ] constants.json contains all required fields with provenance

---

## Phase 1: Import Script Generation

**Goal**: Import-NixOSWSL.ps1 generated from template with correct constants.

### Changes

1. **New template**: `pkgs/wsl-terminal-constants/Import-NixOSWSL.ps1.template`
   - `@WSL_TERMINAL_NAMESPACE@` → `{BE9372FE-...}` (from constants)
   - `@GENERATED_PROFILES_NAMESPACE@` → `{2bde4a90-...}` (from constants)
   - `@SOURCE_TERMINAL_REV@` → commit SHA (provenance)
   - `@SOURCE_WSL_REV@` → commit SHA (provenance)

2. **New function**: `Get-DistroRegistryGuid`
   - Reads `HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\*`
   - Finds subkey where `DistributionName` matches
   - Returns the subkey name (which IS the registry GUID)

3. **Updated function**: `Get-TerminalProfileGuid`
   - Now accepts `$RegistryGuid` parameter (not `$DistroName`)
   - Uses `@WSL_TERMINAL_NAMESPACE@` (not Terminal's namespace)
   - Computes `UUIDv5(WslTerminalNamespace, UTF-16LE(registryGuidString))`

4. **Updated flow**: After `wsl --import`:
   - Read registry GUID via `Get-DistroRegistryGuid`
   - Compute Tier 2 GUID via updated `Get-TerminalProfileGuid`
   - Compute hide GUID via `UUIDv5(@GENERATED_PROFILES_NAMESPACE@, UTF-16LE(distroName))`
   - Write fragment with both `guid` and `updates` entries

5. **Companion utility**: `Compute-WslProfileGuid.ps1`
   - Standalone tool for debugging/verification
   - Accepts: `-RegistryGuid` (computes Tier 2) or `-DistroName` (computes Tier 1)

### Definition of Done
- [ ] Template generates correct script via `substituteAll`
- [ ] `Get-DistroRegistryGuid` reads Lxss registry correctly
- [ ] Tier 2 GUID computation matches WSL's _CreateTerminalProfile output
- [ ] Fragment JSON structure matches WSL's output
- [ ] `nix build '.#import-nixos-wsl'` produces working script
- [ ] Checked-in reference copy validated by `nix flake check`

---

## Phase 2: Tarball Integration (NixOS-WSL Fork)

**Goal**: Upstream [windowsterminal] support to NixOS-WSL fork, remove wsl-enterprise workaround.

### NixOS-WSL Fork Changes

1. **New option**: `wsl.terminal.profileTemplate`
   - Type: `types.nullOr types.path`
   - Default: null
   - Description: Path to JSON file for Terminal profile customization

2. **Updated**: `build-tarball.nix`
   - Generate [windowsterminal] section in wsl-distribution.conf when profileTemplate is set
   - Install profile template file to /etc/wsl-terminal-profile.json

3. **Updated**: `wsl-distro.nix`
   - Add terminal-related options

### nixcfg Changes

1. **Remove**: Tarball builder override in `wsl-enterprise.nix`
   - Currently `lib.mkForce` overrides entire tarball builder
   - Replace with: `wsl.terminal.profileTemplate = generatedTemplate;`

2. **Generate**: `wsl-terminal-profile.json` from constants package
   - Fragment fields derived from _CreateTerminalProfile source analysis
   - Validated at build time

### Definition of Done
- [ ] NixOS-WSL fork has `wsl.terminal.profileTemplate` option
- [ ] wsl-distribution.conf includes [windowsterminal] when configured
- [ ] wsl-enterprise.nix uses upstream option instead of tarball builder override
- [ ] Generated profile template matches what WSL expects
- [ ] Fork changes are clean enough for upstream PR

---

## Phase 3: Home Manager Terminal Module Refinement

**Goal**: Refine windows-terminal HM module with source-derived knowledge.

### Changes

1. **Settings path discovery**: Use constants for Terminal LocalState paths
2. **Profile GUID awareness**: Module can compute expected GUIDs for distros
3. **Schema validation**: Settings merge validated against Terminal's accepted fields
4. **targets.wsl integration**: GUID functions available to other HM modules

### Dependencies
- Needs constants from Phase 0
- Needs HM fork `wsl-windows-terminal` branch
- Lower priority than Phases 0-2

### Definition of Done
- [ ] windows-terminal module uses constants package for any hardcoded values
- [ ] Settings merge logic tested against Terminal's schema
- [ ] targets.wsl exposes GUID computation for other modules

---

## Phase 4: Validation Check

**Goal**: `nix flake check` validates all integration points are consistent.

### Checks

1. **Constants extraction**: Source parsing still works (format hasn't changed)
2. **Cross-validation**: Matching constants between Terminal and WSL sources
3. **Test vectors**: Known GUID computations produce expected results
4. **Consistency**: All consumers (Import script, enterprise module, HM module) use
   same constants from same source
5. **Reference file**: Checked-in Import-NixOSWSL.ps1 matches generated version

### Definition of Done
- [ ] `nix flake check --no-build` includes wsl-terminal validation
- [ ] Validation catches deliberate constant mismatch (negative test)
- [ ] All integration points verified consistent

---

## Data Collection Needed

Before Phase 0 implementation, we need empirical data from a running Windows system:

1. **Registry GUID for NixOS distro** on thinky:
   `Get-ChildItem "HKCU:\...\Lxss" | Get-ItemProperty | Where DistributionName -eq "NixOS"`

2. **Corresponding Terminal profile GUID** from settings.json or fragment

3. **Verify**: `UUIDv5({BE9372FE-...}, UTF-16LE("{registry-guid}"))` == profile GUID

4. **Terminal source file locations**: Exact paths for namespace constants in Terminal repo

This data validates the extraction approach before we build the derivation.

---

## Risk Assessment

**Low risk**: Constants extraction (stable C++ header format, simple grep)
**Low risk**: UUIDv5 computation (standard RFC 4122, well-understood)
**Medium risk**: Terminal source structure changes (mitigated by build-time validation)
**Medium risk**: NixOS-WSL upstream acceptance of [windowsterminal] feature
**Low risk**: Repo size as flake inputs (~300MB Terminal, ~100MB WSL, cached by Nix)
