#!/usr/bin/env bash
# capture.sh — Sample WSL + Windows network state across a GlobalProtect VPN
# connect/disconnect transition, WITHOUT depending on WSL network egress or on
# Claude Code being alive.
#
# WHY THIS EXISTS: Claude Code runs *inside* WSL, so when the VPN breaks WSL's
# egress (or DNS), the CLI cannot reach api.anthropic.com and the whole session
# hangs — you cannot diagnose the outage from within Claude. This script is
# self-contained: run it in a PLAIN WSL terminal, reproduce the transition, then
# have Claude read the log AFTER connectivity is restored.
#
# Every command is either (a) WSL-local kernel state, or (b) a Windows .exe over
# interop — both keep working while WSL's outbound path is dead (interop is a
# vsock pipe, not the network). Every probe that could block is `timeout`-wrapped.
#
# The heartbeat distinguishes the two failure modes at a glance:
#   ping8.8.8.8=OK  DNS=FAIL   -> DNS race (name resolution flaps, IP egress fine)
#   ping8.8.8.8=FAIL           -> route starvation (GP hijacked routes / WSL subnet)
#
# USAGE:
#   1. In a PLAIN WSL terminal (NOT via Claude):  bash capture.sh
#   2. Connect GlobalProtect, wait ~30s, exercise it; then disconnect, wait ~15s.
#   3. Ctrl-C. Then tell Claude: "capture done" and point it at the log.
#
# Tunables (env):
#   LOG=<path>         default $HOME/wsl-vpn-transition.log
#   CORP_HOST=<host>   default git.panasonic.aero (403 w/o VPN, 200/302 with = discriminator)
#   INTERVAL=<secs>    default 5

LOG=${LOG:-$HOME/wsl-vpn-transition.log}
CORP_HOST=${CORP_HOST:-git.panasonic.aero}
INTERVAL=${INTERVAL:-5}
TO="timeout -k 1 3"

snap() {
  echo "======================================================================"
  echo "SNAPSHOT $(date +%Y-%m-%d\ %H:%M:%S\ %Z)"
  echo "======================================================================"
  echo "--- [Win] PANGP adapter status ---"
  $TO powershell.exe -NoProfile -Command \
    "Get-NetAdapter | Where-Object {\$_.InterfaceDescription -match 'PANGP'} | Format-Table Name,Status,InterfaceDescription -AutoSize" 2>/dev/null | tr -d '\r'
  echo "--- [Win] IPv4 interfaces by metric ---"
  $TO powershell.exe -NoProfile -Command \
    "Get-NetIPInterface -AddressFamily IPv4 | Sort-Object InterfaceMetric | Format-Table ifIndex,InterfaceAlias,InterfaceMetric,NlMtu,ConnectionState -AutoSize" 2>/dev/null | tr -d '\r'
  echo "--- [Win] default routes (who owns egress) ---"
  $TO powershell.exe -NoProfile -Command \
    "Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' | Format-Table ifIndex,NextHop,RouteMetric,InterfaceAlias -AutoSize" 2>/dev/null | tr -d '\r'
  echo "--- [Win] per-interface DNS servers (corp resolver appears when VPN up) ---"
  $TO powershell.exe -NoProfile -Command \
    "Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object {\$_.ServerAddresses} | Select-Object InterfaceAlias,@{n='DNS';e={\$_.ServerAddresses -join ','}} | Format-Table -AutoSize" 2>/dev/null | tr -d '\r'
  echo "--- [WSL] ip -brief addr / route / eth0 mtu ---"
  ip -brief addr 2>&1; ip route 2>&1; ip link show eth0 2>/dev/null | grep -o 'mtu [0-9]*'
  echo "--- [WSL] resolv.conf ---"
  cat /etc/resolv.conf 2>&1
  echo "--- [WSL] probes (IP egress vs DNS vs corp-HTTP) ---"
  $TO ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 && echo "ping 8.8.8.8 : OK" || echo "ping 8.8.8.8 : FAIL"
  $TO getent hosts github.com >/dev/null 2>&1 && echo "DNS github.com : OK" || echo "DNS github.com : FAIL"
  code=$($TO curl -s -o /dev/null -w '%{http_code}' "https://$CORP_HOST" 2>/dev/null)
  echo "corp https $CORP_HOST : HTTP ${code:-000} (403=VPN-not-effective, 200/302=VPN-OK)"
  echo
}

echo "Capturing to $LOG every ${INTERVAL}s. Ctrl-C to stop."
echo "Log started $(date +%Y-%m-%d\ %H:%M:%S\ %Z)" > "$LOG"
trap 'echo; echo "Stopped. Tell Claude: capture done ($LOG)"; exit 0' INT
while true; do
  snap >> "$LOG" 2>&1
  gp=$($TO powershell.exe -NoProfile -Command "Get-NetAdapter | Where-Object {\$_.InterfaceDescription -match 'PANGP'} | Select-Object -ExpandProperty Status" 2>/dev/null | tr -d '\r ')
  png=$($TO ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 && echo OK || echo FAIL)
  dns=$($TO getent hosts github.com >/dev/null 2>&1 && echo OK || echo FAIL)
  code=$($TO curl -s -o /dev/null -w '%{http_code}' "https://$CORP_HOST" 2>/dev/null)
  case "$code" in 200|301|302) corp="VPN-OK($code)";; 403) corp="VPN-NO($code)";; *) corp="UNREACH(${code:-000})";; esac
  echo "$(date +%H:%M:%S)  VPN=${gp:-?}  ping8.8.8.8=${png}  DNS=${dns}  corp=${corp}"
  sleep "$INTERVAL"
done
