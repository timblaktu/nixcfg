# Plan 024: Terminal Fragment Integration in Import-NixOSWSL.ps1

**Branch**: `refactor/dendritic-pattern`
**Created**: 2026-02-15
**Status**: COMPLETE

## Context

WSL's `wsl --import` has known bugs (microsoft/WSL#13064, #13129, #13339) where it
fails to create the fragment file that Terminal needs for profile discovery. This causes
ghost "Profile no longer detected" entries. Manual fragment creation was confirmed working
on thinky.

## Progress

| Task | Status | Commit | Notes |
|------|--------|--------|-------|
| Implement helper functions | TASK:COMPLETE | 429c1b7 | UUIDv5, fragment dir, profile GUID |
| Fragment creation function | TASK:COMPLETE | 429c1b7 | New-TerminalFragment reads /etc/wsl-terminal-profile.json |
| Enhanced cleanup function | TASK:COMPLETE | 429c1b7 | Remove-StaleTerminalArtifacts replaces old function |
| Update script flow | TASK:COMPLETE | 429c1b7 | Fragment creation after verify, updated summary |
| Update debug doc | TASK:COMPLETE | 429c1b7 | TERMINAL-PROFILE-DEBUG.md marked RESOLVED |
| Fix [byte[]] cast | TASK:COMPLETE | 6611b89 | PS array slice returns [object[]], GUID needs [byte[]] |
| Fix UNC path CWD | TASK:COMPLETE | 131c0fd | Added --cd / to wsl invocations |
| Fix Get-DistroGuid return | TASK:COMPLETE | 6328d67 | return inside ForEach-Object emits to pipeline, doesn't return |
| Use Terminal WSL namespace | TASK:COMPLETE | 3f0fd41 | Match Terminal's dynamic GUID generation |
| Hybrid GUID lookup | TASK:COMPLETE | 37833f2 | Dynamic lookup first, namespace fallback |
| Use fragment updates field | TASK:COMPLETE | f78cedb | Modify dynamic profile instead of creating new one |
| Fix UTF-16LE encoding | TASK:COMPLETE | 59d7a3c | ROOT CAUSE: Terminal uses UTF-16LE, we used UTF-8 |
| Architecture doc | TASK:COMPLETE | 59d7a3c | TERMINAL-PROFILE-ARCHITECTURE.md |
| Find WSL GUID namespace | TASK:COMPLETE | | Found: {BE9372FE-59E1-4876-BDA9-C33C8F2F1AF1}, input=registry GUID not name |
| Fix fallback GUID computation | TASK:COMPLETE | | Tier 2 from registry GUID, WSL-style fragment with guid+source+hide |
| Clean state.json orphans | TASK:COMPLETE | | Compute all GUID variants (Tier 1, UTF-8, old Tier 2) + scan fragments |
| Update architecture doc | TASK:COMPLETE | | Two-tier system, Modern flag, scenario matrix, debugging (2026-02-16) |
| Fix PS 5.1 string compat | TASK:COMPLETE | 3b3ee75, b8552b7 | `1GB` and `($var ...)` inside strings break PS 5.1 parser |
| PS 5.1 encoding guardrails | TASK:COMPLETE | f643b1a, b1cd13e, 718c2c4 | BOM, single-quote GB, UTF-8 I/O, flake check |
| End-to-end validation | TASK:COMPLETE | | Validated: clean reimport, no ghost profiles, single dropdown entry |
| Fix ghost profile bug | TASK:COMPLETE | 53bee7d, 997a8d3, 3a2fd6f | Root cause: wsl --import re-adds to state.json. Fix: post-import orphan sweep |
| Investigate tarball size | TASK:COMPLETE | 7743bc5 | Disabled Mesa/LLVM: 2.6→1.8 GiB closure (800 MiB saved) |

## Commits (in order)

