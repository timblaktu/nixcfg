# Windows Terminal Profile Architecture

How Windows Terminal discovers, generates, and manages WSL profiles — and how
`Import-NixOSWSL.ps1` integrates with this system.

**Last updated**: 2026-02-16

## How Terminal Finds Profiles

Windows Terminal assembles its profile list from four sources, processed in this
order at every startup:

### 1. Dynamic Profile Generators (runtime, not stored in any file)

Terminal has built-in generators that scan the system for shells:

- **WSL generator** (`WslDistroGenerator`): reads `HKCU:\...\Lxss` registry
- **PowerShell generator**: finds PowerShell installations
- **Azure Cloud Shell generator**

Each generator uses a fixed **namespace GUID** and the item name to compute a
deterministic profile GUID via UUIDv5. For WSL:

```
namespace = {2bde4a90-d05f-401c-9492-e40884ead1d8}   (Terminal's internal GUID)
name      = distro name (e.g., "nixos-wsl-tiger-team")
encoding  = UTF-16LE (critical — NOT UTF-8)
result    = UUIDv5(namespace, name.encode("UTF-16LE"))
```

**These profiles exist only in memory.** They are regenerated every time Terminal
starts. If a distro is registered in the Lxss registry, the generator creates a
profile. If not, it doesn't. There is no file to delete.

