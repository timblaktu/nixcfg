# Install Noto Color Emoji font for Windows Terminal
# This script downloads and installs the Noto Color Emoji font

param(
    [switch]$Force = $false
)

Write-Host "Noto Color Emoji Font Installer" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan

# Check if running as admin (required for system-wide install)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin) {
    Write-Host "Note: Running without admin rights - installing to user fonts" -ForegroundColor Yellow
}

# Check if font is already installed
Add-Type -AssemblyName System.Drawing
$fonts = [System.Drawing.Text.InstalledFontCollection]::new()
$notoInstalled = $fonts.Families | Where-Object { $_.Name -eq "Noto Color Emoji" }

if ($notoInstalled -and -not $Force) {
    Write-Host "✅ Noto Color Emoji is already installed!" -ForegroundColor Green
    exit 0
}

if ($notoInstalled -and $Force) {
    Write-Host "Font already installed, but -Force specified. Reinstalling..." -ForegroundColor Yellow
}

# Download URL
$downloadUrl = "https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf"
$fontFileName = "NotoColorEmoji.ttf"

# Determine installation path
if ($isAdmin) {
    $fontsPath = "$env:WINDIR\Fonts"
    Write-Host "Installing to system fonts: $fontsPath" -ForegroundColor Gray
} else {
    $fontsPath = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    if (-not (Test-Path $fontsPath)) {
        New-Item -ItemType Directory -Path $fontsPath -Force | Out-Null
    }
    Write-Host "Installing to user fonts: $fontsPath" -ForegroundColor Gray
}

$fontFilePath = Join-Path $fontsPath $fontFileName

try {
    Write-Host "⬇️  Downloading Noto Color Emoji..." -ForegroundColor Yellow

    # Download with progress
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($downloadUrl, $fontFilePath)

    Write-Host "✅ Download complete!" -ForegroundColor Green

    # Register the font
    Write-Host "📝 Registering font..." -ForegroundColor Yellow

    if ($isAdmin) {
        # System-wide registration
        $fontRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        New-ItemProperty -Path $fontRegPath -Name "Noto Color Emoji (TrueType)" -Value $fontFileName -Force -ErrorAction SilentlyContinue | Out-Null
    } else {
        # User registration
        $fontRegPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        if (-not (Test-Path $fontRegPath)) {
            New-Item -Path $fontRegPath -Force | Out-Null
        }
        New-ItemProperty -Path $fontRegPath -Name "Noto Color Emoji (TrueType)" -Value $fontFilePath -Force -ErrorAction SilentlyContinue | Out-Null
    }

    # Notify Windows of font change
    Add-Type @"
        using System;
        using System.Runtime.InteropServices;
        public class FontNotifier {
            [DllImport("user32.dll", CharSet = CharSet.Auto)]
            public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
            public static void NotifyFontChange() {
                SendMessage(new IntPtr(0xFFFF), 0x001D, IntPtr.Zero, IntPtr.Zero);
            }
        }
"@
    [FontNotifier]::NotifyFontChange()

    Write-Host "✅ Font installed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Close all Windows Terminal windows" -ForegroundColor White
    Write-Host "2. Reopen Windows Terminal" -ForegroundColor White
    Write-Host "3. The font will be available as 'Noto Color Emoji'" -ForegroundColor White
    Write-Host ""
    Write-Host "To use in Windows Terminal, run:" -ForegroundColor Yellow
    Write-Host "  home-manager switch --flake '.#$env:USER@$env:COMPUTERNAME'" -ForegroundColor White

} catch {
    Write-Host "❌ Installation failed: $_" -ForegroundColor Red
    if (Test-Path $fontFilePath) {
        Remove-Item $fontFilePath -Force -ErrorAction SilentlyContinue
    }
    exit 1
}