1. `429c1b7` — Main implementation: 6 new functions, enhanced cleanup, fragment creation
2. `6611b89` — Fix: `[byte[]]` cast for GUID constructor (PS array slice returns `[object[]]`)
3. `131c0fd` — Fix: `--cd /` on wsl commands to avoid UNC path translation errors
4. `6328d67` — Fix: `Get-DistroGuid` returning `@("{guid}", $null)` due to `return` inside `ForEach-Object`
5. `6f97973` — Plan 024 tracking document
6. `3f0fd41` — Use Terminal's WSL namespace GUID for profile computation
7. `37833f2` — Hybrid GUID lookup: dynamic first, namespace fallback
8. `f78cedb` — Use fragment `updates` field instead of `guid` + `source`
9. `59d7a3c` — Fix UTF-16LE encoding (root cause), add architecture doc
10. `8223a0f` — Fix fallback GUID to use WSL Tier 2 computation (registry GUID input)
11. `293c159` — Clean orphaned GUIDs from state.json generatedProfiles
12. `0811e2e` — Rewrite Terminal architecture doc with two-tier GUID system
13. `901b4ce` — Record pre-flight snapshot for end-to-end validation
14. `3b3ee75` — Fix `1GB` constant inside string interpolation for PS ISE compat
15. `b8552b7` — Fix `($var ...)` string interpolation for PS 5.1 compat
16. `f643b1a` — Use single-quoted strings for PS 5.1 GB multiplier quirk
17. `b1cd13e` — Add UTF-8 BOM for PS 5.1 encoding compatibility
18. `718c2c4` — Add PS 5.1 encoding guardrails: BOM enforcement, UTF-8 I/O, flake check
19. `8083d27` — Record first successful import, document ghost profile bug
20. `53bee7d` — Fix ghost profile cleanup via registry GUID liveness check
21. `7743bc5` — Disable Mesa/LLVM for WSL enterprise images (800 MiB closure reduction)

## Root Cause Analysis

### Original Root Cause (encoding — FIXED)

The initial chain of bugs stemmed from **incorrect character encoding** in UUIDv5 GUID
computation. Terminal uses UTF-16LE encoding for the distro name bytes, as documented at
https://learn.microsoft.com/en-us/windows/terminal/json-fragment-extensions

Our `New-UuidV5` used `[System.Text.Encoding]::UTF8`, producing completely different GUIDs.

### Deeper Root Cause (two-tier GUID system — DISCOVERED 2026-02-15)

Analysis of user's actual Terminal state revealed the script's fallback GUID computation
uses the WRONG namespace. There are TWO profile GUID generators:

**Tier 1 — Terminal's built-in WslDistroGenerator** (legacy):
- Namespace: `{2bde4a90-d05f-401c-9492-e40884ead1d8}` (TERMINAL_PROFILE_NAMESPACE_GUID)
- Encoding: UTF-16LE (confirmed in `DynamicProfileUtils.cpp:20`)
- Source: `"Windows.Terminal.Wsl"` (LegacyProfileGeneratorNamespaces.h)
- Since commit `00ff803` (Nov 2024): **SKIPS distros with `Modern=1`** in Lxss registry
- File: `~/src/terminal/src/cascadia/TerminalSettingsModel/WslDistroGenerator.cpp`

