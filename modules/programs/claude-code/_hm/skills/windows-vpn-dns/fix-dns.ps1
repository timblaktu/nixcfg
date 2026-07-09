# fix-dns.ps1 - Fix the Windows VPN split-tunnel DNS race (GlobalProtect / PANGP).
#
# Disables Windows "smart multi-homed name resolution" so lookups go to interfaces
# in metric order (VPN first) instead of racing every resolver in parallel - which
# lets a non-VPN resolver's fast NXDOMAIN intermittently win. One-time, persistent
# machine policy; survives reboots, VPN reconnects, and GP updates.
#
# MUST be run in an ELEVATED (Administrator) PowerShell. It writes an HKLM policy
# key. Right-click PowerShell -> Run as administrator, or Win -> PowerShell ->
# Ctrl+Shift+Enter, then: powershell -ExecutionPolicy Bypass -File .\fix-dns.ps1

$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'ERROR: not elevated. This writes an HKLM policy key and needs Admin.' -ForegroundColor Red
    Write-Host 'Open an elevated PowerShell (Ctrl+Shift+Enter) and re-run.' -ForegroundColor Yellow
    exit 1
}

$k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
try {
    New-Item $k -Force | Out-Null
    Set-ItemProperty $k DisableSmartNameResolution 1 -Type DWord
    Set-ItemProperty $k DisableParallelAandAAAA   1 -Type DWord
    ipconfig /flushdns | Out-Null
    Write-Host 'OK: smart multi-homed name resolution disabled; DNS cache flushed.' -ForegroundColor Green
    Write-Host 'Windows now resolves via interface metric order (VPN first).'
    Get-ItemProperty $k | Select-Object DisableSmartNameResolution, DisableParallelAandAAAA | Format-List
}
catch {
    Write-Host "DENIED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'If denied even when elevated, corporate GPO locks this hive.' -ForegroundColor Yellow
    Write-Host 'Then ask IT to push NRPT split-DNS on the GlobalProtect portal.'
    exit 1
}
