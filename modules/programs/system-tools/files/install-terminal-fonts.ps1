# PowerShell Font Installation Script for WSL Terminal Setup
# Robust approach: Detect actual font names → Download if missing → Install → Configure dynamically

param(
    [switch]$Force,
    [switch]$NoPrompt
)

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "            Windows Terminal Font Installation Script                  " -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "                   Robust Font Detection System                       " -ForegroundColor Yellow
Write-Host ""

# Load font detection functions - try multiple locations
$fontFunctionsLoaded = $false

# Try same directory as script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$fontFunctionsPath = Join-Path $scriptDir "font-detection-functions.ps1"

if (Test-Path $fontFunctionsPath) {
    try {
        . $fontFunctionsPath
        $fontFunctionsLoaded = $true
        Write-Host "✅ Loaded robust font detection system" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to load font detection functions: $_"
    }
} else {
    # Try user's bin directory (home-manager deployment location)
    $userBinPath = "$env:USERPROFILE\bin\font-detection-functions.ps1"
    if (Test-Path $userBinPath) {
        try {
            . $userBinPath
            $fontFunctionsLoaded = $true
            Write-Host "✅ Loaded robust font detection system from user bin" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to load font detection functions from user bin: $_"
        }
    }
}

if (-not $fontFunctionsLoaded) {
    Write-Warning "Font detection functions not found. Using fallback mode."
    Write-Host "  Searched: $fontFunctionsPath" -ForegroundColor Gray
    Write-Host "  Searched: $env:USERPROFILE\bin\font-detection-functions.ps1" -ForegroundColor Gray
}

# Load font configuration
if (Get-Command "Get-FontConfig" -ErrorAction SilentlyContinue) {
    $FontConfig = Get-FontConfig
    $CascadiaFiles = $FontConfig.terminal.primary.files
    $NotoFile = $FontConfig.terminal.emoji.files[0]
    $CascadiaUrl = $FontConfig.terminal.primary.downloadUrl
    $NotoUrl = $FontConfig.terminal.emoji.downloadUrl
    Write-Host "✅ Loaded font configuration from JSON" -ForegroundColor Green
} else {
    # Fallback configuration
    Write-Warning "Using hardcoded fallback font configuration"
    $CascadiaFiles = @(
        'CaskaydiaMonoNerdFontMono-Regular.ttf',
        'CaskaydiaMonoNerdFontMono-Bold.ttf',
        'CaskaydiaMonoNerdFontMono-Italic.ttf',
        'CaskaydiaMonoNerdFontMono-BoldItalic.ttf'
    )
    $NotoFile = 'NotoColorEmoji.ttf'
    $CascadiaUrl = 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip'
    $NotoUrl = 'https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf'
}


# Paths
$DownloadsPath = "$env:USERPROFILE\Downloads"
$TempPath = "$env:TEMP\FontInstall"
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Warning "Running without administrator privileges. Fonts will be installed for current user only."
}

# Function to check if font is installed
function Test-FontInstalled($FontName) {
    try {
        Add-Type -AssemblyName System.Drawing
        $family = [System.Drawing.FontFamily]::new($FontName)
        $result = $family.IsStyleAvailable([System.Drawing.FontStyle]::Regular)
        $family.Dispose()
        return $result
    } catch {
        return $false
    }
}

