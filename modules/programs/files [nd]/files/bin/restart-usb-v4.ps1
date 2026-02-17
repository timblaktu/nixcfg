# restart-usb-v4.ps1 - Complete USB reset with auto-binding for nixos-wsl
# Run as Administrator

Write-Host "=== USB/WSL Reset Script v4 (Auto-Bind Edition) ===" -ForegroundColor Cyan

# Define the nixos-wsl superset from user's config
$nixosSuperset = @("5-1", "5-2", "5-3", "8-1", "8-2", "8-3", "9-1", "9-2", "9-3", "10-1", "10-2", "10-3", 
                   "11-1", "11-2", "11-3", "12-1", "12-2", "12-3", "13-1", "13-2", "13-3", "14-1", "14-2", "14-3")

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "[!] This script must be run as Administrator!" -ForegroundColor Red
    exit 1
}

Write-Host "`nPhase 0: Initial device analysis..." -ForegroundColor Yellow

# Capture initial state including persisted devices
$initialPersistedDevices = @()
$initialConnectedDevices = @()
$parseSection = "none"

foreach ($line in (usbipd list)) {
    if ($line -match "^Connected:") {
        $parseSection = "connected"
        continue
    } elseif ($line -match "^Persisted:") {
        $parseSection = "persisted"
        continue
    }
    
    if ($parseSection -eq "connected" -and $line -match "^(\d+-\d+)\s+(\w+:\w+)\s+(.*?)\s+(Shared|Not shared|Attached)$") {
        $device = @{
            BusId = $matches[1]
            VidPid = $matches[2]
            Description = $matches[3].Trim()
            State = $matches[4]
        }
        $initialConnectedDevices += $device
        if ($device.Description -like "*CP210x*") {
            Write-Host "  - ESP32 connected: $($device.BusId) - $($device.Description) [$($device.State)]" -ForegroundColor Green
        }
    } elseif ($parseSection -eq "persisted" -and $line -match "^([a-f0-9-]+)\s+(.*)$") {
        $device = @{
            Guid = $matches[1]
            Description = $matches[2].Trim()
        }
        $initialPersistedDevices += $device
        Write-Host "  - PERSISTED device: $($device.Description)" -ForegroundColor Yellow
    }
}

$totalEsp32Expected = ($initialConnectedDevices | Where-Object { $_.Description -like "*CP210x*" }).Count + 
                     ($initialPersistedDevices | Where-Object { $_.Description -like "*CP210x*" }).Count

Write-Host "`n  Summary:" -ForegroundColor Cyan
Write-Host "  - Connected ESP32 devices: $(($initialConnectedDevices | Where-Object { $_.Description -like '*CP210x*' }).Count)" -ForegroundColor Green
Write-Host "  - Persisted ESP32 devices: $(($initialPersistedDevices | Where-Object { $_.Description -like '*CP210x*' }).Count)" -ForegroundColor Yellow
Write-Host "  - Total ESP32 devices expected: $totalEsp32Expected" -ForegroundColor Cyan

# Note: You mentioned 7 devices total in your udev rules
if ($totalEsp32Expected -lt 7) {
    Write-Host "  - Note: Only $totalEsp32Expected of 7 expected ESP32 devices are currently visible" -ForegroundColor Yellow
}

# Try to unbind persisted devices first
if ($initialPersistedDevices.Count -gt 0) {
    Write-Host "`nPhase 0.5: Attempting to unbind persisted devices..." -ForegroundColor Yellow
    foreach ($device in $initialPersistedDevices) {
        try {
            Write-Host "  - Unbinding: $($device.Description)" -ForegroundColor Yellow
            & usbipd unbind --guid $device.Guid 2>&1 | Out-Null
        } catch {
            Write-Host "    Failed to unbind (device may not be present)" -ForegroundColor Gray
        }
    }
}

Write-Host "`nPhase 1: Stopping usbipd service..." -ForegroundColor Yellow
Stop-Service -Name "usbipd" -Force -ErrorAction SilentlyContinue
Write-Host "  - Service stopped" -ForegroundColor Green

Write-Host "`nPhase 2: Clearing USB device cache..." -ForegroundColor Yellow
# Remove ghost devices using pnputil
Write-Host "  - Scanning for ghost USB devices..." -ForegroundColor Cyan
try {
    # Get all USB devices including hidden ones
    $ghostDevices = & pnputil /enum-devices /class USB /problem | Select-String "Instance ID:"
    if ($ghostDevices) {
        Write-Host "  - Found potential ghost devices, attempting cleanup..." -ForegroundColor Yellow
        foreach ($device in $ghostDevices) {
            if ($device -match "Instance ID:\s+(.*)") {
                $instanceId = $matches[1].Trim()
                & pnputil /remove-device "$instanceId" 2>&1 | Out-Null
            }
        }
    }
} catch {
    Write-Host "  - Could not clean ghost devices (may require different approach)" -ForegroundColor Gray
}

