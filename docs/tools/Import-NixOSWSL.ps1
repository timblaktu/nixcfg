<#
.SYNOPSIS
    Import a NixOS-WSL tarball into Windows Subsystem for Linux.

.DESCRIPTION
    Automates the import of a NixOS-WSL .wsl tarball by:
    - Auto-detecting where existing WSL distros are stored
    - Creating the target directory alongside existing distros
    - Cleaning up stale Windows Terminal profiles, state entries, and fragment files
    - Importing the tarball via wsl --import
    - Creating a Windows Terminal fragment file for the new profile
    - Optionally setting the new distro as default

    The script computes the correct Windows Terminal profile GUID using WSL's
    two-tier system: Tier 2 GUIDs are derived from the distro's registry GUID
    via UUIDv5({BE9372FE-...}), matching what WSL's _CreateTerminalProfile
    generates. The fragment also hides Terminal's auto-generated Tier 1 profile.
    This works around WSL bugs (microsoft/WSL#13064, #13129, #13339) where
    wsl --import fails to create the fragment file Terminal needs.

.PARAMETER TarballPath
    Path to the .wsl tarball file. If not specified, searches common locations.

.PARAMETER DistroName
    Name for the imported WSL distribution. Default: nixos-wsl-tiger-team

.PARAMETER SetDefault
    If specified, sets the imported distro as the default WSL distribution.

.EXAMPLE
    .\Import-NixOSWSL.ps1 -TarballPath \\wsl$\NixOS\home\tim\src\nixcfg\nixos.wsl
    # Import tarball from a WSL distro's filesystem (most common usage)

.EXAMPLE
    .\Import-NixOSWSL.ps1 -TarballPath C:\Downloads\nixos.wsl -DistroName my-nixos
    # Import from Windows filesystem with custom distro name

.EXAMPLE
    .\Import-NixOSWSL.ps1 -TarballPath \\wsl$\NixOS\home\tim\src\nixcfg-dendritic\nixos.wsl -SetDefault
    # Import and set as default WSL distro

.NOTES
    The -TarballPath is strongly recommended. Auto-detection searches running
    WSL distros for nixos.wsl but UNC path globbing can be unreliable.

    Find your tarball path: the tarball is built in the directory where you
    ran the builder. If you built it in ~/src/nixcfg-dendritic on a distro
    named "NixOS", the Windows path is:
        \\wsl$\NixOS\home\<user>\src\nixcfg-dendritic\nixos.wsl
#>

param(
    [string]$TarballPath,
    [string]$DistroName = "nixos-wsl-tiger-team",
    [switch]$SetDefault
)

$ErrorActionPreference = "Stop"

# ENCODING NOTE: This file requires a UTF-8 BOM (EF BB BF) for PS 5.1 compat.
# Without BOM, PS 5.1 reads as Windows-1252 and byte 0x94 (from UTF-8 em dashes)
# becomes a smart quote that PS treats as a string delimiter.
# The BOM is enforced by the lint-ps1-encoding flake check.
#
# All Get-Content calls below use -Encoding UTF8 because PS 5.1 otherwise
# reads files as Windows-1252. Terminal's JSON files are UTF-8.
# All Set-Content calls use -Encoding UTF8 for the same reason. Note that
# PS 5.1's -Encoding UTF8 writes WITH BOM; PS 7+ writes WITHOUT BOM.

function Write-Status($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)     { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn($msg)   { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err($msg)    { Write-Host "[-] $msg" -ForegroundColor Red }

# --- Helper: Get WSL distro GUID from registry ---
function Get-DistroGuid($name) {
    $lxssPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
    if (-not (Test-Path $lxssPath)) { return $null }

    # NOTE: Do not use 'return' inside ForEach-Object — it outputs to the pipeline
    # but does NOT return from the function, causing the trailing 'return $null'
    # to also emit, producing @("{guid}", $null) instead of just "{guid}".
    $result = $null
    Get-ChildItem $lxssPath | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath
        if ($props.DistributionName -eq $name) {
            $result = $_.PSChildName
        }
    }
    return $result
}

# --- Helper: RFC 4122 UUIDv5 generation (deterministic GUID from namespace + name) ---
function New-UuidV5([guid]$Namespace, [string]$Name, [System.Text.Encoding]$Encoding) {
    # Default to UTF-16LE, matching Terminal and WSL's UUIDv5 implementations.
    # Legacy callers can pass [System.Text.Encoding]::UTF8 to reproduce old (buggy) GUIDs.
    if (-not $Encoding) { $Encoding = [System.Text.Encoding]::Unicode }

    # Convert namespace GUID to bytes in RFC 4122 network byte order
    $nsBytes = $Namespace.ToByteArray()
    # .NET stores first 3 fields in little-endian; RFC 4122 requires big-endian
    [Array]::Reverse($nsBytes, 0, 4)
    [Array]::Reverse($nsBytes, 4, 2)
    [Array]::Reverse($nsBytes, 6, 2)

    # Windows Terminal and WSL use UTF-16LE encoding for name bytes in UUIDv5 generation.
    # See: https://learn.microsoft.com/en-us/windows/terminal/json-fragment-extensions
    # Python equivalent: name.encode("UTF-16LE").decode("ASCII")
    $nameBytes = $Encoding.GetBytes($Name)
    $data = $nsBytes + $nameBytes

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    $hash = $sha1.ComputeHash($data)
    $sha1.Dispose()

    # Set version (5) and variant (RFC 4122)
    $hash[6] = ($hash[6] -band 0x0F) -bor 0x50  # version 5
    $hash[8] = ($hash[8] -band 0x3F) -bor 0x80  # variant 10xx

    # Take first 16 bytes, convert back from network order to .NET GUID order
    # Cast explicitly to [byte[]] — PS array slicing returns [object[]] which [guid]::new() rejects
    [byte[]]$guidBytes = $hash[0..15]
    [Array]::Reverse($guidBytes, 0, 4)
    [Array]::Reverse($guidBytes, 4, 2)
    [Array]::Reverse($guidBytes, 6, 2)

    return [guid]::new($guidBytes)
}

# --- Helper: Find existing Terminal profile GUID for a distro (dynamic lookup) ---
# Scans settings.json and fragment files across all Terminal installations.
# Returns [guid] if found, $null otherwise.
function Find-ExistingTerminalProfileGuid([string]$DistroName) {
    # Check settings.json across all Terminal installations
    foreach ($localState in (Get-AllTerminalLocalStatePaths)) {
        $settingsPath = Join-Path $localState "settings.json"
        if (-not (Test-Path $settingsPath)) { continue }

        $raw = Get-Content $settingsPath -Raw -Encoding UTF8
        $stripped = $raw -replace '(?m)^\s*//.*$', '' -replace '(?<=,)\s*//.*$', ''
        try { $settings = $stripped | ConvertFrom-Json } catch { continue }

        if ($settings.profiles -and $settings.profiles.list) {
            foreach ($p in $settings.profiles.list) {
                if (-not $p.guid) { continue }
                # Match by name + WSL source (both old and new source values)
                if ($p.name -eq $DistroName -and ($p.source -eq "Windows.Terminal.Wsl" -or $p.source -eq "Microsoft.WSL")) {
                    return [guid]($p.guid.Trim('{}'))
                }
                # Match by commandline
                if ($p.commandline -and $p.commandline -match "wsl.*-d\s+$([regex]::Escape($DistroName))") {
                    return [guid]($p.guid.Trim('{}'))
                }
            }
        }
    }

    # Check existing fragment files for one referencing this distro
    $fragmentDir = Get-TerminalFragmentDir
    if (Test-Path $fragmentDir) {
        foreach ($file in (Get-ChildItem $fragmentDir -Filter "*.json" -ErrorAction SilentlyContinue)) {
            try {
                $content = Get-Content $file.FullName -Raw -Encoding UTF8
                if ($content -match [regex]::Escape($DistroName)) {
                    $frag = $content | ConvertFrom-Json
                    if ($frag.profiles -and $frag.profiles.Count -gt 0 -and $frag.profiles[0].guid) {
                        return [guid]($frag.profiles[0].guid.Trim('{}'))
                    }
                }
            } catch { }
        }
    }

    return $null
}

# --- Helper: Compute WSL Tier 2 profile GUID from registry GUID ---
# WSL computes fragment profile GUIDs from the distro's registry GUID (random,
# assigned at import time), NOT from the distro name. Uses a different namespace
# than Terminal's built-in WslDistroGenerator.
# Source: WSL src/windows/common/wslutil.h (WslTerminalNamespace)
# Source: WSL src/windows/wslcore/LxssUserSession.cpp (_CreateTerminalProfile)
function Get-WslProfileGuid([string]$RegistryGuid) {
    $ns = [guid]"BE9372FE-59E1-4876-BDA9-C33C8F2F1AF1"
    # Normalize to lowercase with braces, matching WSL's GuidToString<wchar_t> format
    $normalizedGuid = "{$("$RegistryGuid".Trim('{}').ToLower())}"
    return New-UuidV5 $ns $normalizedGuid
}

# --- Helper: Compute Terminal Tier 1 hide GUID from distro name ---
# Terminal's WslDistroGenerator uses this namespace + distro name for auto-profiles.
# WSL's fragment uses this GUID in an "updates"+"hidden" entry to suppress Terminal's
# auto-generated Tier 1 profile (preventing duplicate entries in the tab dropdown).
# Source: Terminal src/cascadia/TerminalSettingsModel/WslDistroGenerator.cpp
function Get-TerminalHideGuid([string]$DistroName) {
    $ns = [guid]"2BDE4A90-D05F-401C-9492-E40884EAD1D8"
    return New-UuidV5 $ns $DistroName
}

# --- Helper: Get ALL Terminal LocalState directories (Stable, Preview, Unpackaged) ---
function Get-AllTerminalLocalStatePaths {
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState"
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal"
    )
    return @($candidates | Where-Object { Test-Path $_ })
}

# --- Helper: Get Terminal fragment directory ---
function Get-TerminalFragmentDir {
    return "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\Microsoft.WSL"
}

# --- Helper: Remove stale fragment files for a distro ---
function Remove-StaleTerminalFragments($DistroName, $OldLxssGuid, $ProfileGuid) {
    $fragmentDir = Get-TerminalFragmentDir
    if (-not (Test-Path $fragmentDir)) { return }

    $profileGuidStr = "$ProfileGuid".Trim('{}').ToLower()
    $removed = @()

    Get-ChildItem $fragmentDir -Filter "*.json" -ErrorAction SilentlyContinue | ForEach-Object {
        $remove = $false
        $fileName = $_.BaseName.Trim('{}').ToLower()

        # Match by our deterministic profile GUID (exact filename match)
        if ($fileName -eq $profileGuidStr) {
            $remove = $true
        }

        # Content scan: match distro name or old Lxss GUID
        if (-not $remove) {
            try {
                $content = Get-Content $_.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($content) {
                    if ($content -match [regex]::Escape($DistroName)) {
                        $remove = $true
                    }
                    if ($OldLxssGuid -and $content -match [regex]::Escape("$OldLxssGuid".Trim('{}'))) {
                        $remove = $true
                    }
                }
            }
            catch { }
        }

        if ($remove) {
            $removed += $_.Name
            Remove-Item $_.FullName -Force
        }
    }

    if ($removed.Count -gt 0) {
        Write-Ok "Removed $($removed.Count) stale fragment file(s): $($removed -join ', ')"
    }
}

# --- Helper: Create Terminal fragment file for a distro ---
# When $HideGuid is provided, creates a WSL-style fragment with both a new Tier 2
# profile (guid + source) and a hide entry for Terminal's Tier 1 auto-profile.
# When $HideGuid is $null, falls back to updates-only overlay on an existing profile.
function New-TerminalFragment($DistroName, $ProfileGuid, $HideGuid) {
    $fragmentDir = Get-TerminalFragmentDir

    # Create fragment directory if needed
    if (-not (Test-Path $fragmentDir)) {
        try {
            New-Item -ItemType Directory -Path $fragmentDir -Force | Out-Null
        }
        catch {
            Write-Warn "Could not create fragment directory: $fragmentDir"
            Write-Warn "  Error: $_"
            Write-Warn "  Terminal may not show the profile in the tab dropdown."
            return
        }
    }

    # Get distribution GUID from registry (used for icon path lookup)
    $distroGuid = Get-DistroGuid $DistroName

    # Read profile metadata from inside the distro
    $profileName = $DistroName
    $icon = $null
    $font = $null
    $colorScheme = $null

    try {
        $profileJson = wsl -d $DistroName --cd / -- cat /etc/wsl-terminal-profile.json 2>$null
        if ($profileJson) {
            $profile = $profileJson | ConvertFrom-Json
            if ($profile.name) { $profileName = $profile.name }
            if ($profile.font) { $font = $profile.font }
            if ($profile.colorScheme) { $colorScheme = $profile.colorScheme }
            Write-Status "Read profile metadata from /etc/wsl-terminal-profile.json"
        }
    }
    catch {
        Write-Warn "Could not read /etc/wsl-terminal-profile.json -- using defaults."
    }

    # Look for icon extracted by WSL
    $iconCandidates = @("$env:LOCALAPPDATA\wsl\$DistroName\shortcut.ico")
    if ($distroGuid) {
        $iconCandidates += "$env:LOCALAPPDATA\wsl\$($distroGuid.Trim('{}'))\shortcut.ico"
    }
    foreach ($ic in $iconCandidates) {
        if (Test-Path $ic) {
            $icon = $ic
            break
        }
    }

    # Build fragment profile entries.
    $profiles = @()

    if ($HideGuid) {
        # Full WSL-style fragment: create the Tier 2 profile and hide the Tier 1 auto-profile.
        # Matches the structure WSL's _CreateTerminalProfile writes in LxssUserSession.cpp.
        # Using "guid" + "source" is correct here because:
        #   - The Tier 2 GUID doesn't conflict with any Terminal generator GUID
        #   - Terminal's WslDistroGenerator skips Modern=1 distros (no Tier 1 profile to conflict)
        #   - Source "Microsoft.WSL" is not a Terminal-internal generator name
        $profileObj = [ordered]@{
            guid        = "{$("$ProfileGuid".Trim('{}'))}"
            name        = $profileName
            commandline = "wsl.exe -d $DistroName"
            source      = "Microsoft.WSL"
        }
        if ($icon) { $profileObj["icon"] = $icon }
        if ($font) { $profileObj["font"] = $font }
        if ($colorScheme) { $profileObj["colorScheme"] = $colorScheme }
        $profiles += $profileObj

        # Hide Terminal's auto-generated Tier 1 profile to prevent duplicate entries.
        # The hide GUID matches what WslDistroGenerator would compute from the distro name.
        $profiles += [ordered]@{
            updates = "{$("$HideGuid".Trim('{}'))}"
            hidden  = $true
        }
    }
    else {
        # Fallback: overlay on existing profile (when we couldn't compute from registry).
        # Uses "updates" to modify the dynamic profile rather than creating a new one.
        $profileObj = [ordered]@{
            updates = "{$("$ProfileGuid".Trim('{}'))}"
            name    = $profileName
        }
        if ($icon) { $profileObj["icon"] = $icon }
        if ($font) { $profileObj["font"] = $font }
        if ($colorScheme) { $profileObj["colorScheme"] = $colorScheme }
        $profiles += $profileObj
    }

    # Fragment JSON structure
    $fragment = [ordered]@{
        profiles = $profiles
    }

    $fragmentPath = Join-Path $fragmentDir "$DistroName.json"
    $fragment | ConvertTo-Json -Depth 10 | Set-Content $fragmentPath -Encoding UTF8

    Write-Ok "Created Terminal fragment: $fragmentPath"
    if ($HideGuid) {
        Write-Host "  Profile GUID (Tier 2): {$("$ProfileGuid".Trim('{}'))}"
        Write-Host "  Hidden GUID (Tier 1):  {$("$HideGuid".Trim('{}'))}"
    }
    else {
        Write-Host "  Updates profile GUID: {$("$ProfileGuid".Trim('{}'))}"
    }
    Write-Host "  Display name: $profileName"
    if ($icon) { Write-Host "  Icon: $icon" }
}

# --- Helper: Remove stale Terminal profiles, state entries, and fragments for a distro ---
function Remove-StaleTerminalArtifacts($distroName, $oldGuid, $profileGuid) {
    $localStatePaths = Get-AllTerminalLocalStatePaths
    if ($localStatePaths.Count -eq 0) {
        Write-Warn "No Windows Terminal installations found -- skipping artifact cleanup."
        return
    }

    Write-Status "Cleaning stale Windows Terminal artifacts..."

    $profileGuidStr = "$profileGuid".Trim('{}').ToLower()

    # Build set of currently-registered Lxss GUIDs for orphan detection.
    # WSL fragments use --distribution-id {registry-guid} in commandlines.
    # After wsl --unregister, orphaned profiles retain old GUIDs that are no longer
    # registered. Comparing against this set identifies those orphans.
    $currentLxssGuids = @()
    $lxssRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
    if (Test-Path $lxssRegPath) {
        Get-ChildItem $lxssRegPath | ForEach-Object {
            $currentLxssGuids += $_.PSChildName.Trim('{}').ToLower()
        }
    }

    foreach ($localState in $localStatePaths) {
        $settingsPath = Join-Path $localState "settings.json"
        if (-not (Test-Path $settingsPath)) { continue }

        Write-Host "  Settings: $settingsPath"

        # --- Clean settings.json ---
        $settingsRaw = Get-Content $settingsPath -Raw -Encoding UTF8

        # Remove single-line // comments (Terminal allows them but ConvertFrom-Json does not)
        $stripped = $settingsRaw -replace '(?m)^\s*//.*$', '' -replace '(?<=,)\s*//.*$', ''

        try {
            $settings = $stripped | ConvertFrom-Json
        }
        catch {
            Write-Warn "Could not parse settings.json at $settingsPath -- skipping."
            continue
        }

        $settingsModified = $false

        if ($settings.profiles -and $settings.profiles.list) {
            $removed = @()

            $settings.profiles.list = @($settings.profiles.list | Where-Object {
                if ($null -eq $_) { return $true }
                $dominated = $false
                $pGuid = $_.guid
                $pName = $_.name
                $pSource = $_.source
                $pCmd = $_.commandline

                # Match by old Lxss GUID
                if ($oldGuid -and $pGuid) {
                    $normalizedOld = "$oldGuid".Trim('{}').ToLower()
                    $normalizedCur = "$pGuid".Trim('{}').ToLower()
                    if ($normalizedOld -eq $normalizedCur) { $dominated = $true }
                }

                # Match by our deterministic profile GUID
                if (-not $dominated -and $pGuid) {
                    $normalizedCur = "$pGuid".Trim('{}').ToLower()
                    if ($normalizedCur -eq $profileGuidStr) { $dominated = $true }
                }

                # Match by name for WSL-sourced profiles (both old and new source values)
                if (-not $dominated -and $pName -and $pName -eq $distroName) {
                    if ($pSource -eq "Windows.Terminal.Wsl" -or $pSource -eq "Microsoft.WSL") {
                        $dominated = $true
                    }
                }

                # Match entries that reference the distro by commandline (-d distroname format)
                if (-not $dominated -and $pCmd -and $pCmd -match "wsl.*-d\s+$([regex]::Escape($distroName))") {
                    $dominated = $true
                }

                # Match WSL-created profiles by --distribution-id with stale registry GUID.
                # WSL fragments use: wsl.exe --distribution-id {registry-guid}
                # After unregister, old registry GUIDs are no longer in Lxss. Any profile
                # whose --distribution-id references a non-existent GUID is orphaned.
                if (-not $dominated -and $pCmd -and $pCmd -match 'distribution-id\s+\{?([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\}?') {
                    $cmdGuid = $Matches[1].ToLower()
                    if ($cmdGuid -notin $currentLxssGuids) {
                        $dominated = $true
                    }
                }

                if ($dominated) {
                    $removed += if ($pName) { $pName } else { "(unnamed)" }
                }
                -not $dominated
            })

            if ($removed.Count -gt 0) {
                $settingsModified = $true
                Write-Ok "  Removing $($removed.Count) stale profile(s): $($removed -join ', ')"
            }
        }

        if ($settingsModified) {
            $backupPath = "$settingsPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item $settingsPath $backupPath
            Write-Status "  Backed up settings to: $backupPath"
            $settings | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
        }

        # NOTE: state.json orphan sweep is intentionally NOT done here. It runs
        # AFTER import+fragment creation (Clean-StateJsonOrphans) because wsl --import
        # re-adds GUIDs to state.json during its (failed) terminal profile creation,
        # undoing any pre-import cleanup.
    }

    # --- Clean fragment files ---
    Remove-StaleTerminalFragments $distroName $oldGuid $profileGuid
}

# --- Helper: Final orphan sweep of state.json generatedProfiles ---
# Runs AFTER import and fragment creation, when all Terminal artifacts are final.
# Removes any generatedProfile GUID not backed by a registered distro's Tier 2,
# a settings.json profile, or a fragment file. This must run post-import because
# wsl --import re-adds GUIDs to state.json during its terminal profile creation
# attempt (which fails with E_UNEXPECTED but still modifies state.json).
function Clean-StateJsonOrphans {
    $localStatePaths = Get-AllTerminalLocalStatePaths
    if ($localStatePaths.Count -eq 0) { return }

    # Build set of currently-registered Lxss GUIDs
    $currentLxssGuids = @()
    $lxssRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
    if (Test-Path $lxssRegPath) {
        Get-ChildItem $lxssRegPath | ForEach-Object {
            $currentLxssGuids += $_.PSChildName.Trim('{}').ToLower()
        }
    }

    foreach ($localState in $localStatePaths) {
        $statePath = Join-Path $localState "state.json"
        if (-not (Test-Path $statePath)) { continue }

        try {
            $stateRaw = Get-Content $statePath -Raw -Encoding UTF8
            $state = $stateRaw | ConvertFrom-Json

            if (-not $state.generatedProfiles -or $state.generatedProfiles.Count -eq 0) { continue }

            # Build "accounted for" set from all active sources
            $accountedFor = @()

            # Tier 2 GUIDs of all currently-registered WSL distros
            foreach ($lxssGuid in $currentLxssGuids) {
                $accountedFor += "$(Get-WslProfileGuid "{$lxssGuid}")".Trim('{}').ToLower()
            }

            # GUIDs that have profiles in settings.json
            $settingsPath = Join-Path $localState "settings.json"
            if (Test-Path $settingsPath) {
                $settingsRaw = Get-Content $settingsPath -Raw -Encoding UTF8
                $stripped = $settingsRaw -replace '(?m)^\s*//.*$', '' -replace '(?<=,)\s*//.*$', ''
                try {
                    $sj = $stripped | ConvertFrom-Json
                    if ($sj.profiles -and $sj.profiles.list) {
                        foreach ($p in $sj.profiles.list) {
                            if ($p.guid) { $accountedFor += "$($p.guid)".Trim('{}').ToLower() }
                        }
                    }
                } catch {}
            }

            # GUIDs from ALL fragment files
            $allFragDir = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments"
            if (Test-Path $allFragDir) {
                Get-ChildItem $allFragDir -Recurse -Filter "*.json" -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $fc = Get-Content $_.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                        if ($fc) {
                            $fj = $fc | ConvertFrom-Json
                            if ($fj.profiles) {
                                foreach ($fp in $fj.profiles) {
                                    if ($fp.guid) { $accountedFor += "$($fp.guid)".Trim('{}').ToLower() }
                                }
                            }
                        }
                    } catch {}
                }
            }

            $accountedFor = @($accountedFor | Where-Object { $_ } | Select-Object -Unique)

            # Keep only GUIDs that are accounted for; everything else is orphaned
            $originalCount = $state.generatedProfiles.Count
            $state.generatedProfiles = @($state.generatedProfiles | Where-Object {
                "$_".Trim('{}').ToLower() -in $accountedFor
            })
            $removedCount = $originalCount - $state.generatedProfiles.Count

            if ($removedCount -gt 0) {
                $stateBackup = "$statePath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Copy-Item $statePath $stateBackup
                $state | ConvertTo-Json -Depth 20 | Set-Content $statePath -Encoding UTF8
                Write-Ok "Cleaned $removedCount orphan(s) from state.json generatedProfiles"
            }
        }
        catch {
            Write-Warn "Could not clean state.json at $localState : $_"
        }
    }
}

