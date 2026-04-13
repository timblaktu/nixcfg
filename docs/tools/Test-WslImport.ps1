<#
.SYNOPSIS
    Integration test harness for NixOS-WSL tarball import pipeline.

.DESCRIPTION
    Automates the full Build -> Import -> Validate -> Cleanup pipeline for
    NixOS-WSL tarballs. Tests Import-NixOSWSL.ps1 end-to-end by:
    - Cloning the nixcfg repo into a temp dir inside a Nix-enabled WSL distro
    - Building a tarball via Nix (or using a pre-built one)
    - Importing it under a test-prefixed distro name for isolation
    - Validating the imported distro (user, hostname, services, Nix store)
    - Verifying Windows Terminal fragment GUID computation
    - Cleaning up all test artifacts (temp clone, test distro, fragments)

    This script is distributed as a GitHub release artifact and must work on
    any Windows machine with WSL -- it does not assume any local repo checkout.

    Test distros use "test-" prefix (e.g., test-nixos-wsl-dev-team) to never
    interfere with real WSL distributions.

    GUID verification functions are duplicated (~60 lines) from Import-NixOSWSL.ps1
    for independent validation. Import-NixOSWSL.ps1 runs top-level code on
    dot-source, so we cannot share functions directly. This is a known trade-off;
    a future refactor could extract shared functions into a module.

.PARAMETER ConfigName
    NixOS configuration name to test. Default: nixos-wsl-dev-team

.PARAMETER All
    Test ALL WSL-capable configurations (matrix mode). Discovers configs via
    nix eval and runs each sequentially.

.PARAMETER TarballPath
    Path to a pre-built .wsl tarball. Skips the build phase when provided.

.PARAMETER BuildDistro
    WSL distro with Nix and git installed, used for building and discovery.
    Auto-detected if omitted (first running distro that has nix on PATH).

.PARAMETER RepoUrl
    Git URL of the nixcfg repository to clone for building.
    Default: https://github.com/timblaktu/nixcfg.git

.PARAMETER Branch
    Branch or tag to checkout after cloning. Default: main

.PARAMETER SkipBuild
    Skip the build phase entirely. Requires -TarballPath.

.PARAMETER SkipCleanup
    Leave the test distro registered for manual inspection after tests complete.

.PARAMETER SkipTerminalValidation
    Skip Windows Terminal fragment and GUID verification checks.

.PARAMETER BuildTimeoutMinutes
    Timeout for nix build + tarball-builder combined. Default: 30

.PARAMETER BootTimeoutSeconds
    Timeout waiting for imported distro to respond. Default: 120

.PARAMETER Verbose
    Enable extra diagnostic output.

.EXAMPLE
    .\Test-WslImport.ps1
    # Test default config (nixos-wsl-dev-team), full pipeline

.EXAMPLE
    .\Test-WslImport.ps1 -TarballPath .\nixcfg-wsl-dev-team-0.1.0.wsl -SkipBuild
    # Test with a pre-built tarball (e.g., from a release download)

.EXAMPLE
    .\Test-WslImport.ps1 -ConfigName nixos-wsl-minimal
    # Test the minimal WSL config

.EXAMPLE
    .\Test-WslImport.ps1 -All
    # Test all WSL-capable configurations sequentially

.EXAMPLE
    .\Test-WslImport.ps1 -SkipCleanup
    # Leave test distro for manual inspection

.EXAMPLE
    .\Test-WslImport.ps1 -Branch feat/my-feature -BuildDistro nixos
    # Build from a specific branch using a specific WSL distro

.NOTES
    Prerequisites:
    - Windows 10/11 with WSL installed and responding
    - For build phase: a WSL distro with Nix and git installed
    - For build phase: passwordless sudo in the build distro (tarball builder needs it)
    - For terminal validation: Windows Terminal installed

    The script clones the repo into a temp directory (mktemp -d) inside the
    build distro, so no pre-existing checkout is needed.

    Exit codes:
    0 = All checks passed
    1 = One or more checks failed
    2 = Fatal error (WSL missing, build failed, import failed)
#>

