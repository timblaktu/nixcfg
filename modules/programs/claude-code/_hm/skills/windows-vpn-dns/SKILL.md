---
name: windows-vpn-dns
description: Diagnose and fix Windows-host DNS / name resolution failing while WSL resolves fine, when a corporate VPN (GlobalProtect / PANGP) is connected. Use when internet or internal/corporate names work inside WSL but intermittently fail in Windows browsers/apps, when the VPN is up and Windows name resolution is flaky, or for the classic "works in WSL, not in Windows" split-tunnel DNS race.
---

# Windows VPN DNS Fix (WSL-adjacent)

Fixes the recurring situation on the user's corporate WSL host (`pa161878-nixos`,
GlobalProtect / PANGP VPN): **DNS resolves reliably inside WSL but intermittently
fails in native Windows apps** while the VPN is connected.

## Symptom recognition (when to reach for this)

- "DNS isn't working in Windows right now, but it's fine in WSL."
- Corporate/internal sites (e.g. `*.mascorp.com`, `git.panasonic.aero`) or even
  public sites intermittently fail in a Windows browser, yet `curl`/`getent` in
  WSL resolve them every time.
- The VPN (GlobalProtect, adapter "PANGP Virtual Ethernet Adapter") is connected.

## Root cause (the actual mechanism)

Two conditions combine, both on the **Windows** side:

1. **GlobalProtect installs no split-DNS rules.** `Get-DnsClientNrptPolicy` is
   **empty**, so Windows has no policy saying "send corporate suffixes to the VPN
   resolver."
2. **Windows "smart multi-homed name resolution" is ON** (the default). Windows
   fires every lookup at **all** active interfaces' resolvers in parallel:
   - VPN resolver (e.g. `10.170.77.1`) — correct answer, but slower over the tunnel.
   - Wi-Fi/LAN resolver (e.g. `172.20.214.78`) — returns a **fast NXDOMAIN** for
     corporate names.

   The fast negative intermittently wins the race → Windows apps see "can't find".

**WSL is immune** because `dnsTunneling=true` in `%USERPROFILE%\.wslconfig` funnels
WSL lookups through a single deterministic path that returns the positive answer —
so WSL never suffers the interface race.

## NOT the cause (rule these out; don't chase them)

- **The nixcfg `mss-clamp` / MTU change is Linux-only.** It sets an `iptables`
  mangle MSS clamp + `eth0` MTU inside WSL. It has no code path to the Windows
  resolver, VPN adapter, or NRPT. It cannot change Windows name resolution.
- **The Windows VPN adapter MTU is already correct (1400 = tunnel MTU).** So there
  is no oversized-packet blackhole on the Windows side. Confirm with
  `Get-NetIPInterface` if in doubt, but this is a red herring.
- The timing correlation ("started since the MTU fix") is **observational**:
  fixing WSL made it reliable, which exposed the pre-existing Windows race by
  contrast. Correlation, not causation.

## Diagnose

Run the bundled diagnostic from WSL (calls Windows `.exe`s directly, read-only):

```bash
bash "$CLAUDE_SKILL_DIR/diagnose.sh"    # or the skill's diagnose.sh path
```

It reports: WSL `/etc/resolv.conf`, per-interface Windows DNS servers + metrics,
whether NRPT is empty, whether smart resolution is enabled, per-resolver `nslookup`
of a corporate name, and interface MTUs — then prints a verdict.

## Fix

The durable, no-reconnect fix: disable the parallel-resolver race so Windows queries
interfaces in metric order (VPN first), matching WSL's behavior. This is a one-time,
persistent machine policy — survives reboots, VPN reconnects, and GP updates.

**Requires an ELEVATED (Admin) PowerShell.** A WSL-launched shell inherits the
user's standard, non-elevated token, so Claude cannot apply it directly — the HKLM
policy write will be denied. Hand the user the command; do not silently fail.

```powershell
# Run in an elevated PowerShell (Win -> type PowerShell -> Ctrl+Shift+Enter):
$k='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'; New-Item $k -Force | Out-Null; Set-ItemProperty $k DisableSmartNameResolution 1 -Type DWord; Set-ItemProperty $k DisableParallelAandAAAA 1 -Type DWord; ipconfig /flushdns
```

The bundled `fix-dns.ps1` does the same with an elevation self-check and status
output. Put it on the clipboard for the user, or have them run it elevated:

```bash
# Offer the one-liner on the Windows clipboard for pasting into an admin window:
clip.exe < "$CLAUDE_SKILL_DIR/fix-dns.ps1"     # then user pastes into elevated pwsh
```

### If the elevated write is still denied

That means corporate GPO locks the policy hive even for local admins. Then it is an
IT ask: have them push **NRPT split-DNS** on the GlobalProtect portal (map the
corporate DNS suffixes to the VPN resolver). That is the cleaner upstream fix and
removes the race at the source.

### Undo

```powershell
$k='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'; Remove-ItemProperty $k DisableSmartNameResolution,DisableParallelAandAAAA -ErrorAction SilentlyContinue; ipconfig /flushdns
```

## Surgical alternative (instead of disabling globally)

Self-install NRPT rules for the corporate suffixes (also needs elevation):

```powershell
Add-DnsClientNrptRule -Namespace ".mascorp.com" -NameServers "10.170.77.1"
Add-DnsClientNrptRule -Namespace ".panasonic.aero" -NameServers "10.170.77.1"
```

Caveat: GlobalProtect can clobber user-added NRPT rules on each connect, so this is
less durable than the registry toggle. Verify the VPN resolver IP first via
`diagnose.sh` (it can change between gateways).