Write-Host "`nPhase 3: Resetting USB controllers with devcon..." -ForegroundColor Yellow
try {
    # First, try to specifically restart devices that match our VID:PID
    Write-Host "  - Attempting targeted reset of CP210x devices..." -ForegroundColor Cyan
    $targetedResult = & devcon restart "USB\VID_10C4&PID_EA60*" 2>&1
    
    # Then do full USB controller reset
    Write-Host "  - Performing full USB controller reset..." -ForegroundColor Yellow
    $result = & devcon restart "=USB" 2>&1
    Write-Host "  - USB controllers reset complete" -ForegroundColor Green
} catch {
    Write-Host "  - Error resetting USB: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  - Make sure devcon.exe is in your PATH" -ForegroundColor Red
}

Write-Host "`nPhase 4: Starting usbipd service..." -ForegroundColor Yellow
Start-Service -Name "usbipd"
Start-Sleep -Seconds 2
$serviceStatus = Get-Service -Name "usbipd"
Write-Host "  - Service status: $($serviceStatus.Status)" -ForegroundColor $(if($serviceStatus.Status -eq 'Running') {'Green'} else {'Red'})

Write-Host "`nPhase 5: Ensuring WSL is ready..." -ForegroundColor Yellow
# Check available WSL distros and find NixOS
$wslReady = $false
$nixosDistroName = "NixOS"  # Default, will be updated if found differently

try {
    # Get list of WSL distros
    $wslList = wsl --list --quiet
    $nixosFound = $wslList | Where-Object { $_ -like "*NixOS*" -or $_ -like "*nixos*" }
    
    if ($nixosFound) {
        $nixosDistroName = ($nixosFound | Select-Object -First 1).Trim()
        Write-Host "  - Found NixOS distro: $nixosDistroName" -ForegroundColor Green
        
        # Try to ensure it's running
        wsl -d $nixosDistroName echo "NixOS ready" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $wslReady = $true
            Write-Host "  - WSL $nixosDistroName instance ready" -ForegroundColor Green
        }
    }
} catch {
    Write-Host "  - Error checking WSL: $($_.Exception.Message)" -ForegroundColor Yellow
}

if (-not $wslReady) {
    Write-Host "  - WSL NixOS instance not ready, auto-attach may not work" -ForegroundColor Yellow
}

Write-Host "`nPhase 6: Waiting for device re-enumeration..." -ForegroundColor Yellow
Write-Host "  - Monitoring for ESP32 devices..." -ForegroundColor Cyan

# Extended monitoring with detailed progress
$maxWaitTime = 90  # seconds
$checkInterval = 3
$iterations = [math]::Ceiling($maxWaitTime / $checkInterval)
$lastConnectedCount = 0
$lastPersistedCount = 999  # Start high so we detect reduction

for ($i = 1; $i -le $iterations; $i++) {
    Start-Sleep -Seconds $checkInterval
    
    try {
        # Count devices in each category
        $currentOutput = usbipd list 2>$null
        $connectedCount = ($currentOutput | Select-String "CP210x" | Select-String -Pattern "(Shared|Not shared|Attached)").Count
        $persistedCount = 0
        
        # Count persisted devices
        $inPersistedSection = $false
        foreach ($line in $currentOutput) {
            if ($line -match "^Persisted:") {
                $inPersistedSection = $true
                continue
            }
            if ($inPersistedSection -and $line -match "CP210x") {
                $persistedCount++
            }
        }
        
        $totalFound = $connectedCount + $persistedCount
        $elapsed = $i * $checkInterval
        
        Write-Host "    - Progress (${elapsed}s): $connectedCount connected, $persistedCount persisted (Total: $totalFound)" -ForegroundColor Gray
        
        # Check if we're making progress
        if ($persistedCount -lt $lastPersistedCount) {
            Write-Host "      [+] Persisted devices are being rediscovered!" -ForegroundColor Green
        }
        
        # Stop if we've found enough devices and they're stable
        if ($i -gt 3 -and $connectedCount -gt 0 -and $connectedCount -eq $lastConnectedCount -and $persistedCount -eq $lastPersistedCount) {
            Write-Host "    - Device enumeration stabilized" -ForegroundColor Green
            break
        }
        
        $lastConnectedCount = $connectedCount
        $lastPersistedCount = $persistedCount
        
    } catch {
        Write-Host "    - Waiting... (${elapsed}s)" -ForegroundColor Gray
    }
}

Write-Host "`nPhase 7: Binding ESP32 devices for WSL access..." -ForegroundColor Yellow

# Get current device list and bind all CP210x devices
$devicesToBind = @()
$parseSection = "none"

foreach ($line in (usbipd list)) {
    if ($line -match "^Connected:") {
        $parseSection = "connected"
        continue
    } elseif ($line -match "^Persisted:") {
        $parseSection = "persisted"
        continue
    }
    
    if ($parseSection -eq "connected" -and $line -match "^(\d+-\d+)\s+10c4:ea60\s+(.*?)\s+(Not shared|Shared|Attached)$") {
        $busId = $matches[1]
        $description = $matches[2].Trim()
        $state = $matches[3]
        
        if ($state -eq "Not shared") {
            $devicesToBind += @{
                BusId = $busId
                Description = $description
            }
        }
    }
}