**Tier 2 — WSL's own profile provider** (current, closed-source):
- Namespace: **UNKNOWN** — not in Terminal source, must be in `~/src/WSL`
- Source: `"Microsoft.WSL"` (replaces `"Windows.Terminal.Wsl"`)
- Creates fragment files at `Fragments\Microsoft.WSL\`
- Fragments hide Tier 1 GUIDs via `"updates": "{tier1-guid}", "hidden": true`
- Creates new profiles via `"guid": "{tier2-guid}"`

**Empirical evidence** (from user's thinky Terminal state):

| Distro | Tier 1 GUID (Terminal ns) | Tier 2 GUID (WSL ns) | Source |
|--------|--------------------------|---------------------|--------|
| NixOS | `{c397f356-...}` | `{565d4910-...}` | settings.json + fragment |
| archlinux | `{398d4a22-...}` | `{ec57df90-...}` | settings.json + fragment |
| nixos-wsl-tiger-team | `{abf54488-...}` | `{c5fed060-...}` | settings.json |

Tier 1 GUIDs confirmed: `UUIDv5({2bde4a90-...}, name.encode("UTF-16LE"))` matches
the `"hidden": true, "updates"` entries in WSL-created fragment files.

Tier 2 GUIDs confirmed as UUIDv5 (version nibble = 5) but namespace is unknown.
Tested: Terminal ns, Fragment ns (`{f65ddb7e-...}`), all RFC 4122 standard ns, Terminal's
two-step `_GenerateGuidForProfile` algorithm (`Profile.cpp:307-318`). None match.

**Terminal's two-step algorithm** (`Profile.cpp:307-318`):
```cpp
// If source is set, derive namespace from source name first
const auto namespaceGuid = !source.empty() ?
    Utils::CreateV5Uuid(RUNTIME_GENERATED_PROFILE_NAMESPACE_GUID, std::as_bytes(std::span{ source })) :
    RUNTIME_GENERATED_PROFILE_NAMESPACE_GUID;
return { Utils::CreateV5Uuid(namespaceGuid, std::as_bytes(std::span{ name })) };
```
This ALSO doesn't match the WSL GUIDs, confirming WSL uses its own namespace internally.

**Impact on script**:
- **Reimport (existing distro)**: WORKS — `Find-ExistingTerminalProfileGuid` captures correct
  Tier 2 GUID from settings.json BEFORE cleanup. GUID is name-deterministic, so WSL assigns
  the same one after reimport.
- **First import + WSL fragment creation succeeds**: WORKS — dynamic lookup finds GUID from
  WSL's fragment file after import.
- **First import + WSL fragment creation FAILS** (E_UNEXPECTED bug): BROKEN — fallback computes
  Tier 1 GUID `{abf54488-...}`, but no profile with that GUID exists (Modern=1 → Terminal
  skips, WSL failed to create fragment). Fragment's `updates` targets nothing.

**Source repos for investigation**:
- Terminal: `~/src/terminal` (cloned, Tier 1 code confirmed)
- WSL: `~/src/WSL` (cloned 2026-02-15, Tier 2 namespace should be in here)

## Bugs Found and Fixed

### 1. UTF-16LE encoding (59d7a3c) — ORIGINAL ROOT CAUSE
Terminal uses UTF-16LE for name bytes in UUIDv5. We used UTF-8.
**Fix**: `[System.Text.Encoding]::Unicode.GetBytes($Name)` (Unicode = UTF-16LE in .NET)

### 2. Fragment `guid` vs `updates` (f78cedb)
Using `guid` + `source: "Microsoft.WSL"` claims to BE a WSL-generated profile.
Terminal validates against its generator, fails, shows "Profile no longer detected."
**Fix**: Use `updates` field to overlay name/icon/font on the dynamic profile.

### 3. PowerShell `return` inside `ForEach-Object` (6328d67)
`return` inside `ForEach-Object` outputs to pipeline, doesn't return from function.
**Fix**: Use `$result` variable instead.

### 4. Array slice type mismatch (6611b89)
`$hash[0..15]` returns `[object[]]` but `[guid]::new()` requires `[byte[]]`.
**Fix**: Explicit `[byte[]]` cast.

### 5. UNC path CWD translation (131c0fd)
WSL fails to translate UNC CWD to target distro path.
**Fix**: Pass `--cd /` on all wsl invocations.

### 6. Source matching bug (429c1b7, pre-existing)
Old code only matched `source == "Windows.Terminal.Wsl"`, modern WSL uses `"Microsoft.WSL"`.
**Fix**: Match both values.

## Remaining Work (ordered by dependency)

### 1. Find WSL GUID namespace (TASK:COMPLETE)

**FOUND** in `~/src/WSL/src/windows/common/wslutil.h:36-41`:

```cpp
// Namespace GUID used for Windows Terminal profile generation.
// {BE9372FE-59E1-4876-BDA9-C33C8F2F1AF1}
inline constexpr GUID WslTerminalNamespace = {0xbe9372fe, 0x59e1, 0x4876, {0xbd, 0xa9, 0xc3, 0x3c, 0x8f, 0x2f, 0x1a, 0xf1}};