# --- Step 1: Find the tarball ---
if (-not $TarballPath) {
    Write-Status "No tarball path specified, searching..."

    # Search common locations: all running WSL distros' nixcfg paths
    $searchPaths = @()
    $runningDistros = wsl --list --quiet 2>$null | Where-Object { $_ -and $_ -notmatch '^\s*$' }
    foreach ($distro in $runningDistros) {
        $distro = $distro.Trim()
        if (-not $distro) { continue }
        # Common worktree/repo locations
        $searchPaths += "\\wsl$\$distro\home\*\src\nixcfg\nixos.wsl"
        $searchPaths += "\\wsl$\$distro\home\*\src\nixcfg-dendritic\nixos.wsl"
    }
    # Also check Windows-side common locations
    $searchPaths += "$env:USERPROFILE\Downloads\nixos.wsl"
    $searchPaths += "$env:USERPROFILE\Desktop\nixos.wsl"

    $found = @()
    foreach ($pattern in $searchPaths) {
        $matches = Resolve-Path -Path $pattern -ErrorAction SilentlyContinue
        if ($matches) { $found += $matches }
    }

    if ($found.Count -eq 0) {
        Write-Err "No nixos.wsl tarball found. Searched:"
        foreach ($p in $searchPaths) { Write-Host "  $p" }
        Write-Host ""
        Write-Host "Specify the tarball path explicitly, e.g.:"
        Write-Host "  .\Import-NixOSWSL.ps1 -TarballPath \\wsl`$\NixOS\home\USER\src\nixcfg\nixos.wsl"
        Write-Host ""
        Write-Host "Find your distro name with: wsl --list --quiet"
        exit 1
    }
    elseif ($found.Count -eq 1) {
        $TarballPath = $found[0].Path
        Write-Ok "Found tarball: $TarballPath"
    }
    else {
        Write-Status "Multiple tarballs found:"
        for ($i = 0; $i -lt $found.Count; $i++) {
            Write-Host "  [$i] $($found[$i].Path)"
        }
        $choice = Read-Host "Select tarball (0-$($found.Count - 1))"
        $TarballPath = $found[[int]$choice].Path
    }
}

