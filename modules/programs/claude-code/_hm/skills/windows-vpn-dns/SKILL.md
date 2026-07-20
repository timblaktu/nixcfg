---
name: windows-vpn-dns
description: Diagnose and fix the GlobalProtect / PANGP split-tunnel DNS race, where DNS name resolution intermittently fails while the VPN is connected - in Windows browsers/apps AND inside WSL (which inherits the race via dnsTunneling). Use when name lookups flap but `ping <IP>` works while the VPN is up, when corporate/internal or even public names intermittently fail, or when the Claude Code CLI itself hangs on the VPN because it cannot resolve api.anthropic.com. Covers both admin and no-admin fixes.
---

# Windows VPN DNS Fix (WSL-adjacent)

Fixes the recurring situation on the user's corporate WSL host (`pa161878-nixos`,
GlobalProtect / PANGP VPN): **DNS name resolution intermittently fails while the VPN
is connected** — in native Windows apps *and* inside WSL (which inherits the race via
`dnsTunneling`), while raw-IP connectivity (`ping <IP>`) keeps working.

## Symptom recognition (when to reach for this)

- Name resolution flaps while the VPN is up: the same lookup fails, then succeeds,
  then fails — in Windows browsers/apps AND inside WSL (`getent hosts github.com`
  intermittently FAILs), while `ping <IP>` by raw address stays reliable.
- Corporate/internal sites (e.g. `*.mascorp.com`, `git.panasonic.aero`) or even
  public sites (`github.com`) intermittently fail to resolve.
- The Claude Code CLI (running inside WSL) hangs for minutes on the VPN — it is
  failing to resolve `api.anthropic.com` during a flap.
- The VPN (GlobalProtect, adapter "PANGP Virtual Ethernet Adapter") is connected.
- Quick triage: `ping 8.8.8.8` OK but name lookups flaky ⇒ this DNS race. If
  `ping 8.8.8.8` itself FAILs ⇒ route starvation instead (different fix).

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

**WSL is NOT immune (correction, verified 2026-07-19).** An earlier version of this
skill claimed `dnsTunneling=true` made WSL immune. That is **wrong**. `dnsTunneling`
answers WSL lookups by forwarding them to the **Windows host resolver** — the very
component that runs the smart multi-homed race — so WSL *inherits* the race. A live
capture on `pa161878-nixos` (WSL 2.7.10, Win 11 24H2 build 26100) showed public-name
resolution (`getent hosts github.com`) intermittently FAILing *inside WSL* while the
VPN was up, even though `ping 8.8.8.8` by IP stayed up the whole time — the classic
DNS-race signature: **name resolution flaps, raw IP egress is fine.** This is exactly
what wedges the Claude Code CLI (which runs *inside* WSL): it cannot resolve
`api.anthropic.com`, so the whole session hangs until the flap clears.

## NOT the cause (rule these out; don't chase them)

- **The nixcfg `mss-clamp` / MTU change is Linux-only.** It sets an `iptables`
  mangle MSS clamp + `eth0` MTU inside WSL. It has no code path to the Windows
  resolver, VPN adapter, or NRPT. It cannot change Windows name resolution.
- **The Windows VPN adapter MTU is already correct (1400 = tunnel MTU).** So there
  is no oversized-packet blackhole on the Windows side. Confirm with
  `Get-NetIPInterface` if in doubt, but this is a red herring.
- The timing correlation ("started since the MTU fix") is **observational**: the
  MTU / `mss-clamp` change (a separate throughput fix for the hotspot MTU
  black-hole) does not touch DNS at all. The DNS race is an independent,
  pre-existing failure mode that affects both Windows apps AND WSL (via
  dnsTunneling — see correction above). Correlation, not causation.

## Two distinct VPN failure modes — don't conflate them

"WSL networking is flaky on the VPN" is really **two** independent mechanisms:

| Mode | Signature | Fix |
|------|-----------|-----|
| **DNS race** (this skill) | name lookups flap; `ping <IP>` fine; corp+public names both affected while VPN up | disable smart resolution (admin) OR WSL-side split-DNS (no admin) OR NRPT (IT) |
| **Route starvation** | `ping <IP>` itself FAILs; full-tunnel GP hijacks all routes / blocks the WSL NAT subnet | host-route self-healer, or GP split-tunnel Exclude of the WSL subnet (admin/IT) |

Confirm which you have with the capture script (below): if `ping 8.8.8.8` stays OK
but `DNS=FAIL` flaps, it's the **race**; if `ping 8.8.8.8` itself FAILs, it's
**route starvation** (see the `mss-clamp` module header and the deep-research notes
for the route fix). The 2026-07-19 capture on this host was overwhelmingly the race,
with only a single self-healing route blip.