**Important**: Since Terminal commit `00ff803` (November 2024), the WSL generator
**skips distros with `Modern=1`** in the Lxss registry. All distros imported by
recent WSL versions have `Modern=1`, so Terminal's built-in generator no longer
creates profiles for them. WSL's own fragment-based system (Tier 2) has taken
over profile creation. See [Two-Tier GUID System](#two-tier-guid-system) below.

### 2. Fragment Extensions (JSON files on disk)

Fragments are JSON files that applications install to add or modify profiles.

**Locations** (both checked at every startup):
```
Per-user:    %LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\{app-name}\*.json
Per-machine: C:\ProgramData\Microsoft\Windows Terminal\Fragments\{app-name}\*.json
```

For WSL fragments, the app-name is `Microsoft.WSL`:
```
%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\Microsoft.WSL\*.json
```

Fragments can do two things:

**Add a new profile** (uses `guid` field):
```json
{
  "profiles": [{
    "guid": "{some-new-guid}",
    "name": "My Custom Shell",
    "commandline": "my-shell.exe"
  }]
}
```

**Modify an existing profile** (uses `updates` field):
```json
{
  "profiles": [{
    "updates": "{existing-profile-guid}",
    "name": "Better Name",
    "icon": "C:\\path\\to\\icon.ico",
    "font": { "face": "CaskaydiaMono Nerd Font", "size": 11 }
  }]
}
```

The `updates` field targets a profile by its GUID — typically a dynamic profile
from step 1. Terminal applies the fragment's properties as overrides on top of the
dynamic profile's defaults.

### 3. settings.json (user customizations)

```
Stable:     %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
Preview:    %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json
Unpackaged: %LOCALAPPDATA%\Microsoft\Windows Terminal\settings.json
```

Contains `profiles.list` — an array of profiles the user has customized through
the Settings UI or by editing the JSON directly. Entries here override dynamic and
fragment values for the same GUID.

**Key behavior**: If a user changes font size on a dynamic WSL profile, Terminal
writes a `profiles.list` entry with that GUID and only the changed property. The
rest comes from the dynamic generator + fragments.

### 4. state.json (Terminal's internal bookkeeping)

Same directories as settings.json. Contains:

- `generatedProfiles`: array of GUIDs that Terminal has auto-generated. If a GUID
  is in this list but the corresponding generator no longer produces it, Terminal
  shows **"Profile no longer detected"** with a warning icon.

## Two-Tier GUID System

There are **two independent systems** that generate Terminal profile GUIDs for WSL
distros. Understanding this is essential for creating correct fragment files.

### Tier 1 — Terminal's WslDistroGenerator (legacy)

Terminal's built-in WSL generator computes profile GUIDs from the **distro name**:

| Property | Value |
|----------|-------|
| Namespace | `{2bde4a90-d05f-401c-9492-e40884ead1d8}` |
| Input | distro name (e.g., `"nixos-wsl-tiger-team"`) |
| Encoding | UTF-16LE |
| Source | `"Windows.Terminal.Wsl"` |
| Code | `WslDistroGenerator.cpp` in Terminal source |

```
Tier1GUID = UUIDv5({2bde4a90-...}, distroName.encode("UTF-16LE"))
```

**Since commit `00ff803` (November 2024)**: The generator **skips distros with
`Modern=1`** in the Lxss registry key. All distros imported by recent WSL versions
set `Modern=1`, so Tier 1 profiles are no longer generated for them. The generator
still processes legacy (non-Modern) distros.

Source: `terminal/src/cascadia/TerminalSettingsModel/WslDistroGenerator.cpp`

### Tier 2 — WSL's _CreateTerminalProfile (current)

WSL's own runtime creates fragment files for each distro. These GUIDs are derived
from the **distro's registry GUID** (a random value assigned at import time), not
the distro name:

| Property | Value |
|----------|-------|
| Namespace | `{BE9372FE-59E1-4876-BDA9-C33C8F2F1AF1}` |
| Input | stringified registry GUID (e.g., `"{a1b2c3d4-...}"`) |
| Encoding | UTF-16LE (via `GuidToString<wchar_t>`) |
| Source | `"Microsoft.WSL"` |
| Code | `LxssUserSession.cpp` + `wslutil.h` in WSL source |

```
registryGuid = HKCU:\...\Lxss\{GUID}\  (random, assigned by CoCreateGuid at import)
guidString   = GuidToString(registryGuid)  — lowercase with braces
Tier2GUID    = UUIDv5({BE9372FE-...}, guidString.encode("UTF-16LE"))
```

The registry GUID is **random** — it changes on every reimport (`wsl --unregister`
followed by `wsl --import`). Therefore, the Tier 2 profile GUID also changes on
reimport.

Source: `WSL/src/windows/common/wslutil.h:36-41`,
`WSL/src/windows/wslcore/LxssUserSession.cpp:2728-2733`

### How WSL fragments use both tiers

WSL's `_CreateTerminalProfile` function creates fragment files with **two entries**:

```json
{
  "profiles": [
    {
      "guid": "{tier2-guid}",
      "name": "distro-name",
      "commandline": "wsl.exe -d distro-name",
      "source": "Microsoft.WSL"
    },
    {
      "updates": "{tier1-guid}",
      "hidden": true
    }
  ]
}
```

1. **New profile**: Uses the Tier 2 GUID as the profile's identity. The `source:
   "Microsoft.WSL"` field tells Terminal this profile belongs to WSL's provider.

2. **Hide entry**: Targets the Tier 1 GUID (computed from the distro name using
   Terminal's namespace) and sets `hidden: true`. This suppresses Terminal's
   auto-generated profile, preventing duplicate entries in the dropdown.

The hide GUID intentionally matches Terminal's Tier 1 GUID because it uses the
same namespace (`{2bde4a90-...}`) and the same input (distro name).

### Empirical verification

Example from a working system (thinky, 2026-02-15):

| Distro | Tier 1 GUID | Tier 2 GUID | Notes |
|--------|-------------|-------------|-------|
| NixOS | `{c397f356-...}` | `{565d4910-...}` | Both in settings.json + fragment |
| archlinux | `{398d4a22-...}` | `{ec57df90-...}` | Both in settings.json + fragment |
| nixos-wsl-tiger-team | `{abf54488-...}` | `{c5fed060-...}` | settings.json only |

Tier 1 GUIDs verified: `UUIDv5({2bde4a90-...}, name.encode("UTF-16LE"))` matches
the `"updates": "{...}", "hidden": true` entries in WSL-created fragments.

Tier 2 GUIDs verified: version nibble = 5 (UUIDv5), derive from registry GUID via
`UUIDv5({BE9372FE-...}, registryGuidString.encode("UTF-16LE"))`.

## GUID Encoding: The Critical Detail

Both tiers use **UTF-16LE encoding** for the UUIDv5 name bytes. This is documented
in the [official fragment extension docs](https://learn.microsoft.com/en-us/windows/terminal/json-fragment-extensions):

```python
# Microsoft's example — note the .encode("UTF-16LE")
profileGUID = uuid.uuid5(namespace, "Ubuntu".encode("UTF-16LE").decode("ASCII"))
```

The `.encode("UTF-16LE").decode("ASCII")` trick produces a byte sequence where
each ASCII character is followed by a `\x00` null byte. These bytes are what gets
fed into the SHA-1 hash inside UUIDv5.

**Getting the encoding wrong produces a completely different GUID**, which causes
all downstream matching to fail silently.

Terminal also has a third namespace for fragment-provided profiles:

| Context | Namespace GUID | Used for |
|---------|---------------|----------|
| Tier 1: Terminal generators | `{2bde4a90-d05f-401c-9492-e40884ead1d8}` | WSL, PowerShell auto-profiles |
| Tier 2: WSL runtime | `{BE9372FE-59E1-4876-BDA9-C33C8F2F1AF1}` | WSL fragment profile GUIDs |
| Third-party fragments | `{f65ddb7e-706b-4499-8a50-40313caf510a}` | Plugin-installed profiles |

### PowerShell implementation

```powershell
# WRONG — produces different GUID than Terminal/WSL:
$nameBytes = [System.Text.Encoding]::UTF8.GetBytes($Name)

# CORRECT — matches Terminal and WSL behavior:
$nameBytes = [System.Text.Encoding]::Unicode.GetBytes($Name)  # .NET Unicode = UTF-16LE
```

## The WSL Import Problem

### What WSL does during `wsl --import`

1. Registers the distro in the Lxss registry (new random GUID via `CoCreateGuid`)
2. Attempts to create a fragment file at `Fragments\Microsoft.WSL\{tier2-guid}.json`
3. Reads `wsl-distribution.conf` from the tarball for profile metadata

### The bug (microsoft/WSL#13064, #13129, #13339)

Step 2 frequently fails with `E_UNEXPECTED`:
```
wsl: Failed to parse terminal profile while registering distribution: E_UNEXPECTED
The operation completed successfully.
```

The import itself succeeds, but no fragment file is created. Without the fragment:
- **Modern distros** (`Modern=1`): No profile appears at all — Terminal's Tier 1
  generator skips them, and the Tier 2 fragment is missing.
- **Legacy distros**: Tier 1 provides a bare profile (name only, no icon/font).

### What happens on reimport (unregister + import)

1. `wsl --unregister` removes the distro from the Lxss registry
2. WSL does NOT clean up old fragment files or state.json entries
3. `wsl --import` creates a new Lxss entry with a NEW random registry GUID
4. Because the registry GUID changed, the **Tier 2 GUID also changes** (it's
   derived from the registry GUID, not the distro name)
5. The old Tier 2 GUID is now orphaned — its fragment file still exists on disk,
   and `state.json` still references it

Artifacts from the old registration may persist in:
- Fragment files (orphaned `{old-tier2-guid}.json`)
- `settings.json` (profile entries referencing old Tier 2 GUIDs)
- `state.json` (`generatedProfiles` entries for old Tier 1 and Tier 2 GUIDs)

## How Import-NixOSWSL.ps1 Integrates

### GUID strategy

The script computes the **Tier 2 GUID** from the distro's registry GUID after
import, matching exactly what WSL's `_CreateTerminalProfile` would have generated.
It also computes the Tier 1 hide GUID to suppress Terminal's auto-generated
profile (if any).

**After import** (primary path):
1. Read the distro's registry GUID from `HKCU:\...\Lxss\*` by matching
   `DistributionName`
2. Compute Tier 2 GUID: `UUIDv5({BE9372FE-...}, registryGuidString)`
3. Compute Tier 1 hide GUID: `UUIDv5({2bde4a90-...}, distroName)`
4. Create fragment with `guid` (Tier 2) + `updates`/`hidden` (Tier 1 hide)

**Registry GUID unavailable** (fallback):
1. Dynamic lookup — check if WSL created a fragment despite the bug
2. If found, use `updates`-only overlay on the existing profile
3. If not found, no fragment is created (manual configuration required)

### Cleanup (`Remove-StaleTerminalArtifacts`)

Before reimport, captures the old profile GUID from settings.json/fragments (for
cleanup only), then removes stale artifacts across ALL Terminal installations:

1. **settings.json**: Removes profile entries matching old Lxss GUID, profile
   GUID, distro name + WSL source, or commandline
2. **state.json**: Removes old GUIDs from `generatedProfiles`, including:
   - The old Tier 2 GUID (from dynamic lookup before unregister)
   - The Tier 1 GUID (Terminal namespace + UTF-16LE distro name)
   - Legacy UTF-8 GUID (from initial script version's encoding bug)
   - Old Tier 2 GUID (from previous registry GUID)
   - GUIDs found by scanning fragment files referencing the distro name
3. **Fragment files**: Removes files matching profile GUID (filename) or distro
   name / old Lxss GUID (content scan)

### Fragment creation (`New-TerminalFragment`)

After import + verification:

1. Reads `/etc/wsl-terminal-profile.json` from inside the distro (contains display
   name, font, color scheme from Nix configuration)
2. Locates icon at `%LOCALAPPDATA%\wsl\{distroName}\shortcut.ico`
3. Creates fragment file at `Fragments\Microsoft.WSL\{distroName}.json`

When the registry GUID is available (normal case), the fragment mimics WSL's own
format — a new Tier 2 profile plus a hide entry for Tier 1:

```json
{
  "profiles": [
    {
      "guid": "{tier2-guid-from-registry}",
      "name": "NixOS Tiger Team",
      "commandline": "wsl.exe -d nixos-wsl-tiger-team",
      "source": "Microsoft.WSL",
      "icon": "C:\\Users\\...\\shortcut.ico",
      "font": { "face": "CaskaydiaMono Nerd Font", "size": 11 }
    },
    {
      "updates": "{tier1-hide-guid}",
      "hidden": true
    }
  ]
}
```

When the registry GUID is unavailable (fallback), the fragment uses `updates`
to overlay on whatever profile Terminal or WSL already created:

```json
{
  "profiles": [{
    "updates": "{dynamically-found-guid}",
    "name": "NixOS Tiger Team",
    "icon": "C:\\Users\\...\\shortcut.ico",
    "font": { "face": "CaskaydiaMono Nerd Font", "size": 11 }
  }]
}
```

### Script flow

```
Step 1: Find tarball

Step 2: If distro exists (reimport):
  a. Capture old registry GUID from Lxss
  b. Dynamic GUID lookup from settings.json / fragments (for cleanup)
  c. wsl --unregister
  d. Remove-StaleTerminalArtifacts (settings.json, state.json, fragments)

Step 3: Find WSL storage directory

Step 4: wsl --import (assigns new random registry GUID)

Step 5: Verify (wsl -d <name> --cd / -- echo test)

Step 6: Create Terminal fragment
  a. Read new registry GUID from Lxss
  b. Compute Tier 2 profile GUID from registry GUID
  c. Compute Tier 1 hide GUID from distro name
  d. Remove any WSL-created fragment (we replace with our customized version)
  e. Read /etc/wsl-terminal-profile.json from distro
  f. Write fragment with guid + source + updates/hidden entries

Step 7: Optional: set as default

Step 8: Summary
```

### Scenario matrix

| Scenario | Tier 1 | Tier 2 | Script behavior | Result |
|----------|--------|--------|-----------------|--------|
| Reimport (common) | Skipped (Modern=1) | New GUID from new registry GUID | Computes Tier 2 from registry, creates fragment | Works |
| First import, WSL fragment succeeds | Skipped (Modern=1) | WSL created fragment | Replaces WSL fragment with customized version | Works |
| First import, WSL fragment fails | Skipped (Modern=1) | No fragment | Computes Tier 2 from registry, creates fragment | Works |
| First import, registry read fails | Skipped (Modern=1) | No fragment | Dynamic lookup fallback, may fail | Degraded |
| Legacy distro (no Modern flag) | Generated | May or may not exist | Tier 1 GUID used for updates-only overlay | Works |

## Nix-side Configuration

The tarball includes `/etc/wsl-terminal-profile.json`, generated by the NixOS
module at `modules/system/settings/wsl-enterprise/wsl-enterprise.nix`:

```nix
enterprise.terminal = {
  enable = true;                              # default
  profileName = "NixOS";                      # overridden by tiger-team
  icon = "/etc/nixos.ico";                    # Linux-side path (not used by fragment)
  font = { };                                 # e.g., { face = "CaskaydiaMono Nerd Font"; size = 11; }
  colorScheme = null;                         # e.g., "One Half Dark"
};
```

The tiger-team layer overrides:
```nix
enterprise.terminal.profileName = "NixOS Tiger Team";
enterprise.terminal.font = { face = "CaskaydiaMono Nerd Font"; size = 11; };
```

The resulting JSON inside the tarball:
```json
{"name":"NixOS Tiger Team","icon":"/etc/nixos.ico","font":{"face":"CaskaydiaMono Nerd Font","size":11}}
```

The import script reads this file and uses the `name`, `font`, and `colorScheme`
fields in the fragment. The `icon` field from the JSON is ignored — the script
looks for the Windows-side icon that WSL extracts during import instead.

## Debugging

### Check what Terminal sees

```powershell
# List all fragment files
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments" -Recurse

# Read our fragment
Get-Content "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\Microsoft.WSL\nixos-wsl-tiger-team.json"

# Check state.json for generated profile GUIDs
$state = Get-Content "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\state.json" | ConvertFrom-Json
$state.generatedProfiles

# Check settings.json for profile entries (strip comments first)
$raw = Get-Content "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json" -Raw
$stripped = $raw -replace '(?m)^\s*//.*$', '' -replace '(?<=,)\s*//.*$', ''
($stripped | ConvertFrom-Json).profiles.list | Format-Table name, guid, source, commandline
```

### Compute expected GUIDs (Python)

```python
import uuid

# Tier 1 GUID (Terminal namespace + distro name)
tier1_ns = uuid.UUID("{2bde4a90-d05f-401c-9492-e40884ead1d8}")
distro_name = "nixos-wsl-tiger-team"
tier1 = uuid.uuid5(tier1_ns, distro_name.encode("UTF-16LE").decode("ASCII"))
print(f"Tier 1 (hide): {{{tier1}}}")

# Tier 2 GUID (WSL namespace + registry GUID string)
tier2_ns = uuid.UUID("{BE9372FE-59E1-4876-BDA9-C33C8F2F1AF1}")
registry_guid = "{a1b2c3d4-e5f6-7890-abcd-ef1234567890}"  # from Lxss registry
tier2 = uuid.uuid5(tier2_ns, registry_guid.lower().encode("UTF-16LE").decode("ASCII"))
print(f"Tier 2 (profile): {{{tier2}}}")
```

### Compute expected GUIDs (PowerShell)

```powershell
# Tier 1 (hide GUID) — from distro name
Get-TerminalHideGuid "nixos-wsl-tiger-team"

# Tier 2 (profile GUID) — from registry GUID
$registryGuid = Get-DistroGuid "nixos-wsl-tiger-team"
Get-WslProfileGuid $registryGuid
```

### Check the Lxss registry

```powershell
# List all registered WSL distros with their registry GUIDs
Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath
    [PSCustomObject]@{
        RegistryGuid = $_.PSChildName
        Name         = $p.DistributionName
        Modern       = $p.Modern
        BasePath     = $p.BasePath
    }
} | Format-Table -AutoSize
```

### Common failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| No profile at all | Modern=1 distro, no fragment, Tier 1 skipped | Run Import-NixOSWSL.ps1 to create fragment |
| "Profile no longer detected" | Orphaned GUID in state.json generatedProfiles | Clean state.json or reimport with script |
| Two profiles, same name | Tier 1 not hidden, Tier 2 fragment also exists | Fragment needs `updates`+`hidden` entry for Tier 1 |
| Wrong GUID in fragment | Used UTF-8 instead of UTF-16LE, or wrong namespace | Fix encoding; use correct namespace per tier |
| Profile disappears on reimport | Old Tier 2 GUID orphaned, new one not created | Script handles this — creates fragment with new Tier 2 GUID |
| No icon | WSL didn't extract shortcut.ico | Check `%LOCALAPPDATA%\wsl\{distroName}\` |
| Delete doesn't persist | Fragment recreates profile every Terminal start | Delete the fragment FILE, not just the profile in Settings |

## References

- [Windows Terminal JSON Fragment Extensions](https://learn.microsoft.com/en-us/windows/terminal/json-fragment-extensions) — Official Microsoft docs
- [Windows Terminal Dynamic Profiles](https://learn.microsoft.com/en-us/windows/terminal/dynamic-profiles) — How generators work
- [microsoft/WSL#13064](https://github.com/microsoft/WSL/issues/13064) — Fragment creation fails on import
- [microsoft/WSL#13129](https://github.com/microsoft/WSL/issues/13129) — Related fragment bug
- [microsoft/WSL#13339](https://github.com/microsoft/WSL/issues/13339) — Related fragment bug
- [Terminal source: WslDistroGenerator.cpp](https://github.com/microsoft/terminal/blob/main/src/cascadia/TerminalSettingsModel/WslDistroGenerator.cpp) — Tier 1 GUID generation
- [WSL source: wslutil.h](https://github.com/microsoft/WSL/blob/main/src/windows/common/wslutil.h) — Tier 2 namespace GUID definition
- [WSL source: LxssUserSession.cpp](https://github.com/microsoft/WSL/blob/main/src/windows/wslcore/LxssUserSession.cpp) — `_CreateTerminalProfile` (Tier 2 GUID + fragment creation)
- [Terminal source: Profile.cpp](https://github.com/microsoft/terminal/blob/main/src/cascadia/TerminalSettingsModel/Profile.cpp) — `_GenerateGuidForProfile` two-step algorithm