if (-not (Test-Path $TarballPath)) {
    Write-Err "Tarball not found: $TarballPath"
    exit 1
}

$tarballSize = [math]::Round((Get-Item $TarballPath).Length / 1GB, 2)
Write-Status ("Tarball: " + $TarballPath + " (" + $tarballSize + " GB)")

# --- Step 2: Check if distro already exists ---
$existing = wsl --list --quiet 2>$null | Where-Object { $_ -and $_.Trim() -eq $DistroName }
if ($existing) {
    Write-Warn "Distribution '$DistroName' already exists."
    $action = Read-Host "Choose: [R]eplace (unregister + reimport), [A]bort"
    if ($action -match '^[Rr]') {
        # Capture the old GUID before unregistering (needed for Terminal cleanup)
        $oldGuid = Get-DistroGuid $DistroName
        if ($oldGuid) {
            Write-Status "Old distro GUID: $oldGuid"
        }

        # Dynamic lookup for cleanup: capture the GUID Terminal is currently using.
        # This is the OLD Tier 2 GUID — only used for cleanup, NOT for fragment creation.
        # After reimport, a new registry GUID produces a different Tier 2 GUID.
        $oldProfileGuid = Find-ExistingTerminalProfileGuid $DistroName
        if ($oldProfileGuid) {
            Write-Status "Found existing Terminal profile GUID (for cleanup): {$("$oldProfileGuid".Trim('{}'))}"
        }
        else {
            Write-Warn "No existing Terminal profile GUID found — cleanup may miss stale entries."
        }

        Write-Status "Unregistering existing '$DistroName'..."
        wsl --unregister $DistroName
        Write-Ok "Unregistered."

        # Clean up stale Terminal artifacts left behind by the old registration
        Remove-StaleTerminalArtifacts $DistroName $oldGuid $oldProfileGuid
    }
    else {
        Write-Host "Aborted."
        exit 0
    }
}