if ($devicesToBind.Count -gt 0) {
    Write-Host "  - Found $($devicesToBind.Count) ESP32 devices to bind" -ForegroundColor Cyan
    
    foreach ($device in $devicesToBind) {
        try {
            Write-Host "  - Binding $($device.BusId): $($device.Description)..." -ForegroundColor Yellow
            & usbipd bind --busid $device.BusId 2>&1 | Out-Null
            Write-Host "    [OK] Bound successfully" -ForegroundColor Green
        } catch {
            Write-Host "    [!] Failed to bind: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    # Give binding a moment to complete
    Start-Sleep -Seconds 2
} else {
    Write-Host "  - All ESP32 devices already bound/shared" -ForegroundColor Green
}

# If WSL is ready, give auto-attach time to work
if ($wslReady) {
    Write-Host "`nPhase 8: Waiting for nixos-wsl auto-attach..." -ForegroundColor Yellow
    Write-Host "  - NixOS should auto-attach devices in the superset" -ForegroundColor Cyan
    Start-Sleep -Seconds 10
}

Write-Host "`n=== Final Status Report ===" -ForegroundColor Cyan
$finalOutput = usbipd list
Write-Host $finalOutput

# Final analysis
Write-Host "`nFinal Analysis:" -ForegroundColor Yellow
$finalConnected = 0
$finalAttached = 0
$finalShared = 0
$finalPersisted = 0
$inPersistedSection = $false
$finalPersistedDevices = @()
$devicesOutsideSuperset = @()

foreach ($line in $finalOutput) {
    if ($line -match "^Persisted:") {
        $inPersistedSection = $true
        continue
    }
    
    if (-not $inPersistedSection -and $line -match "^(\d+-\d+)\s+10c4:ea60\s+(.*?)\s+(Not shared|Shared|Attached)$") {
        $busId = $matches[1]
        $description = $matches[2].Trim()
        $state = $matches[3]
        
        $finalConnected++
        
        if ($state -eq "Attached") {
            $finalAttached++
            # Check if this bus ID is in the superset
            if ($busId -notin $nixosSuperset) {
                $devicesOutsideSuperset += $busId
            }
        } elseif ($state -eq "Shared") {
            $finalShared++
        }
    } elseif ($inPersistedSection -and $line -match "([a-f0-9-]+)\s+(.*CP210x.*)") {
        $finalPersisted++
        $finalPersistedDevices += $matches[2].Trim()
    }
}

Write-Host "  - Total ESP32 devices found: $finalConnected" -ForegroundColor $(if($finalConnected -ge 5) {'Green'} else {'Yellow'})
Write-Host "  - Devices attached to WSL: $finalAttached" -ForegroundColor $(if($finalAttached -gt 0) {'Green'} else {'Yellow'})
Write-Host "  - Devices shared (ready for attach): $finalShared" -ForegroundColor $(if($finalShared -gt 0) {'Green'} else {'Yellow'})
Write-Host "  - Persisted devices: $finalPersisted" -ForegroundColor $(if($finalPersisted -eq 0) {'Green'} else {'Red'})

if ($finalPersisted -gt 0) {
    Write-Host "`n[!] PERSISTENT DEVICE ISSUE DETECTED" -ForegroundColor Red
    Write-Host "The following devices remain in 'Persisted' state:" -ForegroundColor Red
    foreach ($device in $finalPersistedDevices) {
        Write-Host "  - $device" -ForegroundColor Red
    }
} 

if ($devicesOutsideSuperset.Count -gt 0) {
    Write-Host "`n[!] Devices attached outside your nixos-wsl superset:" -ForegroundColor Yellow
    foreach ($busId in $devicesOutsideSuperset) {
        Write-Host "  - $busId" -ForegroundColor Yellow
    }
    Write-Host "`nConsider adding these to your nixos-wsl config:" -ForegroundColor Cyan
    $suggestedAdditions = $devicesOutsideSuperset | ForEach-Object { "`"$_`"" } | Sort-Object -Unique
    Write-Host "  wsl.usbip.autoAttach = [ ... $($suggestedAdditions -join '  ') ];" -ForegroundColor Cyan
}

if ($finalConnected -lt 7) {
    Write-Host "`n[!] Only found $finalConnected of 7 expected ESP32 devices" -ForegroundColor Yellow
    Write-Host "Missing devices may need:" -ForegroundColor Yellow
    Write-Host "  - Physical power cycle of the USB hub" -ForegroundColor White
    Write-Host "  - Check USB hub power and connections" -ForegroundColor White
}

Write-Host "`nScript complete." -ForegroundColor Cyan

if ($finalShared -gt 0 -and $finalAttached -eq 0) {
    Write-Host "`n[i] Devices are shared but not attached. To manually attach:" -ForegroundColor Yellow
    Write-Host "  usbipd attach --wsl --busid <BUSID>" -ForegroundColor Cyan
    Write-Host "Or restart your NixOS instance to trigger auto-attach." -ForegroundColor Cyan
}
