#!/usr/bin/env bash
# diagnose.sh - Read-only diagnostic for the Windows VPN split-tunnel DNS race.
# Runs from WSL, calling Windows .exe helpers directly. Prints a verdict at the end.
# bash- and zsh-safe; no writes, no elevation needed.
set -u

ps() { powershell.exe -NoProfile -Command "$1" 2>/dev/null; }

echo "=== WSL /etc/resolv.conf (should be a single stub; dnsTunneling makes WSL immune) ==="
cat /etc/resolv.conf 2>/dev/null
echo
echo "=== WSL eth0 MTU (Linux side; clamped by mss-clamp - NOT the Windows problem) ==="
ip link show eth0 2>/dev/null | grep -o 'mtu [0-9]*'
echo
echo "=== Windows per-interface DNS servers ==="
ps "Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object {\$_.ServerAddresses} | Select-Object InterfaceAlias,@{n='DNS';e={\$_.ServerAddresses -join ','}} | Format-Table -AutoSize"
echo "=== Windows interface metrics + MTU (VPN adapter should be lowest metric) ==="
ps "Get-NetIPInterface -AddressFamily IPv4 | Where-Object {\$_.ConnectionState -eq 'Connected'} | Sort-Object InterfaceMetric | Format-Table -AutoSize InterfaceAlias,InterfaceMetric,NlMtu"

echo "=== NRPT split-DNS rules (EMPTY output = condition #1 of the race is present) ==="
nrpt="$(ps "(Get-DnsClientNrptPolicy | Measure-Object).Count")"
echo "NRPT rule count: ${nrpt:-0}"

echo "=== Smart multi-homed resolution policy (blank = ENABLED = condition #2 present) ==="
ps "(Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -EA SilentlyContinue | Select-Object DisableSmartNameResolution,DisableParallelAandAAAA | Format-List)"

echo "=== Per-resolver probe of a corporate name (expect VPN=answer, Wi-Fi=NXDOMAIN) ==="
name="${1:-git.panasonic.aero}"
echo "--- WSL getent $name ---"; getent hosts "$name" || echo "(no answer)"
for dns in $(ps "(Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object {\$_.ServerAddresses}).ServerAddresses" | tr -d '\r'); do
  echo "--- nslookup $name @ $dns ---"
  nslookup.exe "$name" "$dns" 2>/dev/null | tail -4
done

echo
echo "=== VERDICT ==="
smart="$(ps "(Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -EA SilentlyContinue).DisableSmartNameResolution" | tr -d '\r')"
if [ "${nrpt:-0}" = "0" ] && [ -z "$smart" ]; then
  echo "RACE PRESENT: NRPT empty AND smart resolution enabled -> Windows will"
  echo "intermittently fail corporate names. Fix: run fix-dns.ps1 in ELEVATED PowerShell."
elif [ "$smart" = "1" ]; then
  echo "FIXED: smart multi-homed resolution is already disabled. If DNS still flaky,"
  echo "check the VPN resolver reachability above and 'ipconfig /flushdns'."
else
  echo "PARTIAL: NRPT has rules (count=$nrpt). Split-DNS may be handling it; verify the"
  echo "per-resolver probe above resolved corporate names correctly."
fi