param(
    [string]$ConfigName = "nixos-wsl-dev-team",
    [switch]$All,
    [string]$TarballPath,
    [string]$BuildDistro,
    [string]$RepoUrl = "https://github.com/timblaktu/nixcfg.git",
    [string]$Branch = "main",
    [switch]$SkipBuild,
    [switch]$SkipCleanup,
    [switch]$SkipTerminalValidation,
    [int]$BuildTimeoutMinutes = 30,
    [int]$BootTimeoutSeconds = 120,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# ENCODING NOTE: This file requires a UTF-8 BOM (EF BB BF) for PS 5.1 compat.
# Without BOM, PS 5.1 reads as Windows-1252. The BOM is enforced by the
# lint-ps1-encoding flake check.

# ============================================================================
# Output helpers
# ============================================================================

function Write-Status($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)     { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn($msg)   { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err($msg)    { Write-Host "[-] $msg" -ForegroundColor Red }

# ============================================================================
# WSL output encoding helper
# ============================================================================

# wsl.exe outputs UTF-16LE text. PowerShell 5.1 often mishandles this, leaving
# invisible NUL bytes in strings. This function strips them so distro names
# can be used reliably as -d arguments.
function Get-WslDistroNames {
    $raw = wsl --list --quiet 2>$null
    if (-not $raw) { return @() }
    # Force to string array, strip NUL bytes and whitespace, filter empties
    $names = @($raw | ForEach-Object {
        if ($_) { ($_ -replace "`0", "").Trim() }
    } | Where-Object { $_ -and $_ -notmatch '^\s*$' })
    return $names
}

# ============================================================================
# Test infrastructure
# ============================================================================

# Global results accumulator: array of [ordered]@{ Phase; Name; Status; Detail; Duration }
$script:Results = @()
$script:TestStartTime = Get-Date
# Track temp clone dir for cleanup
$script:CloneTempDir = $null

function Test-Check {
    param(
        [string]$Phase,
        [string]$Name,
        [scriptblock]$Check
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $status = "FAIL"
    $detail = ""

    try {
        $output = & $Check
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            $status = "FAIL"
            $detail = "exit code $LASTEXITCODE"
        } else {
            $status = "PASS"
            $detail = if ($output) { "$output".Trim() } else { "" }
        }
    }
    catch {
        $status = "FAIL"
        $detail = "$_"
    }

    $sw.Stop()
    $elapsed = $sw.Elapsed

    $result = [ordered]@{
        Phase    = $Phase
        Name     = $Name
        Status   = $status
        Detail   = $detail
        Duration = $elapsed
    }
    $script:Results += $result

    $durationStr = if ($elapsed.TotalSeconds -ge 60) {
        "{0:N0}m {1:N0}s" -f $elapsed.TotalMinutes, ($elapsed.Seconds)
    } elseif ($elapsed.TotalSeconds -ge 1) {
        "{0:N1}s" -f $elapsed.TotalSeconds
    } else {
        ""
    }

    $color = if ($status -eq "PASS") { "Green" } elseif ($status -eq "SKIP") { "Yellow" } else { "Red" }
    $detailSuffix = if ($detail -and $detail.Length -le 80) { "  ($detail)" } elseif ($detail) { "  ($($detail.Substring(0,77))...)" } else { "" }
    $timeSuffix = if ($durationStr) { "  ($durationStr)" } else { "" }

    $line = "[{0,-8}] {1,-28} {2}{3}{4}" -f $Phase, $Name, $status, $detailSuffix, $timeSuffix
    Write-Host $line -ForegroundColor $color

    return $status
}

function Skip-Check {
    param(
        [string]$Phase,
        [string]$Name,
        [string]$Reason
    )

    $result = [ordered]@{
        Phase    = $Phase
        Name     = $Name
        Status   = "SKIP"
        Detail   = $Reason
        Duration = [TimeSpan]::Zero
    }
    $script:Results += $result

    $line = "[{0,-8}] {1,-28} SKIP  ({2})" -f $Phase, $Name, $Reason
    Write-Host $line -ForegroundColor Yellow
}

function Invoke-WslCommand {
    param(
        [string]$Distro,
        [string]$Command,
        [int]$TimeoutSec = 30
    )

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "wsl.exe"
    $pinfo.Arguments = "-d $Distro -- bash -lc `"$($Command -replace '"', '\"')`""
    $pinfo.UseShellExecute = $false
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($pinfo)

    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        try { $proc.Kill() } catch {}
        throw "Command timed out after ${TimeoutSec}s: $Command"
    }

    $stdout = $proc.StandardOutput.ReadToEnd().Trim()
    $stderr = $proc.StandardError.ReadToEnd().Trim()
    $exitCode = $proc.ExitCode

    if ($Verbose) {
        if ($stderr) { Write-Host "  stderr: $stderr" -ForegroundColor DarkGray }
    }

    return [PSCustomObject]@{
        Output   = $stdout
        Error    = $stderr
        ExitCode = $exitCode
    }
}

function Get-NixEval {
    param(
        [string]$Distro,
        [string]$RepoPath,
        [string]$AttrPath
    )

    $cmd = "cd $RepoPath && nix eval '$AttrPath' --raw 2>/dev/null"
    $result = Invoke-WslCommand -Distro $Distro -Command $cmd -TimeoutSec 60
    if ($result.ExitCode -ne 0) {
        throw "nix eval failed for $AttrPath (exit $($result.ExitCode)): $($result.Error)"
    }
    return $result.Output
}

function Write-TestSummary {
    $total = $script:Results.Count
    $passed = @($script:Results | Where-Object { $_.Status -eq "PASS" }).Count
    $failed = @($script:Results | Where-Object { $_.Status -eq "FAIL" }).Count
    $skipped = @($script:Results | Where-Object { $_.Status -eq "SKIP" }).Count

    $elapsed = (Get-Date) - $script:TestStartTime
    $elapsedStr = "{0:N0}m {1:N0}s" -f [math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds

    Write-Host ""
    if ($failed -eq 0) {
        Write-Host ("=== RESULT: {0}/{1} passed" -f $passed, ($total - $skipped)) -NoNewline -ForegroundColor Green
        if ($skipped -gt 0) { Write-Host " ($skipped skipped)" -NoNewline -ForegroundColor Yellow }
        Write-Host " ($elapsedStr) ===" -ForegroundColor Green
    } else {
        Write-Host ("=== RESULT: {0} FAILED, {1} passed" -f $failed, $passed) -NoNewline -ForegroundColor Red
        if ($skipped -gt 0) { Write-Host " ($skipped skipped)" -NoNewline -ForegroundColor Yellow }
        Write-Host " ($elapsedStr) ===" -ForegroundColor Red

        Write-Host ""
        Write-Host "Failed checks:" -ForegroundColor Red
        foreach ($r in ($script:Results | Where-Object { $_.Status -eq "FAIL" })) {
            Write-Host "  - [$($r.Phase)] $($r.Name): $($r.Detail)" -ForegroundColor Red
        }
    }
}

# ============================================================================
# GUID functions -- duplicated from Import-NixOSWSL.ps1 for independent
# verification. See that script for detailed comments on the two-tier system.
# ============================================================================

function New-UuidV5([guid]$Namespace, [string]$Name, [System.Text.Encoding]$Encoding) {
    if (-not $Encoding) { $Encoding = [System.Text.Encoding]::Unicode }

    $nsBytes = $Namespace.ToByteArray()
    [Array]::Reverse($nsBytes, 0, 4)
    [Array]::Reverse($nsBytes, 4, 2)
    [Array]::Reverse($nsBytes, 6, 2)

    $nameBytes = $Encoding.GetBytes($Name)
    $data = $nsBytes + $nameBytes

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    $hash = $sha1.ComputeHash($data)
    $sha1.Dispose()

    $hash[6] = ($hash[6] -band 0x0F) -bor 0x50
    $hash[8] = ($hash[8] -band 0x3F) -bor 0x80

    [byte[]]$guidBytes = $hash[0..15]
    [Array]::Reverse($guidBytes, 0, 4)
    [Array]::Reverse($guidBytes, 4, 2)
    [Array]::Reverse($guidBytes, 6, 2)

    return [guid]::new($guidBytes)
}

function Get-DistroGuid($Name) {
    $lxssPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
    if (-not (Test-Path $lxssPath)) { return $null }

    $result = $null
    Get-ChildItem $lxssPath | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath
        if ($props.DistributionName -eq $Name) {
            $result = $_.PSChildName
        }
    }
    return $result
}

function Get-WslProfileGuid([string]$RegistryGuid) {
    $ns = [guid]"BE9372FE-59E1-4876-BDA9-C33C8F2F1AF1"
    $normalizedGuid = "{$("$RegistryGuid".Trim('{}').ToLower())}"
    return New-UuidV5 $ns $normalizedGuid
}

function Get-TerminalHideGuid([string]$DistroName) {
    $ns = [guid]"2BDE4A90-D05F-401C-9492-E40884EAD1D8"
    return New-UuidV5 $ns $DistroName
}

function Get-TerminalFragmentDir {
    return "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\Microsoft.WSL"
}

# ============================================================================
# Run a single config test (used by both single and matrix modes)
# ============================================================================

function Test-SingleConfig {
    param(
        [string]$Config,
        [string]$Tarball,
        [string]$BuildDistroName,
        [string]$CloneDir,
        [bool]$DoBuild,
        [bool]$DoTerminal,
        [bool]$DoCleanup,
        [int]$BuildTimeout,
        [int]$BootTimeout
    )

    $testDistro = "test-$Config"
    $expectations = @{}

    Write-Host ""
    Write-Host ("=== Test-WslImport: {0} ===" -f $Config) -ForegroundColor Cyan
    Write-Host "Test distro: $testDistro"
    Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host ""

    # ========================================================================
    # Phase 1 -- Discovery (extract expectations from Nix config)
    # ========================================================================

    if ($BuildDistroName -and $CloneDir) {
        try {
            $expectations.User = Get-NixEval -Distro $BuildDistroName -RepoPath $CloneDir `
                -AttrPath ".#nixosConfigurations.$Config.config.wsl.defaultUser"
            $expectations.Hostname = Get-NixEval -Distro $BuildDistroName -RepoPath $CloneDir `
                -AttrPath ".#nixosConfigurations.$Config.config.networking.hostName"

            Write-Status "Expectations: user=$($expectations.User), hostname=$($expectations.Hostname)"
        }
        catch {
            Write-Warn "Could not extract expectations via nix eval: $_"
            Write-Warn "Validation checks will compare against actual values only."
        }
    }

    # ========================================================================
    # Phase 2 -- Build
    # ========================================================================

    if ($DoBuild -and -not $Tarball) {
        $buildLinkName = "result-test-$Config"
        $tarballFileName = "test-$Config.wsl"

        # Build the tarball builder derivation
        $buildStatus = Test-Check "BUILD" "tarball-builder" {
            $cmd = "cd $CloneDir && nix build '.#nixosConfigurations.$Config.config.system.build.tarballBuilder' -o $buildLinkName --print-build-logs"
            $r = Invoke-WslCommand -Distro $BuildDistroName -Command $cmd -TimeoutSec ($BuildTimeout * 60)
            if ($r.ExitCode -ne 0) { throw "nix build failed: $($r.Error)" }
            return "derivation built"
        }

        if ($buildStatus -ne "PASS") {
            Write-Err "Build failed -- cannot continue with import."
            return 2
        }

        # Run the tarball builder (requires sudo)
        $buildStatus = Test-Check "BUILD" "tarball-built" {
            $cmd = "cd $CloneDir && sudo ./$buildLinkName/bin/nixos-wsl-tarball-builder $tarballFileName"
            $r = Invoke-WslCommand -Distro $BuildDistroName -Command $cmd -TimeoutSec ($BuildTimeout * 60)
            if ($r.ExitCode -ne 0) { throw "tarball builder failed: $($r.Error)" }
            return "tarball created"
        }

        if ($buildStatus -ne "PASS") {
            Write-Err "Tarball build failed -- cannot continue with import."
            return 2
        }

        # Resolve UNC path to the tarball inside the temp clone dir
        $uncCloneDir = $CloneDir -replace '/', '\'
        $Tarball = "\\wsl.localhost\$BuildDistroName$uncCloneDir\$tarballFileName"

        Test-Check "BUILD" "tarball-exists" {
            if (-not (Test-Path $Tarball)) { throw "Tarball not found at: $Tarball" }
            $size = [math]::Round((Get-Item $Tarball).Length / 1GB, 2)
            return "${size} GB"
        } | Out-Null
    }
    elseif ($Tarball) {
        Test-Check "BUILD" "tarball-exists" {
            if (-not (Test-Path $Tarball)) { throw "Tarball not found at: $Tarball" }
            $size = [math]::Round((Get-Item $Tarball).Length / 1GB, 2)
            return "${size} GB"
        } | Out-Null
    }

    if (-not $Tarball -or -not (Test-Path $Tarball)) {
        Write-Err "No tarball available -- cannot proceed with import."
        return 2
    }

    # ========================================================================
    # Phase 3 -- Import (call Import-NixOSWSL.ps1)
    # ========================================================================

    # Pre-clean: remove leftover test distro if it exists
    $existingNames = Get-WslDistroNames
    if ($testDistro -in $existingNames) {
        Write-Status "Pre-cleaning leftover test distro: $testDistro"
        wsl --unregister $testDistro 2>$null | Out-Null
    }

    $importScript = Join-Path $PSScriptRoot "Import-NixOSWSL.ps1"

    $importStatus = Test-Check "IMPORT" "import-success" {
        if (-not (Test-Path $importScript)) {
            throw "Import script not found: $importScript"
        }
        # Run import script. It should not prompt because we pre-cleaned the distro.
        & $importScript -TarballPath $Tarball -DistroName $testDistro
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            throw "Import-NixOSWSL.ps1 exited with code $LASTEXITCODE"
        }
        return "imported"
    }

    if ($importStatus -ne "PASS") {
        Write-Err "Import failed -- cannot continue with validation."
        return 2
    }

    Test-Check "IMPORT" "distro-registered" {
        $names = Get-WslDistroNames
        if ($testDistro -notin $names) { throw "$testDistro not found in wsl --list" }
        return "registered"
    } | Out-Null

    # ========================================================================
    # Phase 4 -- Validate
    # ========================================================================

    # Core checks (all configs)
    Test-Check "VALIDATE" "distro-responds" {
        $r = Invoke-WslCommand -Distro $testDistro -Command "echo ok" -TimeoutSec $BootTimeout
        if ($r.ExitCode -ne 0) { throw "distro not responding: $($r.Error)" }
        if ($r.Output -ne "ok") { throw "unexpected output: $($r.Output)" }
        return "ok"
    } | Out-Null

    Test-Check "VALIDATE" "user-matches" {
        $r = Invoke-WslCommand -Distro $testDistro -Command "whoami" -TimeoutSec 30
        if ($r.ExitCode -ne 0) { throw "whoami failed: $($r.Error)" }
        $actual = $r.Output
        if ($expectations.User -and $actual -ne $expectations.User) {
            throw "expected: $($expectations.User), got: $actual"
        }
        return "expected: $actual, got: $actual"
    } | Out-Null

    Test-Check "VALIDATE" "hostname-matches" {
        $r = Invoke-WslCommand -Distro $testDistro -Command "hostname" -TimeoutSec 30
        if ($r.ExitCode -ne 0) { throw "hostname failed: $($r.Error)" }
        $actual = $r.Output
        if ($expectations.Hostname -and $actual -ne $expectations.Hostname) {
            throw "expected: $($expectations.Hostname), got: $actual"
        }
        return "expected: $($expectations.Hostname)"
    } | Out-Null

    Test-Check "VALIDATE" "nix-available" {
        $r = Invoke-WslCommand -Distro $testDistro -Command "nix --version" -TimeoutSec 30
        if ($r.ExitCode -ne 0) { throw "nix not found: $($r.Error)" }
        return $r.Output
    } | Out-Null

    Test-Check "VALIDATE" "nixos-version" {
        $r = Invoke-WslCommand -Distro $testDistro -Command "nixos-version" -TimeoutSec 30
        if ($r.ExitCode -ne 0) { throw "nixos-version failed: $($r.Error)" }
        if (-not $r.Output) { throw "empty nixos-version" }
        return $r.Output
    } | Out-Null

    Test-Check "VALIDATE" "systemd-state" {
        $r = Invoke-WslCommand -Distro $testDistro -Command "systemctl is-system-running --wait" -TimeoutSec 60
        $state = $r.Output
        # "running" = fully converged, "degraded" = booted but some units failed (acceptable for WSL)
        if ($state -ne "running" -and $state -ne "degraded") {
            throw "unexpected systemd state: $state"
        }
        return $state
    } | Out-Null

    Test-Check "VALIDATE" "wsl-conf-user" {
        $r = Invoke-WslCommand -Distro $testDistro -Command "grep '^default=' /etc/wsl.conf 2>/dev/null || echo ''" -TimeoutSec 15
        if (-not $r.Output) { throw "/etc/wsl.conf missing default= line" }
        if ($expectations.User -and $r.Output -notmatch $expectations.User) {
            throw "wsl.conf default user mismatch: $($r.Output)"
        }
        return $r.Output
    } | Out-Null

    Test-Check "VALIDATE" "nix-store-valid" {
        $r = Invoke-WslCommand -Distro $testDistro -Command "nix-store --verify --check-contents 2>&1 | head -5" -TimeoutSec 60
        if ($r.Output -match "error" -or $r.Output -match "corrupt") {
            throw "nix store issues: $($r.Output)"
        }
        return "valid"
    } | Out-Null

    # Conditional checks -- probe what the distro has
    $checkGit = Invoke-WslCommand -Distro $testDistro -Command "command -v git 2>/dev/null" -TimeoutSec 10
    if ($checkGit.ExitCode -eq 0) {
        Test-Check "VALIDATE" "git-available" {
            $r = Invoke-WslCommand -Distro $testDistro -Command "git --version" -TimeoutSec 15
            if ($r.ExitCode -ne 0) { throw "git failed: $($r.Error)" }
            return $r.Output
        } | Out-Null
    }

    $checkTmux = Invoke-WslCommand -Distro $testDistro -Command "command -v tmux 2>/dev/null" -TimeoutSec 10
    if ($checkTmux.ExitCode -eq 0) {
        Test-Check "VALIDATE" "tmux-available" {
            $r = Invoke-WslCommand -Distro $testDistro -Command "tmux -V" -TimeoutSec 15
            if ($r.ExitCode -ne 0) { throw "tmux failed: $($r.Error)" }
            return $r.Output
        } | Out-Null
    }

    $checkSetupUsername = Invoke-WslCommand -Distro $testDistro -Command "command -v setup-username 2>/dev/null" -TimeoutSec 10
    if ($checkSetupUsername.ExitCode -eq 0) {
        Test-Check "VALIDATE" "setup-username" {
            return "available"
        } | Out-Null
    }

    $checkPodman = Invoke-WslCommand -Distro $testDistro -Command "command -v podman 2>/dev/null" -TimeoutSec 10
    if ($checkPodman.ExitCode -eq 0) {
        Test-Check "VALIDATE" "podman-available" {
            $r = Invoke-WslCommand -Distro $testDistro -Command "podman --version" -TimeoutSec 15
            if ($r.ExitCode -ne 0) { throw "podman failed: $($r.Error)" }
            return $r.Output
        } | Out-Null
    }

    # Terminal profile metadata files inside the distro
    $checkTermProfile = Invoke-WslCommand -Distro $testDistro -Command "test -f /etc/wsl-terminal-profile.json && echo exists" -TimeoutSec 10
    if ($checkTermProfile.Output -eq "exists") {
        Test-Check "VALIDATE" "terminal-profile-json" {
            $r = Invoke-WslCommand -Distro $testDistro -Command "cat /etc/wsl-terminal-profile.json" -TimeoutSec 15
            if ($r.ExitCode -ne 0) { throw "failed to read: $($r.Error)" }
            # Validate it parses as JSON
            try { $r.Output | ConvertFrom-Json | Out-Null } catch { throw "invalid JSON: $_" }
            return "valid JSON"
        } | Out-Null
    }

    $checkDistConf = Invoke-WslCommand -Distro $testDistro -Command "test -f /etc/wsl-distribution.conf && echo exists" -TimeoutSec 10
    if ($checkDistConf.Output -eq "exists") {
        Test-Check "VALIDATE" "distribution-conf" {
            $r = Invoke-WslCommand -Distro $testDistro -Command "cat /etc/wsl-distribution.conf" -TimeoutSec 15
            if ($r.ExitCode -ne 0) { throw "failed to read: $($r.Error)" }
            if ($r.Output -notmatch '\[windowsterminal\]') {
                throw "missing [windowsterminal] section"
            }
            return "has [windowsterminal]"
        } | Out-Null
    }

    # ========================================================================
    # Phase 5 -- Terminal Validation
    # ========================================================================

    if (-not $DoTerminal) {
        Skip-Check "TERMINAL" "all-terminal-checks" "terminal validation skipped"
    } else {
        # Check if Windows Terminal is installed
        $terminalInstalled = (Test-Path "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe") -or
                             (Test-Path "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe") -or
                             (Test-Path "$env:LOCALAPPDATA\Microsoft\Windows Terminal")

        if (-not $terminalInstalled) {
            Skip-Check "TERMINAL" "all-terminal-checks" "Windows Terminal not installed"
        } else {
            # Read registry GUID for the test distro
            $registryGuid = $null
            Test-Check "TERMINAL" "registry-guid" {
                $script:testRegistryGuid = Get-DistroGuid $testDistro
                if (-not $script:testRegistryGuid) { throw "no registry GUID found for $testDistro" }
                return $script:testRegistryGuid
            } | Out-Null
            $registryGuid = $script:testRegistryGuid

            if ($registryGuid) {
                # Independently compute expected GUIDs
                $expectedTier2 = Get-WslProfileGuid $registryGuid
                $expectedTier1Hide = Get-TerminalHideGuid $testDistro

                # Check fragment file exists
                $fragmentDir = Get-TerminalFragmentDir
                $fragmentPath = Join-Path $fragmentDir "$testDistro.json"

                Test-Check "TERMINAL" "fragment-exists" {
                    if (-not (Test-Path $fragmentPath)) {
                        throw "fragment not found: $fragmentPath"
                    }
                    return "found"
                } | Out-Null

                if (Test-Path $fragmentPath) {
                    Test-Check "TERMINAL" "fragment-valid-json" {
                        $raw = Get-Content $fragmentPath -Raw -Encoding UTF8
                        try { $frag = $raw | ConvertFrom-Json } catch { throw "invalid JSON: $_" }
                        if (-not $frag.profiles) { throw "no profiles array in fragment" }
                        $profileCount = @($frag.profiles).Count
                        if ($profileCount -lt 2) { throw "expected 2 profile entries, got $profileCount" }
                        return "$profileCount profiles"
                    } | Out-Null

                    Test-Check "TERMINAL" "tier2-guid-matches" {
                        $raw = Get-Content $fragmentPath -Raw -Encoding UTF8
                        $frag = $raw | ConvertFrom-Json
                        # First profile entry should be the Tier 2 profile with a guid field
                        $fragGuid = $null
                        foreach ($p in $frag.profiles) {
                            if ($p.guid) { $fragGuid = $p.guid; break }
                        }
                        if (-not $fragGuid) { throw "no guid found in fragment profiles" }
                        $fragGuidNorm = "$fragGuid".Trim('{}').ToLower()
                        $expectedNorm = "$expectedTier2".Trim('{}').ToLower()
                        if ($fragGuidNorm -ne $expectedNorm) {
                            throw "fragment={$fragGuidNorm} expected={$expectedNorm}"
                        }
                        return "{$expectedNorm}"
                    } | Out-Null

                    Test-Check "TERMINAL" "tier1-guid-matches" {
                        $raw = Get-Content $fragmentPath -Raw -Encoding UTF8
                        $frag = $raw | ConvertFrom-Json
                        # Second profile entry should be the hide entry with an "updates" field
                        $hideGuid = $null
                        foreach ($p in $frag.profiles) {
                            if ($p.updates -and $p.hidden -eq $true) { $hideGuid = $p.updates; break }
                        }
                        if (-not $hideGuid) { throw "no hidden/updates entry found in fragment" }
                        $hideGuidNorm = "$hideGuid".Trim('{}').ToLower()
                        $expectedNorm = "$expectedTier1Hide".Trim('{}').ToLower()
                        if ($hideGuidNorm -ne $expectedNorm) {
                            throw "fragment={$hideGuidNorm} expected={$expectedNorm}"
                        }
                        return "{$expectedNorm}"
                    } | Out-Null
                }
            }
        }
    }

    # ========================================================================
    # Phase 6 -- Cleanup
    # ========================================================================

    if (-not $DoCleanup) {
        Skip-Check "CLEANUP" "distro-unregistered" "cleanup skipped (-SkipCleanup)"
        Write-Warn "Test distro '$testDistro' left registered for inspection."
        Write-Warn "  Launch: wsl -d $testDistro"
        Write-Warn "  Remove: wsl --unregister $testDistro"
    } else {
        Test-Check "CLEANUP" "distro-unregistered" {
            wsl --unregister $testDistro 2>$null | Out-Null
            # Verify
            $names = Get-WslDistroNames
            if ($testDistro -in $names) { throw "$testDistro still registered after unregister" }
            return "removed"
        } | Out-Null

        # Remove fragment file
        $fragmentPath = Join-Path (Get-TerminalFragmentDir) "$testDistro.json"
        if (Test-Path $fragmentPath) {
            Remove-Item $fragmentPath -Force -ErrorAction SilentlyContinue
            if ($Verbose) { Write-Status "Removed fragment: $fragmentPath" }
        }
    }

    return 0
}

# ============================================================================
# Main execution
# ============================================================================

# --- Phase 0: Prerequisites ---

Write-Host ""
Write-Status "Phase 0: Prerequisites"

# Check WSL is installed and responding
try {
    $wslStatus = wsl --status 2>&1
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Err "WSL is not installed or not responding."
        Write-Err "  wsl --status returned exit code $LASTEXITCODE"
        exit 2
    }
    Write-Ok "WSL is installed and responding."
} catch {
    Write-Err "WSL is not available: $_"
    exit 2
}

# Auto-detect or validate build distro
$needsBuildDistro = (-not $SkipBuild) -or (-not $TarballPath)
if (-not $BuildDistro -and $needsBuildDistro) {
    Write-Status "Auto-detecting build distro (WSL distro with nix)..."
    $runningDistros = Get-WslDistroNames

    foreach ($d in $runningDistros) {
        if (-not $d) { continue }
        $check = Invoke-WslCommand -Distro $d -Command "command -v nix 2>/dev/null" -TimeoutSec 15
        if ($check.ExitCode -eq 0) {
            $BuildDistro = $d
            Write-Ok "Auto-detected build distro: $BuildDistro"
            break
        }
    }

    if (-not $BuildDistro) {
        if ($SkipBuild -and $TarballPath) {
            Write-Warn "No WSL distro with nix found. Discovery will be limited."
        } else {
            Write-Err "No WSL distro with nix found. Cannot build tarballs."
            Write-Err "  Use -BuildDistro to specify one, or -SkipBuild with -TarballPath."
            exit 2
        }
    }
}
elseif ($BuildDistro) {
    # Validate specified build distro
    $check = Invoke-WslCommand -Distro $BuildDistro -Command "command -v nix 2>/dev/null" -TimeoutSec 15
    if ($check.ExitCode -ne 0) {
        Write-Err "Specified build distro '$BuildDistro' does not have nix."
        exit 2
    }
    Write-Ok "Build distro validated: $BuildDistro"
}
elseif ($SkipBuild -and $TarballPath) {
    Write-Warn "No build distro -- skipping discovery (expectations won't be checked)."
}

# Clone repo into temp dir inside build distro (needed for discovery and/or build)
$cloneDir = $null
if ($BuildDistro) {
    Write-Status "Cloning $RepoUrl (branch: $Branch) into build distro..."
    $mktemp = Invoke-WslCommand -Distro $BuildDistro -Command "mktemp -d /tmp/test-wsl-import.XXXXXX" -TimeoutSec 10
    if ($mktemp.ExitCode -ne 0) {
        Write-Err "Failed to create temp directory in $BuildDistro"
        exit 2
    }
    $cloneDir = $mktemp.Output
    $script:CloneTempDir = $cloneDir

    $cloneResult = Invoke-WslCommand -Distro $BuildDistro `
        -Command "git clone --depth 1 --branch $Branch $RepoUrl $cloneDir/nixcfg" `
        -TimeoutSec 120
    if ($cloneResult.ExitCode -ne 0) {
        Write-Err "git clone failed: $($cloneResult.Error)"
        # Clean up temp dir
        Invoke-WslCommand -Distro $BuildDistro -Command "rm -rf $cloneDir" -TimeoutSec 10 | Out-Null
        exit 2
    }
    $cloneDir = "$cloneDir/nixcfg"
    $script:CloneTempDir = $mktemp.Output  # parent dir for cleanup
    Write-Ok "Cloned to $cloneDir in $BuildDistro"
}

# Detect Windows Terminal
$hasTerminal = (Test-Path "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe") -or
               (Test-Path "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe") -or
               (Test-Path "$env:LOCALAPPDATA\Microsoft\Windows Terminal")

if ($hasTerminal) {
    Write-Ok "Windows Terminal detected."
} else {
    Write-Warn "Windows Terminal not detected -- terminal validation will be skipped."
    $SkipTerminalValidation = $true
}

# Disk space check
$drive = (Get-Item $env:LOCALAPPDATA).PSDrive
$freeGB = [math]::Round($drive.Free / 1GB, 1)
if ($freeGB -lt 10) {
    Write-Warn "Low disk space: ${freeGB} GB free on $($drive.Name):. Import may fail."
} else {
    Write-Ok "Disk space: ${freeGB} GB free on $($drive.Name):"
}

Write-Host ""

# --- Determine config list ---

$configList = @()

if ($All) {
    if (-not $BuildDistro -or -not $cloneDir) {
        Write-Err "-All mode requires a build distro for config discovery."
        exit 2
    }

    Write-Status "Discovering WSL-capable configurations..."
    $discoverCmd = "cd $cloneDir && nix eval --json '.#nixosConfigurations' --apply 'cs: builtins.filter (n: (builtins.tryEval (cs.\`${n}).config.wsl.enable).value or false) (builtins.attrNames cs)' 2>/dev/null"
    $result = Invoke-WslCommand -Distro $BuildDistro -Command $discoverCmd -TimeoutSec 60

    if ($result.ExitCode -eq 0 -and $result.Output) {
        $configList = $result.Output | ConvertFrom-Json
        Write-Ok "Found $($configList.Count) WSL-capable config(s): $($configList -join ', ')"
    } else {
        Write-Err "Failed to discover WSL configs. Use -ConfigName instead."
        exit 2
    }
} else {
    $configList = @($ConfigName)
}

# --- Run tests ---

$overallExit = 0
$matrixResults = @()

foreach ($cfg in $configList) {
    $script:Results = @()
    $script:TestStartTime = Get-Date

    $exitCode = Test-SingleConfig `
        -Config $cfg `
        -Tarball $TarballPath `
        -BuildDistroName $BuildDistro `
        -CloneDir $cloneDir `
        -DoBuild (-not $SkipBuild -and -not $TarballPath) `
        -DoTerminal (-not $SkipTerminalValidation) `
        -DoCleanup (-not $SkipCleanup) `
        -BuildTimeout $BuildTimeoutMinutes `
        -BootTimeout $BootTimeoutSeconds

    Write-TestSummary

    $failed = @($script:Results | Where-Object { $_.Status -eq "FAIL" }).Count
    $passed = @($script:Results | Where-Object { $_.Status -eq "PASS" }).Count
    $total = $script:Results.Count

    $matrixResults += [ordered]@{
        Config  = $cfg
        Passed  = $passed
        Failed  = $failed
        Total   = $total
        Exit    = if ($exitCode -eq 2) { 2 } elseif ($failed -gt 0) { 1 } else { 0 }
    }

    if ($exitCode -eq 2) { $overallExit = 2 }
    elseif ($failed -gt 0 -and $overallExit -ne 2) { $overallExit = 1 }
}

# --- Cleanup temp clone dir ---

if ($script:CloneTempDir -and $BuildDistro) {
    Write-Status "Cleaning up temp clone dir..."
    Invoke-WslCommand -Distro $BuildDistro -Command "rm -rf $($script:CloneTempDir)" -TimeoutSec 15 | Out-Null
    if ($Verbose) { Write-Status "Removed $($script:CloneTempDir) in $BuildDistro" }
}

# --- Matrix summary (for -All mode) ---

if ($configList.Count -gt 1) {
    Write-Host ""
    Write-Host "=== Matrix Summary ===" -ForegroundColor Cyan
    foreach ($mr in $matrixResults) {
        $color = if ($mr.Exit -eq 0) { "Green" } elseif ($mr.Exit -eq 2) { "Red" } else { "Yellow" }
        $statusLabel = if ($mr.Exit -eq 0) { "PASS" } elseif ($mr.Exit -eq 2) { "FATAL" } else { "FAIL" }
        Write-Host ("  {0,-30} {1}  ({2}/{3} checks)" -f $mr.Config, $statusLabel, $mr.Passed, ($mr.Total)) -ForegroundColor $color
    }
    Write-Host ""
}

exit $overallExit