// Namespace GUID for automatically generated Windows Terminal profiles.
// {2bde4a90-d05f-401c-9492-e40884ead1d8}
inline constexpr GUID GeneratedProfilesTerminalNamespace = {0x2bde4a90, 0xd05f, 0x401c, ...};
```

**Critical discovery**: Tier 2 GUID input is NOT the distro name — it's the **stringified
distro registry GUID** from `HKCU\...\Lxss\{GUID}`.

From `LxssUserSession.cpp:2728-2733`:
```cpp
auto distributionIdString = GuidToString<wchar_t>(Registration.Id());
auto distributionProfileId =
    GuidToString<wchar_t>(CreateV5Uuid(WslTerminalNamespace, std::as_bytes(std::span{distributionIdString})));

auto hideGeneratedProfileGuid = WideToMultiByte(GuidToString<wchar_t>(
    CreateV5Uuid(GeneratedProfilesTerminalNamespace, std::as_bytes(std::span{Configuration.Name}))));
```

**Two computations in `_CreateTerminalProfile`**:
- **Tier 2 profile GUID** = `UUIDv5({BE9372FE-...}, UTF-16LE(GuidToString(RegistryGUID)))` — used as `"guid"` in fragment
- **Hide GUID** = `UUIDv5({2bde4a90-...}, UTF-16LE(DistroName))` — used as `"updates": "{hide}", "hidden": true`

The hide GUID intentionally matches Terminal's Tier 1 GUID (same namespace + same input) so
the fragment can hide Terminal's auto-generated profile.

**GUID format**: `{%08x-%04hx-%04hx-%02x%02x-%02x%02x%02x%02x%02x%02x}` (lowercase with braces)

**Implications**:
- Cannot compute Tier 2 GUID from distro name alone
- Registry GUID is random (`CoCreateGuid`) on first import, changes on reimport
- Fallback must read registry GUID AFTER import, then compute
- `DistributionRegistration::Create` at `DistributionRegistration.cpp:59-81`

**Verification pending**: Need to confirm on thinky by reading registry GUID for NixOS distro
and computing `UUIDv5({BE9372FE-...}, GuidString)` to see if it matches `{565d4910-...}`.

### 2. Fix fallback GUID computation (TASK:PENDING)
**Depends on**: Task 1 (COMPLETE)

**New approach** (based on Task 1 findings):

The fallback `Get-TerminalProfileGuid` currently computes Terminal's Tier 1 GUID from the
distro name. This is wrong for modern distros. The correct approach:

1. After `wsl --import`, read the distro's registry GUID from
   `HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\*` by matching `DistributionName`
2. Compute `UUIDv5({BE9372FE-59E1-4876-BDA9-C33C8F2F1AF1}, UTF-16LE(registryGuidString))`
3. Use this as the fragment's `"guid"` field (matching what WSL would have generated)
4. Also compute the hide GUID using Terminal's namespace for the `"updates"` entry

**Implementation**:
- Add `Get-DistroRegistryGuid` function to read from Lxss registry
- Update `Get-TerminalProfileGuid` to accept registry GUID (not distro name)
- Change namespace from `{2bde4a90-...}` to `{BE9372FE-...}`
- Input changes from distro name to `"{registry-guid-string}"`

**File**: `docs/tools/Import-NixOSWSL.ps1:162-169`

### 3. Clean state.json orphans (TASK:PENDING)
Current cleanup only removes `$profileGuid` and `$oldGuid` from `state.json` generatedProfiles.
Stale GUIDs from previous broken computations remain:
- `{a447ed07-...}` (old UTF-8 computation)
- `{abf54488-...}` (Terminal-namespace UTF-16LE computation)

Fix: Also scan `state.json` generatedProfiles for any GUID that appears in fragment files
referencing the distro name, or compute both Tier 1 and Tier 2 GUIDs for cleanup.

**File**: `docs/tools/Import-NixOSWSL.ps1` — `Remove-StaleTerminalArtifacts` function

### 4. Update architecture doc (TASK:COMPLETE — 2026-02-16)
Rewrote `docs/tools/TERMINAL-PROFILE-ARCHITECTURE.md` to document:
- Two-tier GUID system (Terminal Tier 1 vs WSL Tier 2) with dedicated section
- The `Modern=1` registry flag and its effect on WslDistroGenerator
- How WSL fragments hide Tier 1 GUIDs and create Tier 2 profiles
- Scenario matrix showing which cases the script handles correctly
- Correct fallback strategy (registry GUID → dynamic lookup → manual)
- Updated debugging section with Tier 2 GUID computation examples (Python + PowerShell)
- Lxss registry inspection commands
- Three new WSL source references

### 5. End-to-end validation (TASK:IN_PROGRESS — first successful run 2026-02-16)
**Depends on**: Tasks 2, 3, 4

**Results (2026-02-16, attempt 4 — SUCCESS with one bug)**:

Script ran successfully from non-Terminal PS 5.1. Key output:
- Old registry GUID: `{4e647ca3-2129-45bc-bbfd-665ba90cf90f}`
- Dynamic lookup found: `{a447ed07-...}` (UTF-8 bug fragment, NOT the settings.json profile)
- WSL reported: `wsl: Failed to parse terminal profile while registering distribution: E_UNEXPECTED`
  (this is the known WSL bug — our script compensates by creating the fragment manually)
- New registry GUID: `{b5eb1994-8f2b-4ffa-9f76-af7d1357fcd5}`
- Computed Tier 2: `{257e524d-7a8a-54da-af8a-d98658e426a9}`
- Computed Tier 1 hide: `{abf54488-7457-52ae-a6ba-d6fb865401c4}`
- Fragment created at: `Fragments\Microsoft.WSL\nixos-wsl-tiger-team.json`
- Distro responds: user=dev (correct generic user)

Verification results:
1. ✅ Fragment file created with correct structure (guid + updates/hidden)
2. ✅ Old fragment `{a447ed07-...}.json` removed
3. ✅ 2 orphans removed from state.json (`{abf54488-...}` and `{a447ed07-...}`)
4. ✅ New Tier 2 GUID `{257e524d-...}` added to state.json (by Terminal on restart)
5. ✅ "NixOS Tiger Team" appears in Terminal dropdown, launches correctly
6. ✅ Enterprise welcome message displayed, `setup-username` ready
7. ❌ **BUG: Ghost profile** — old `{c5fed060-...}` NOT removed from state.json
   - Shows as second "NixOS Tiger Team" with "Profile no longer detected" warning
   - Root cause: `{c5fed060-...}` is Tier 2 from an OLDER registry GUID (pre-`{4e647ca3-...}`)
   - Script computes Tier 2 from the MOST RECENT old registry GUID only (line 491-492)
   - After 2+ reimports, Tier 2 GUIDs from earlier imports accumulate as orphans
   - **Fix needed**: Also scan settings.json for profiles matching distro NAME and add
     those GUIDs to the removal list (not just computed GUIDs)

Post-import state.json (7 entries, was 8):
- `{2c4de342-...}` — Ubuntu (KEPT)
- `{51855cb2-...}` — Ubuntu Canonical (KEPT)
- `{257e524d-...}` — NEW tiger-team Tier 2 (ADDED by Terminal)
- `{565d4910-...}` — NixOS (KEPT)
- `{ec57df90-...}` — archlinux (KEPT)
- `{e0b90a16-...}` — Unknown (KEPT)
- `{c5fed060-...}` — OLD tiger-team Tier 2 (MISSED — bug)

**Test vector data captured for Plan 025**:
- Registry GUID `{b5eb1994-8f2b-4ffa-9f76-af7d1357fcd5}` → Tier 2 `{257e524d-7a8a-54da-af8a-d98658e426a9}`
- Distro name `nixos-wsl-tiger-team` → Tier 1 hide `{abf54488-7457-52ae-a6ba-d6fb865401c4}`

**Pre-flight snapshot (2026-02-16, BEFORE reimport)**:

WSL distros:
- `nixos-wsl-tiger-team` — exists, Stopped, WSL2
- Also: Ubuntu (Stopped), NixOS (Running), archlinux (Stopped)

state.json generatedProfiles (8 GUIDs):
- `{2c4de342-...}` — Ubuntu (KEEP)
- `{51855cb2-...}` — Ubuntu Canonical (KEEP)
- `{ec57df90-...}` — archlinux (KEEP)
- `{565d4910-...}` — NixOS (KEEP)
- `{e0b90a16-...}` — Unknown, not tiger-team (KEEP)
- `{c5fed060-7621-587d-9b50-aa961ca39cc1}` — tiger-team current Tier 2 (REMOVE — old registry GUID)
- `{abf54488-7457-52ae-a6ba-d6fb865401c4}` — orphan Terminal-ns UTF-16LE (REMOVE)
- `{a447ed07-64a8-5930-ab30-6de825641afc}` — orphan UTF-8 bug (REMOVE)

Fragment files (Fragments\Microsoft.WSL\):
- `{565d4910-...}.json` — NixOS (KEEP)
- `{ec57df90-...}.json` — archlinux (KEEP)
- `{a447ed07-64a8-5930-ab30-6de825641afc}.json` — tiger-team OLD (REMOVE)

settings.json tiger-team profile:
- GUID: `{c5fed060-7621-587d-9b50-aa961ca39cc1}`
- Name: "NixOS Tiger Team"
- Source: "Microsoft.WSL"
- Hidden: False

**Expected AFTER reimport**:
- state.json: 3 tiger-team GUIDs removed, 1 NEW Tier 2 GUID added (by Terminal on restart)
- Fragments: `{a447ed07-...}.json` removed, `nixos-wsl-tiger-team.json` created
- settings.json: old `{c5fed060-...}` profile removed, new profile via fragment
- Terminal dropdown: "NixOS Tiger Team" appears, no warnings

**Validation attempts (2026-02-16)**:

Attempt 1 — PowerShell ISE:
- Closed Terminal, opened PS ISE, ran script
- FAILED: PS ISE uses PS 5.1 parser, choked on `1GB` inside `$()` in string (line 653)
- Fix: commit `3b3ee75` — extracted `1GB` to separate variable

Attempt 2 — PowerShell ISE (after fix):
- Read file content from ISE confirmed fix was on disk (line 653 showed `$sizeGB`)
- FAILED: Same error. ISE cached the old parsed script despite file change on disk.
- Tried temp-copy workaround (wsl cat → Set-Content $env:TEMP), did not attempt

Attempt 3 — PowerShell from Start Menu shortcut (not Terminal):
- Closed Terminal, launched PowerShell via Start Menu shortcut (goes to folder, click .lnk)
- FAILED: `($sizeGB GB)` in string still triggered PS 5.1 parser — bare `(`
  before `$var` inside double-quoted string causes parser to attempt subexpression
  evaluation, then `GB` after space is unexpected token
- Fix: commit `b8552b7` — use string concatenation `" (" + $sizeGB + " GB)"`
  for ALL similar patterns (lines 587 and 654)

**PS 5.1 parser learnings**:
- `1GB` works fine in standalone expressions, NOT inside `$()` subexpressions in strings
- `"...($var stuff)..."` — bare `(` before `$var` triggers subexpression-like parsing
- Safe patterns: string concatenation (`"x" + $var + "y"`), or `$()` explicit subexpression
- `Win+R → powershell` opens Terminal (due to user's association), NOT conhost
- PS ISE caches parsed scripts — file changes on disk don't invalidate the cache
- Non-Terminal PowerShell launch: Start Menu → Windows PowerShell folder → click shortcut

**Next attempt**: Run script from non-Terminal PowerShell after commit `b8552b7`

**Verification commands to run AFTER successful script execution** (Phase 4):
```powershell
# 4a. Check new fragment
$fragDir = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\Microsoft.WSL"
Get-ChildItem $fragDir
Get-Content "$fragDir\nixos-wsl-tiger-team.json"

# 4b. Check state.json cleanup
$statePath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\state.json"
(Get-Content $statePath -Raw | ConvertFrom-Json).generatedProfiles

# 4c. Read new registry GUID
$lxssPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
Get-ChildItem $lxssPath | ForEach-Object {
    $props = Get-ItemProperty $_.PSPath
    if ($props.DistributionName -eq 'nixos-wsl-tiger-team') {
        Write-Host "Registry key: $($_.PSChildName)"
    }
}

# 4d. Python cross-check (replace REGISTRY_GUID with value from 4c)
wsl -d NixOS --cd / -- python3 -c "
import uuid
ns = uuid.UUID('{BE9372FE-59E1-4876-BDA9-C33C8F2F1AF1}')
reg_guid = 'REGISTRY_GUID'
result = uuid.uuid5(ns, reg_guid.encode('utf-16-le').decode('ascii', errors='surrogateescape'))
print(f'Tier 2 GUID: {{{result}}}')
"
```
Then open Terminal for Phase 5 (dropdown check).

### 6. Fix ghost profile bug (TASK:IN_PROGRESS — 2026-02-16)

**Root cause investigation** (deep dive into WSL source):

The ghost profile `{c5fed060-...}` was NOT removed because the cleanup function fails to
match it by any of its 4 criteria (GUID, profile GUID, name, commandline).

**Discovery: WSL commandline format differs from our script's**

WSL's `_CreateTerminalProfile` (LxssUserSession.cpp:2749-2750) writes:
```
C:\Windows\System32\wsl.exe --distribution-id {registry-guid}
```

Our script's `New-TerminalFragment` (Import-NixOSWSL.ps1:327) writes:
```
wsl.exe -d distroname
```

These are fundamentally different. `--distribution-id` takes the registry GUID directly
(no registry lookup), while `-d` takes the distro name (does registry lookup).
Source: `~/src/WSL/src/windows/inc/wsl.h` defines both:
- `WSL_DISTRO_ARG = "-d"`, `WSL_DISTRO_ARG_LONG = "--distribution"` → name-based
- `WSL_DISTRIBUTION_ID_ARG = "--distribution-id"` → GUID-based

**Why the cleanup regex fails**: Line 441's `wsl.*-d\s+distroname` regex only matches
`-d distroname` format. It does NOT match `--distribution-id {guid}`. Since the ghost
profile was created by WSL (not our script), its commandline uses the `--distribution-id`
format with an old registry GUID that no longer exists.

**Confirmed via Python**: `UUIDv5({BE9372FE-...}, UTF-16LE("{4e647ca3-...}"))` =
`{2822da4b-...}`, NOT `{c5fed060-...}`. So `{c5fed060-...}` is from a 2+-reimport-ago
registry GUID. The Tier 2 computation from `$oldGuid` (line 492) cannot produce it.

**Name mismatch also confirmed**: WSL's `_CreateTerminalProfile` overwrites the template's
name with `Configuration.Name` (distro registry name). But adopted/orphaned profiles may
retain custom names from fragment overlays. "NixOS Tiger Team" ≠ "nixos-wsl-tiger-team".

**Fix implemented** (commit `53bee7d`, 3 parts):

1. **Detect orphaned WSL profiles by registry GUID liveness check**:
   - Build set of currently-registered Lxss GUIDs at function start
   - For settings.json profiles with `--distribution-id {guid}` commandline, check if
     that GUID is still registered
   - If not registered → profile is orphaned → remove from settings.json AND state.json

2. **Track removed profile GUIDs from settings.json cleanup**:
   - Collect GUIDs of all profiles removed in the settings.json phase
   - Feed these GUIDs to the state.json `$guidsToRemove` list

3. **Preserved existing `-d distroname` commandline matching**:
   - Keep existing regex for profiles created by our script
   - New `--distribution-id` matching catches WSL-created profiles

**Known remaining issues** (not blockers):
- `Find-ExistingTerminalProfileGuid` (line 147) has same name-mismatch issue — falls
  through to fragment scan as a workaround. Works but may find wrong GUID.
- Our fragment uses `wsl.exe -d $DistroName` (line 327) while WSL uses
  `wsl.exe --distribution-id {registry-guid}`. Consider aligning in future.

**Awaiting validation**: Next reimport on thinky should show:
- Ghost profile `{c5fed060-...}` removed from both settings.json and state.json
- No "Profile no longer detected" warnings in Terminal dropdown

### 7. Investigate tarball size (TASK:COMPLETE — 2026-02-16)

**Analysis**: Total closure was 2.6 GiB (814 store paths), compressed to 1.78 GB tarball.

**Biggest contributor**: NixOS-WSL unconditionally enables `hardware.graphics.enable = true`,
pulling in Mesa (251 MiB) + LLVM (540 MiB) = ~791 MiB. Unnecessary for CLI-only WSL images
since WSLg provides its own GPU drivers.

**Fix** (commit `7743bc5`):
- `wsl-enterprise.nix`: `hardware.graphics.enable = lib.mkOverride 90 config.wsl-settings.cuda.enable;`
- When CUDA disabled (default): graphics = false → no Mesa/LLVM
- When CUDA enabled: graphics = true + `wsl.useWindowsDriver = true` (auto-wired)
- Personal hosts can override with `hardware.graphics.enable = lib.mkForce true;`

**Result**: Closure reduced from 2.6 GiB → 1.8 GiB (800 store paths). ~800 MiB savings.

**Other findings (not actioned)**:
- QEMU-user-static (253 MiB): binfmt stays in tiger-team (cross-compilation needed)
- Podman (156 MiB): stays in tiger-team (container runtime needed)
- Perl (55 MiB): comes from Git's closure (git-svn, git-send-email), not removable
- nixpkgs source (186 MiB): nix registry reference, standard for NixOS systems

## Key Files

- `docs/tools/Import-NixOSWSL.ps1` — Import script
- `docs/tools/TERMINAL-PROFILE-ARCHITECTURE.md` — How Terminal profiles work (reference doc)
- `docs/tools/TERMINAL-PROFILE-DEBUG.md` — Debug notes (marked RESOLVED)
- `modules/system/settings/wsl-enterprise/wsl-enterprise.nix` — Terminal profile config
- `modules/system/settings/wsl-tiger-team/wsl-tiger-team.nix` — Team overrides

## Reference Source Repos

- `~/src/terminal` — Windows Terminal (MIT, Tier 1 GUID generation confirmed)
- `~/src/WSL` — WSL runtime (open-sourced Nov 2024, Tier 2 GUID generation expected here)

## User's Current Terminal State (thinky, 2026-02-15)

**Installations**: Preview + Unpackaged (no Stable)
- Preview: `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\`
- Unpackaged: `%LOCALAPPDATA%\Microsoft\Windows Terminal\` (Fragments directory only)

**settings.json profiles** (Preview):
- Windows PowerShell `{61c54bbd-...}`, Command Prompt `{0caa0dad-...}`, Azure `{b453ae62-...}`
- Ubuntu WSL `{2c4de342-...}` (hidden), Ubuntu Canonical `{51855cb2-...}`
- NixOS `{565d4910-...}` (default), archlinux `{ec57df90-...}`
- NixOS Tiger Team `{c5fed060-...}`

**state.json generatedProfiles** (Preview):
- Includes both valid and orphaned GUIDs
- Orphans: `{abf54488-...}` (Terminal-ns tiger-team), `{a447ed07-...}` (UTF-8 tiger-team)
- Also unknown: `{e0b90a16-...}` (unidentified, not from current distros)

**Fragment files** (Fragments\Microsoft.WSL\):
- `{565d4910-...}.json` — NixOS (WSL-created, correct)
- `{a447ed07-...}.json` — tiger-team (OUR script, WRONG: uses `guid`+`source`, UTF-8 GUID)
- `{ec57df90-...}.json` — archlinux (WSL-created, correct)