# Function to install a font file
function Install-Font($FontPath, $FontName) {
    if (-not (Test-Path $FontPath)) {
        Write-Error "Font file not found: $FontPath"
        return $false
    }
    
    try {
        $FontFileName = Split-Path $FontPath -Leaf
        
        if ($IsAdmin) {
            # System installation
            $DestPath = "${env:SystemRoot}\Fonts\$FontFileName"
            Copy-Item $FontPath $DestPath -Force
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -Name "$FontName (TrueType)" -Value $FontFileName -Force
        } else {
            # User installation
            $UserFontsPath = "${env:LOCALAPPDATA}\Microsoft\Windows\Fonts"
            if (-not (Test-Path $UserFontsPath)) {
                New-Item -ItemType Directory -Path $UserFontsPath -Force | Out-Null
            }
            $DestPath = "$UserFontsPath\$FontFileName"
            Copy-Item $FontPath $DestPath -Force
            
            $RegPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
            if (-not (Test-Path $RegPath)) {
                New-Item -Path $RegPath -Force | Out-Null
            }
            Set-ItemProperty -Path $RegPath -Name "$FontName (TrueType)" -Value $DestPath -Force
        }
        
        Write-Host "✅ Installed: $FontName" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to install $FontName`: $_"
        return $false
    }
}

# Check current font status using robust detection
Write-Host "Analyzing font installation status..." -ForegroundColor Yellow

if (Get-Command "Get-BestCascadiaFont" -ErrorAction SilentlyContinue) {
    # Use robust detection system
    $detectedCascadia = Get-BestCascadiaFont
    $detectedEmoji = Get-BestEmojiFont
    
    $CascadiaInstalled = $null -ne $detectedCascadia
    $NotoInstalled = $detectedEmoji -eq "Noto Color Emoji"
    
    Write-Host "Cascadia fonts: $(if ($CascadiaInstalled) { "✅ Found: $detectedCascadia" } else { '❌ None found' })" -ForegroundColor $(if ($CascadiaInstalled) { 'Green' } else { 'Red' })
    Write-Host "Emoji fonts: $(if ($NotoInstalled) { "✅ Found: $detectedEmoji" } else { "⚠️  Using fallback: $detectedEmoji" })" -ForegroundColor $(if ($NotoInstalled) { 'Green' } else { 'Yellow' })
    
    # Show all available Cascadia variants if any exist
    $allCascadia = Find-InstalledFonts -Pattern "Cascadia"
    if ($allCascadia.Count -gt 0) {
        Write-Host "Available Cascadia fonts:" -ForegroundColor Gray
        $allCascadia | ForEach-Object { Write-Host "  • $_" -ForegroundColor Gray }
    }
} else {
    # Fallback mode - use basic detection
    Write-Warning "Using basic font detection (robust system not available)"
    $CascadiaInstalled = Test-FontInstalled -FontName "CaskaydiaMono NFM"
    $NotoInstalled = Test-FontInstalled -FontName "Noto Color Emoji"
    
    Write-Host "CaskaydiaMono NFM: $(if ($CascadiaInstalled) { '✅ Installed' } else { '❌ Missing' })" -ForegroundColor $(if ($CascadiaInstalled) { 'Green' } else { 'Red' })
    Write-Host "Noto Color Emoji: $(if ($NotoInstalled) { '✅ Installed' } else { '❌ Missing' })" -ForegroundColor $(if ($NotoInstalled) { 'Green' } else { 'Red' })
}

# Process Cascadia fonts if needed
if (-not $CascadiaInstalled -or $Force) {
    Write-Host "`nProcessing CascadiaMono Nerd Font..." -ForegroundColor Cyan
    
    # Check Downloads for existing files
    $FoundAll = $true
    $CascadiaPath = $null
    
    foreach ($File in $CascadiaFiles) {
        $Found = Get-ChildItem -Path $DownloadsPath -Filter $File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($Found) {
            if (-not $CascadiaPath) {
                $CascadiaPath = Split-Path $Found.FullName -Parent
            }
        } else {
            $FoundAll = $false
            break
        }
    }
    
    if ($FoundAll -and $CascadiaPath) {
        Write-Host "✅ Found CascadiaMono fonts in Downloads: $CascadiaPath" -ForegroundColor Green
    } else {
        # Check for zip file
        $ZipPath = "$DownloadsPath\CascadiaMono.zip"
        if (Test-Path $ZipPath) {
            Write-Host "✅ Found CascadiaMono.zip in Downloads" -ForegroundColor Green
            
            # Extract to temp
            if (Test-Path $TempPath) { Remove-Item $TempPath -Recurse -Force }
            New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
            
            Expand-Archive -Path $ZipPath -DestinationPath $TempPath -Force
            $CascadiaPath = Get-ChildItem -Path $TempPath -Filter $CascadiaFiles[0] -Recurse | Select-Object -First 1 | ForEach-Object { Split-Path $_.FullName -Parent }
            
            if ($CascadiaPath) {
                Write-Host "✅ Extracted from Downloads zip" -ForegroundColor Green
            } else {
                Write-Error "Failed to find fonts in extracted zip"
                exit 1
            }
        } else {
            # Download
            Write-Host "Downloading CascadiaMono from GitHub..." -ForegroundColor Yellow
            
            if (Test-Path $TempPath) { Remove-Item $TempPath -Recurse -Force }
            New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
            
            $ZipPath = "$TempPath\CascadiaMono.zip"
            Invoke-WebRequest -Uri $CascadiaUrl -OutFile $ZipPath -UseBasicParsing
            
            Expand-Archive -Path $ZipPath -DestinationPath $TempPath -Force
            $CascadiaPath = Get-ChildItem -Path $TempPath -Filter $CascadiaFiles[0] -Recurse | Select-Object -First 1 | ForEach-Object { Split-Path $_.FullName -Parent }
            
            if ($CascadiaPath) {
                Write-Host "✅ Downloaded and extracted" -ForegroundColor Green
            } else {
                Write-Error "Failed to find fonts in downloaded archive"
                exit 1
            }
        }
    }
    
    # Install Cascadia fonts
    foreach ($File in $CascadiaFiles) {
        $FontPath = "$CascadiaPath\$File"
        if (Test-Path $FontPath) {
            $FontName = [System.IO.Path]::GetFileNameWithoutExtension($File)
            Install-Font -FontPath $FontPath -FontName $FontName
        } else {
            Write-Error "Font file not found: $FontPath"
            exit 1
        }
    }
}

# Process Noto emoji if needed
if (-not $NotoInstalled -or $Force) {
    Write-Host "`nProcessing Noto Color Emoji..." -ForegroundColor Cyan
    
    # Check Downloads for existing file
    $NotoPath = Get-ChildItem -Path $DownloadsPath -Filter $NotoFile -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    
    if ($NotoPath) {
        Write-Host "✅ Found $NotoFile in Downloads: $($NotoPath.DirectoryName)" -ForegroundColor Green
        $FontPath = $NotoPath.FullName
    } else {
        # Download
        Write-Host "Downloading Noto Color Emoji..." -ForegroundColor Yellow
        
        if (-not (Test-Path $TempPath)) {
            New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
        }
        
        $FontPath = "$TempPath\$NotoFile"
        Invoke-WebRequest -Uri $NotoUrl -OutFile $FontPath -UseBasicParsing
        Write-Host "✅ Downloaded" -ForegroundColor Green
    }
    
    # Install Noto font
    Install-Font -FontPath $FontPath -FontName "Noto Color Emoji"
}

# Update Windows Terminal settings using dynamic font detection
Write-Host "`nConfiguring Windows Terminal with detected fonts..." -ForegroundColor Cyan

# Try to find Windows Terminal settings - check both regular and Preview versions
$SettingsPaths = @(
    "${env:LOCALAPPDATA}\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "${env:LOCALAPPDATA}\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
)

$SettingsPath = $null
foreach ($path in $SettingsPaths) {
    if (Test-Path $path) {
        $SettingsPath = $path
        Write-Host "Found Windows Terminal settings at: $path" -ForegroundColor Gray
        break
    }
}

if (-not $SettingsPath) {
    # If still not found, use the default path
    $SettingsPath = $SettingsPaths[0]
}

# Get optimal font configuration based on what's actually installed
if (Get-Command "Get-OptimalTerminalFontConfig" -ErrorAction SilentlyContinue) {
    $fontConfig = Get-OptimalTerminalFontConfig
    $TerminalFontFace = $fontConfig.FontFace
    $TerminalIntenseStyle = $fontConfig.IntenseTextStyle
    
    Write-Host "Detected optimal configuration:" -ForegroundColor Green
    Write-Host "  Primary font: $($fontConfig.PrimaryFont)" -ForegroundColor Gray
    Write-Host "  Emoji font: $($fontConfig.EmojiFont)" -ForegroundColor Gray
    Write-Host "  Full font stack: $TerminalFontFace" -ForegroundColor Gray
} else {
    # Fallback to hardcoded values if detection not available
    $TerminalFontFace = 'CaskaydiaMono NFM, Noto Color Emoji, Segoe UI Emoji'
    $TerminalIntenseStyle = 'all'
    Write-Warning "Using fallback font configuration"
}

if (Test-Path $SettingsPath) {
    try {
        # Read and backup first
        $BackupPath = "${SettingsPath}.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $SettingsPath $BackupPath
        Write-Host "✅ Backup created: $BackupPath" -ForegroundColor Green
        
        # Read settings content
        $SettingsContent = Get-Content $SettingsPath -Raw
        $Settings = $SettingsContent | ConvertFrom-Json
        
        # Create proper nested structure using hashtables for better JSON handling
        if (-not $Settings.profiles) {
            $Settings | Add-Member -Name "profiles" -Value @{} -MemberType NoteProperty -Force
        }
        if (-not $Settings.profiles.defaults) {
            $Settings.profiles | Add-Member -Name "defaults" -Value @{} -MemberType NoteProperty -Force
        }
        if (-not $Settings.profiles.defaults.font) {
            $Settings.profiles.defaults | Add-Member -Name "font" -Value @{} -MemberType NoteProperty -Force
        }
        
        # Update font settings with dynamically detected values
        $Settings.profiles.defaults.font | Add-Member -Name "face" -Value $TerminalFontFace -MemberType NoteProperty -Force
        $Settings.profiles.defaults | Add-Member -Name "intenseTextStyle" -Value $TerminalIntenseStyle -MemberType NoteProperty -Force
        
        # Convert back to JSON with consistent formatting
        $JsonOutput = $Settings | ConvertTo-Json -Depth 20 -Compress:$false
        $JsonOutput | Set-Content $SettingsPath -Encoding UTF8
        
        Write-Host "✅ Windows Terminal settings updated with detected fonts" -ForegroundColor Green
        Write-Host "   Font stack: $TerminalFontFace" -ForegroundColor Gray
        Write-Host "   Bold rendering: $TerminalIntenseStyle" -ForegroundColor Gray
    } catch {
        Write-Warning "Failed to update Windows Terminal settings: $_"
        Write-Host "You can manually set these in Windows Terminal:" -ForegroundColor Yellow
        Write-Host "  Font face: $TerminalFontFace" -ForegroundColor Yellow
        Write-Host "  Intense text style: $TerminalIntenseStyle" -ForegroundColor Yellow
        
        # Restore backup if update failed
        if (Test-Path $BackupPath) {
            Copy-Item $BackupPath $SettingsPath -Force
            Write-Host "⚠️  Settings restored from backup due to error" -ForegroundColor Yellow
        }
    }
} else {
    Write-Warning "Windows Terminal settings.json not found"
    Write-Host "Please manually configure Windows Terminal:" -ForegroundColor Yellow
    Write-Host "  Font face: $TerminalFontFace" -ForegroundColor Yellow
    Write-Host "  Intense text style: $TerminalIntenseStyle" -ForegroundColor Yellow
}

# Cleanup
if (Test-Path $TempPath) {
    Remove-Item $TempPath -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n🎉 INSTALLATION COMPLETE! 🎉" -ForegroundColor Green

# Attempt to restart Windows Terminal if we're running inside it
$currentProcess = Get-Process -Id $PID
$parentProcess = Get-WmiObject Win32_Process -Filter "ProcessId = $($currentProcess.Id)" | 
    Select-Object -ExpandProperty ParentProcessId
    
if ($parentProcess) {
    $parent = Get-Process -Id $parentProcess -ErrorAction SilentlyContinue
    if ($parent -and ($parent.ProcessName -match "WindowsTerminal|wt")) {
        Write-Host "`n🔄 Windows Terminal detected. Would you like to restart it now?" -ForegroundColor Cyan
        Write-Host "   This will close all tabs and restart Terminal with new settings." -ForegroundColor Yellow
        $restart = Read-Host "   Restart Windows Terminal? [Y/n]"
        
        if ($restart -eq '' -or $restart -match '^[Yy]') {
            Write-Host "   Restarting Windows Terminal in 3 seconds..." -ForegroundColor Green
            Write-Host "   Press Ctrl+C to cancel" -ForegroundColor Yellow
            Start-Sleep -Seconds 3
            
            # Save the current working directory
            $currentDir = Get-Location
            
            # Get Windows Terminal executable path
            $wtPath = (Get-Command wt.exe -ErrorAction SilentlyContinue).Source
            if (-not $wtPath) {
                # Try to find Windows Terminal in common locations
                $possiblePaths = @(
                    "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe",
                    "$env:ProgramFiles\WindowsApps\Microsoft.WindowsTerminal*\wt.exe",
                    "$env:ProgramFiles\WindowsApps\Microsoft.WindowsTerminalPreview*\wt.exe"
                )
                foreach ($path in $possiblePaths) {
                    if (Test-Path $path) {
                        $wtPath = $path
                        break
                    }
                }
            }
            
            if ($wtPath) {
                # Start new Terminal instance before closing current one
                Start-Process $wtPath -ArgumentList "-d", "`"$currentDir`"" -WindowStyle Normal
                Start-Sleep -Seconds 1
                
                # Close current Windows Terminal
                Stop-Process -Id $parentProcess -Force
            } else {
                Write-Warning "Could not find Windows Terminal executable path"
                Write-Host "Please restart Windows Terminal manually" -ForegroundColor Yellow
            }
        } else {
            Write-Host "📋 NEXT STEPS:" -ForegroundColor Cyan
            Write-Host "1. Restart Windows Terminal manually" -ForegroundColor White
            Write-Host "2. Run 'check-terminal-setup' in WSL to verify" -ForegroundColor White
            Write-Host "3. Enjoy perfect emoji rendering! ⚠️ ✅ ❌ 🔥" -ForegroundColor White
        }
    } else {
        Write-Host "📋 NEXT STEPS:" -ForegroundColor Cyan
        Write-Host "1. Restart Windows Terminal" -ForegroundColor White
        Write-Host "2. Run 'check-terminal-setup' in WSL to verify" -ForegroundColor White
        Write-Host "3. Enjoy perfect emoji rendering! ⚠️ ✅ ❌ 🔥" -ForegroundColor White
    }
} else {
    Write-Host "📋 NEXT STEPS:" -ForegroundColor Cyan
    Write-Host "1. Restart Windows Terminal" -ForegroundColor White
    Write-Host "2. Run 'check-terminal-setup' in WSL to verify" -ForegroundColor White
    Write-Host "3. Enjoy perfect emoji rendering! ⚠️ ✅ ❌ 🔥" -ForegroundColor White
}