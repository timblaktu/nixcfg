#!/usr/bin/env bash
# diagnose.sh - Read-only diagnostic for the Windows VPN split-tunnel DNS race.
# Runs from WSL, calling Windows .exe helpers directly. Prints a verdict at the end.
# bash- and zsh-safe; no writes, no elevation needed.
set -u

ps() { powershell.exe -NoProfile -Command "$1" 2>/dev/null; }

echo "=== WSL /etc/resolv.conf (dnsTunneling stub 10.255.255.254; NOTE: WSL is NOT immune"
echo "    - dnsTunneling forwards to the racing Windows resolver, so WSL inherits the race) ==="
cat /etc/resolv.conf 2>/dev/null
echo
echo "=== DNS-flap check from WSL (name resolution vs raw IP; run repeatedly with VPN up) ==="
ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 && echo "ping 8.8.8.8 (IP egress) : OK" || echo "ping 8.8.8.8 (IP egress) : FAIL -> route starvation, not the DNS race"
getent hosts github.com  >/dev/null 2>&1 && echo "getent github.com (DNS)  : OK" || echo "getent github.com (DNS)  : FAIL -> DNS race (name flaps while IP egress is fine)"
# corp reachability via HTTP status: git.panasonic.aero returns 403 when the tunnel is
# NOT effective (server-side allowlist), a normal code (200/302) when the VPN works.
# This is a better VPN discriminator than DNS or TCP - the host is publicly reachable.
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 https://git.panasonic.aero 2>/dev/null)"
case "$code" in 200|301|302) echo "corp https (HTTP $code)  : VPN EFFECTIVE";; 403) echo "corp https (HTTP $code)  : VPN NOT effective (403 = not on allowlist)";; *) echo "corp https (HTTP ${code:-000})  : UNREACHABLE";; esac
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
  echo "RACE PRESENT: NRPT empty AND smart resolution enabled -> Windows (and WSL via"
  echo "dnsTunneling) will intermittently fail name resolution while the VPN is up."
  echo "Fix WITH admin:    run fix-dns.ps1 in ELEVATED PowerShell."
  echo "Fix WITHOUT admin: .wslconfig dnsTunneling=false (test first), or WSL-side"
  echo "                   split-DNS (dnsmasq) - see SKILL.md 'Fix WITHOUT admin'."
elif [ "$smart" = "1" ]; then
  echo "FIXED: smart multi-homed resolution is already disabled. If DNS still flaky,"
  echo "check the VPN resolver reachability above and 'ipconfig /flushdns'."
else
  echo "PARTIAL: NRPT has rules (count=$nrpt). Split-DNS may be handling it; verify the"
  echo "per-resolver probe above resolved corporate names correctly."
fi