# --- Step 3: Find WSL storage parent directory ---
Write-Status "Detecting WSL storage location..."

$wslParent = $null

# Method 1: Check registry for existing distro locations
$lxssPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
if (Test-Path $lxssPath) {
    $distros = Get-ChildItem $lxssPath | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath
        [PSCustomObject]@{
            Name     = $props.DistributionName
            BasePath = $props.BasePath
        }
    } | Where-Object { $_.BasePath -and (Test-Path $_.BasePath) }

    if ($distros) {
        # Group by parent directory, pick the most common one
        $parents = $distros | ForEach-Object { Split-Path $_.BasePath -Parent } |
            Group-Object | Sort-Object Count -Descending

        $wslParent = $parents[0].Name
        Write-Status "Found existing distros in: $wslParent"
        Write-Host ""
        foreach ($d in $distros) {
            $size = ""
            $vhdx = Join-Path $d.BasePath "ext4.vhdx"
            if (Test-Path $vhdx) {
                $sizeGB = [math]::Round((Get-Item $vhdx).Length / 1GB, 1)
                $size = ' (' + $sizeGB + ' GB)'
            }
            Write-Host "  $($d.Name): $($d.BasePath)$size"
        }
        Write-Host ""
    }
}

# Method 2: Fallback to standard location
if (-not $wslParent) {
    $wslParent = "$env:LOCALAPPDATA\WSL"
    Write-Warn "No existing distros found in registry. Using default: $wslParent"
}

