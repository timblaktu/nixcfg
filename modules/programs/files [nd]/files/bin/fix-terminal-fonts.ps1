# Simple PowerShell script to fix Windows Terminal font configuration
# Sets font to CaskaydiaMono Nerd Font Mono for proper git icon rendering

Write-Host "Fixing Windows Terminal Font Configuration..." -ForegroundColor Cyan

# Find Windows Terminal settings.json
$settingsPaths = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
)

$settingsPath = $settingsPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $settingsPath) {
    Write-Error "Windows Terminal settings.json not found"
    exit 1
}

Write-Host "Found settings at: $settingsPath" -ForegroundColor Gray

try {
    # Read current settings
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    
    # Ensure defaults exist
    if (-not $settings.profiles.defaults) {
        $settings.profiles | Add-Member -Name "defaults" -Value @{} -MemberType NoteProperty -Force
    }
    
    # Ensure font property exists
    if (-not $settings.profiles.defaults.font) {
        $settings.profiles.defaults | Add-Member -Name "font" -Value @{} -MemberType NoteProperty -Force
    }
    
    # Set the correct font
    $correctFont = "CaskaydiaMono Nerd Font Mono, Noto Color Emoji"
    $settings.profiles.defaults.font | Add-Member -Name "face" -Value $correctFont -MemberType NoteProperty -Force
    
    # Set intense text style for proper bold rendering
    $settings.profiles.defaults | Add-Member -Name "intenseTextStyle" -Value "all" -MemberType NoteProperty -Force
    
    # Backup existing settings
    $backupPath = "$settingsPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $settingsPath $backupPath
    Write-Host "Backed up settings to: $backupPath" -ForegroundColor Gray
    
    # Write updated settings
    $settings | ConvertTo-Json -Depth 100 | Set-Content $settingsPath -Force
    
    Write-Host "✅ Windows Terminal settings updated!" -ForegroundColor Green
    Write-Host "   Font: $correctFont" -ForegroundColor Gray
    Write-Host "   Intense Text Style: all" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "Please restart Windows Terminal for changes to take effect." -ForegroundColor Yellow
    
} catch {
    Write-Error "Failed to update settings: $_"
    exit 1
}