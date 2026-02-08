# Robust Font Detection Functions for Windows Terminal Setup
# Reads actual font metadata instead of hardcoding font names

# Function to get actual font family name from TTF file
function Get-FontFamilyName {
    param([string]$FontPath)
    
    try {
        Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
        $glyphTypeface = New-Object -TypeName Windows.Media.GlyphTypeface -ArgumentList $FontPath
        
        # Try different name sources in order of preference
        $familyName = $null
        if ($glyphTypeface.Win32FamilyNames.ContainsKey('en-us')) {
            $familyName = $glyphTypeface.Win32FamilyNames['en-us']
        } elseif ($glyphTypeface.Win32FamilyNames.Count -gt 0) {
            $familyName = $glyphTypeface.Win32FamilyNames.Values | Select-Object -First 1
        }
        
        $glyphTypeface = $null
        return $familyName
    } catch {
        Write-Warning "Could not read font metadata from $FontPath`: $_"
        return $null
    }
}

# Function to get all available fonts matching a pattern
function Find-InstalledFonts {
    param([string]$Pattern)
    
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $matchingFonts = [System.Drawing.FontFamily]::Families | 
                        Where-Object { $_.Name -like "*$Pattern*" } |
                        Select-Object -ExpandProperty Name
        return $matchingFonts
    } catch {
        Write-Warning "Could not enumerate installed fonts: $_"
        return @()
    }
}

# Function to load font configuration from JSON
function Get-FontConfig {
    # Check if config was already loaded to avoid redundant warnings
    if (Get-Variable -Name "_CachedFontConfig" -Scope Script -ErrorAction SilentlyContinue) {
        return $script:_CachedFontConfig
    }
    
    # Try to load from JSON file in same directory as script
    # Handle case where $MyInvocation.MyCommand.Path is null (e.g., when running from WSL UNC path)
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) {
        # Try alternative methods to get script path
        $scriptPath = $PSCommandPath
        if (-not $scriptPath) {
            # Default to user's bin directory
            $scriptPath = "$env:USERPROFILE\bin\font-config.json"
        }
    }
    
    $configPath = if ($scriptPath -like "*.json") {
        $scriptPath
    } else {
        Join-Path (Split-Path -Parent $scriptPath) "font-config.json"
    }
    
    if ($configPath -and (Test-Path $configPath)) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            $script:_CachedFontConfig = $config
            return $config
        } catch {
            Write-Warning "Failed to load font configuration from $configPath`: $_"
        }
    }
    
    # First try to use injected config from wrapper script
    if (Get-Variable -Name "FontConfigJson" -Scope Global -ErrorAction SilentlyContinue) {
        try {
            $config = $global:FontConfigJson | ConvertFrom-Json
            $script:_CachedFontConfig = $config
            return $config
        } catch {
            Write-Warning "Failed to parse injected font configuration: $_"
        }
    }
    
    # Hardcoded fallback configuration (should match terminal-verification.nix)
    Write-Warning "Using hardcoded fallback font configuration - JSON file not found at $configPath"
    return @{
        terminal = @{
            primary = @{
                name = "CaskaydiaMono Nerd Font Mono"
                nixPackage = "nerd-fonts.caskaydia-mono"
                downloadUrl = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip"
                files = @(
                    "CaskaydiaMonoNerdFontMono-Regular.ttf",
                    "CaskaydiaMonoNerdFontMono-Bold.ttf",
                    "CaskaydiaMonoNerdFontMono-Italic.ttf",
                    "CaskaydiaMonoNerdFontMono-BoldItalic.ttf"
                )
                aliases = @("CaskaydiaMono NFM", "CaskaydiaMonoNerdFontMono", "Cascadia Code", "Cascadia Mono")
            }
            emoji = @{ 
                name = "Noto Color Emoji"
                nixPackage = "noto-fonts-color-emoji"
                downloadUrl = "https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf"
                files = @("NotoColorEmoji.ttf")
            }
            fallback = @{ name = "Segoe UI Emoji" }
        }
        windowsTerminal = @{ intenseTextStyle = "all" }
    }
}