$targetDir = Join-Path $wslParent $DistroName

Write-Status "Import target: $targetDir"

if (Test-Path $targetDir) {
    Write-Warn "Target directory already exists: $targetDir"
    $confirm = Read-Host "Continue anyway? [Y/n]"
    if ($confirm -match '^[Nn]') { exit 0 }
}

# --- Step 4: Import ---
Write-Status "Importing '$DistroName'..."
Write-Host "  Source:  $TarballPath"
Write-Host "  Target:  $targetDir"
Write-Host ""

wsl --import $DistroName $targetDir $TarballPath

if ($LASTEXITCODE -ne 0) {
    Write-Err "Import failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Ok "Import complete!"

# --- Step 5: Verify ---
Write-Status "Verifying..."
$output = wsl -d $DistroName --cd / -- sh -c 'echo "user=$(whoami) host=$(hostname)"' 2>&1
Write-Ok "Instance responding: $output"

# --- Step 6: Create Terminal fragment ---
# Always compute the correct Tier 2 GUID from the fresh registry GUID assigned
# during import. This matches what WSL's _CreateTerminalProfile would generate.
# The old $oldProfileGuid (if any) was only used for cleanup in Step 2.
$profileGuid = $null
$hideGuid = $null
$registryGuid = Get-DistroGuid $DistroName

if ($registryGuid) {
    $profileGuid = Get-WslProfileGuid $registryGuid
    $hideGuid = Get-TerminalHideGuid $DistroName
    Write-Status "Registry GUID: $registryGuid"
    Write-Status "Computed Tier 2 profile GUID: {$("$profileGuid".Trim('{}'))}"
    Write-Status "Computed Tier 1 hide GUID: {$("$hideGuid".Trim('{}'))}"

    # Remove any WSL-created fragment from import (we'll replace with our customized version)
    Remove-StaleTerminalFragments $DistroName $registryGuid $profileGuid

    Write-Status "Creating Windows Terminal fragment..."
    New-TerminalFragment $DistroName $profileGuid $hideGuid
}
else {
    Write-Warn "Could not read registry GUID after import."
    # Last resort: dynamic lookup (WSL might have created a fragment despite the bug)
    $profileGuid = Find-ExistingTerminalProfileGuid $DistroName
    if ($profileGuid) {
        Write-Status "Found profile GUID from WSL fragment: {$("$profileGuid".Trim('{}'))}"
        Write-Status "Creating Windows Terminal fragment (updates-only fallback)..."
        New-TerminalFragment $DistroName $profileGuid $null
    }
    else {
        Write-Warn "No profile GUID available — Terminal profile must be configured manually."
    }
}

# --- Step 6b: Clean state.json orphans ---
# Must run AFTER import + fragment creation. The wsl --import command modifies
# state.json during its terminal profile creation attempt, so any pre-import
# cleanup of state.json gets undone. This final sweep catches those re-additions.
Clean-StateJsonOrphans

# --- Step 7: Optional default ---
if ($SetDefault) {
    wsl --set-default $DistroName
    Write-Ok "Set '$DistroName' as default WSL distribution."
}

# --- Step 8: Verify registration ---
$newGuid = Get-DistroGuid $DistroName
if ($newGuid) {
    Write-Ok "New distro registered with GUID: $newGuid"
}

# --- Summary ---
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Import Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Distro:       $DistroName"
Write-Host "  Storage:      $targetDir"
if ($profileGuid) {
    Write-Host "  Profile GUID: {$("$profileGuid".Trim('{}'))}"
}
if ($hideGuid) {
    Write-Host "  Hide GUID:    {$("$hideGuid".Trim('{}'))}"
}
Write-Host "  Launch:       wsl -d $DistroName"
Write-Host ""
Write-Host "  IMPORTANT: Close and reopen Windows Terminal (including system tray)"
Write-Host "  to see the new '$DistroName' profile in the tab dropdown."
Write-Host ""
Write-Host "  Next steps:"
Write-Host "    1. Restart Windows Terminal"
Write-Host "    2. Open a tab for '$DistroName'"
Write-Host "    3. setup-username          # personalize your username"
Write-Host "    4. sudo nixos-rebuild switch  # apply after username change"
Write-Host ""