## Diagnose

Run the bundled diagnostic from WSL (calls Windows `.exe`s directly, read-only):

```bash
bash "$CLAUDE_SKILL_DIR/diagnose.sh"    # or the skill's diagnose.sh path
```

It reports: WSL `/etc/resolv.conf`, a ping-vs-DNS-vs-corp-HTTP flap check, per-interface
Windows DNS servers + metrics, whether NRPT is empty, whether smart resolution is
enabled, per-resolver `nslookup` of a corporate name, and interface MTUs — then
prints a verdict.

## Capture a VPN transition (when the outage kills Claude itself)

Because Claude Code runs *inside* WSL, a real outage hangs the CLI — you cannot
diagnose it from within Claude. Use the bundled `capture.sh` from a **plain WSL
terminal** (independent of Claude): it samples WSL + Windows state every few seconds
across a connect/disconnect, writing a timestamped log that needs no network and no
Claude. Reproduce the transition, Ctrl-C, then have Claude read the log afterward.

```bash
bash "$CLAUDE_SKILL_DIR/capture.sh"     # heartbeat: VPN=  ping8.8.8.8=  DNS=  corp=
```

The heartbeat disambiguates the two failure modes live: `ping8.8.8.8=OK DNS=FAIL` ⇒
the **DNS race**; `ping8.8.8.8=FAIL` ⇒ **route starvation**. The corp column uses an
HTTP-status probe of `git.panasonic.aero` (403 without the tunnel, 200/302 with) —
a better VPN discriminator than DNS or TCP, since that host is publicly reachable.

## Fix WITHOUT admin (WSL-side — preferred when you cannot elevate)

The registry fix and NRPT rules both need Administrator, which a locked-down corp
laptop may deny (a request to IT takes time). Since the race lives in the *Windows*
resolver that `dnsTunneling` forwards to, you can sidestep it entirely from *inside
WSL*, where you have root. Two approaches, easiest first:

**Option A′ — disable dnsTunneling (one line, test this first).** `%USERPROFILE%\.wslconfig`
is user-writable (no admin). Set:

```ini
[wsl2]
dnsTunneling=false
```

Then `wsl --shutdown` and restart. WSL now populates `/etc/resolv.conf` with the
actual Windows per-interface DNS servers and queries them **sequentially in interface
metric order (VPN adapter is metric 1, so first)** instead of the parallel Windows
race. On 24H2 this often resolves the flap. Trade-off: this is the pre-22H2 behavior,
so verify it survives VPN connect/disconnect with the capture script before relying
on it. Revert by removing the line (or `dnsTunneling=true`) + `wsl --shutdown`.

**Option B — WSL-side split-DNS resolver (declarative, most robust).** Run a local
resolver inside WSL and route corp suffixes to the corp DNS server, everything else
to a public resolver — bypassing the Windows resolver (and its race) completely.
Needs the corp DNS server IP, which you can only read while the VPN is up:

```bash
# with VPN connected, from WSL:
powershell.exe -NoProfile -Command \
  "Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object {\$_.InterfaceAlias -match 'PANGP|Ethernet 6'} | Select-Object -Expand ServerAddresses"
```

On NixOS-WSL (managed in `nixcfg-work`), wire that IP into `dnsmasq` and stop WSL
from generating resolv.conf:

```nix
# /etc/wsl.conf: [network] generateResolvConf=false   (and .wslconfig dnsTunneling=false)
services.dnsmasq.enable = true;
services.dnsmasq.settings = {
  no-resolv = true;
  server = [ "/mascorp.com/CORP_DNS_IP" "/panasonic.aero/CORP_DNS_IP" "1.1.1.1" "9.9.9.9" ];
};
# point /etc/resolv.conf at 127.0.0.1 (dnsmasq)
```

VPN up → corp names go to the corp resolver over the tunnel, public names to
1.1.1.1; VPN down → corp names fail (they need the VPN anyway), public still works.
No Windows resolver in the path → no race. (If corp policy blocks external DNS while
on the VPN, make the default upstream `CORP_DNS_IP` too.)

**Option C (parallel track) — ask IT** to push NRPT split-DNS on the GlobalProtect
portal (map corp suffixes to the VPN resolver). Cleanest upstream fix; removes the
race at the source for both Windows and WSL. Slow because it needs an admin/IT change.

## Fix WITH admin (registry — one-time machine policy)

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