# Function to detect the best available Cascadia font
function Get-BestCascadiaFont {
    $config = Get-FontConfig
    $cascadiaFonts = Find-InstalledFonts -Pattern "Cascadia"
    
    # Build preference order from configuration
    $preferences = @($config.terminal.primary.name) + $config.terminal.primary.aliases
    
    foreach ($preferred in $preferences) {
        $match = $cascadiaFonts | Where-Object { $_ -eq $preferred }
        if ($match) {
            return $match
        }
    }
    
    # If no exact match, return first Cascadia font found
    if ($cascadiaFonts.Count -gt 0) {
        return $cascadiaFonts[0]
    }
    
    return $null
}

# Function to detect installed emoji fonts
function Get-BestEmojiFont {
    $emojiFonts = @()
    $emojiFonts += Find-InstalledFonts -Pattern "Noto Color Emoji"
    $emojiFonts += Find-InstalledFonts -Pattern "Segoe UI Emoji"
    $emojiFonts += Find-InstalledFonts -Pattern "Apple Color Emoji"
    
    # Return first available emoji font
    if ($emojiFonts.Count -gt 0) {
        return $emojiFonts[0]
    }
    
    return "Segoe UI Emoji"  # Fallback to Windows default
}

# Function to build optimal Windows Terminal font configuration
function Get-OptimalTerminalFontConfig {
    $config = Get-FontConfig
    $cascadiaFont = Get-BestCascadiaFont
    $emojiFont = Get-BestEmojiFont
    
    if ($cascadiaFont) {
        $fontFace = "$cascadiaFont, $emojiFont, $($config.terminal.fallback.name)"
    } else {
        # Fallback to system defaults if no Cascadia font available
        $fontFace = "Consolas, $emojiFont, $($config.terminal.fallback.name)"
        Write-Warning "No Cascadia fonts found. Using Consolas as fallback."
    }
    
    return @{
        FontFace = $fontFace
        PrimaryFont = $cascadiaFont
        EmojiFont = $emojiFont
        IntenseTextStyle = $config.windowsTerminal.intenseTextStyle
        Config = $config
    }
}

# Function to validate font installation by reading TTF metadata
function Install-FontWithValidation {
    param(
        [string]$FontPath,
        [string]$ExpectedPattern
    )
    
    # First, get the actual font name from the TTF file
    $actualFontName = Get-FontFamilyName -FontPath $FontPath
    if (-not $actualFontName) {
        Write-Error "Could not determine font name from $FontPath"
        return $false
    }
    
    Write-Host "   Detected font name: $actualFontName" -ForegroundColor Gray
    
    # Install the font using the original method
    $fontFileName = Split-Path $FontPath -Leaf
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fontFileName)
    
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if ($isAdmin) {
            # System installation
            $destPath = "${env:SystemRoot}\Fonts\$fontFileName"
            Copy-Item $FontPath $destPath -Force
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -Name "$baseName (TrueType)" -Value $fontFileName -Force
        } else {
            # User installation
            $userFontsPath = "${env:LOCALAPPDATA}\Microsoft\Windows\Fonts"
            if (-not (Test-Path $userFontsPath)) {
                New-Item -ItemType Directory -Path $userFontsPath -Force | Out-Null
            }
            
            $destPath = "$userFontsPath\$fontFileName"
            Copy-Item $FontPath $destPath -Force
            
            $regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }
            Set-ItemProperty -Path $regPath -Name "$baseName (TrueType)" -Value $destPath -Force
        }
        
        Write-Host "✅ Installed: $actualFontName" -ForegroundColor Green
        
        # Wait a moment for font registration
        Start-Sleep -Seconds 1
        
        # Verify the font is now available
        $availableFonts = Find-InstalledFonts -Pattern $ExpectedPattern
        if ($availableFonts -contains $actualFontName) {
            Write-Host "✅ Verified: Font is available in system" -ForegroundColor Green
            return $actualFontName
        } else {
            Write-Warning "Font installed but not immediately available. May need system refresh."
            return $actualFontName
        }
        
    } catch {
        Write-Error "Failed to install $actualFontName`: $_"
        return $false
    }
}

# Functions are available for dot-sourcing in main script
# No need for Export-ModuleMember when using dot-sourcing