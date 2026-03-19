# CrowdStrike Falcon Sensor on WSL2: Technical Reference

## Summary

The Falcon Linux sensor enters **Reduced Functionality Mode (RFM)** on WSL2 because the
`microsoft-standard-WSL2` kernel is not on CrowdStrike's supported kernel whitelist. In
RFM, the sensor provides heartbeats and compliance inventory only — no detection, no
prevention. The recommended detection mechanism is the **Windows-side Falcon WSL2
Visibility plugin** (GA since sensor 7.26, June 2025), which monitors WSL2 from the
host. See [CROWDSTRIKE-WSL2-SECURITY-BRIEF.md](../../../docs/CROWDSTRIKE-WSL2-SECURITY-BRIEF.md)
for the full architecture recommendation and IT checklist.

---

## Why the Sensor Enters RFM on WSL2

The Falcon Linux sensor validates the running kernel against CrowdStrike's supported
kernel list at startup. If the kernel is not whitelisted, the sensor enters Reduced
Functionality Mode rather than risk instability on an untested kernel.

Three factors make RFM unavoidable on WSL2:

1. **Kernel not whitelisted**: The `microsoft-standard-WSL2` kernel is not on the
   whitelist and will not be added. CrowdStrike explicitly excludes custom-compiled
   and non-distribution kernels.

2. **BPF backend does not bypass the check**: The kernel identity check triggers RFM
   regardless of whether the sensor uses the `bpf` or `kernel` backend. Switching
   backends does not change RFM behavior.

3. **NixOS-WSL cannot build a custom kernel**: NixOS-WSL sets `boot.kernel.enable = false`
   and uses the Microsoft-provided kernel directly. There is no path to compiling a
   whitelisted kernel for WSL2.

### Context: WSL2 as a Security Blind Spot

In a 2023 penetration test published by security researcher Daniel Happe, WSL2 was
demonstrated as a complete blind spot for endpoint detection. The tester installed Kali
Linux inside WSL2 and used standard offensive tools (Chisel, BloodHound, nmap) — all
undetected by the host's endpoint protection. This is not unique to CrowdStrike; the
underlying issue is architectural. WSL2 runs a real Linux kernel inside a Hyper-V
utility VM with its own PID namespace, filesystem, and network stack, invisible to
Windows-side EDR agents unless they have a specific WSL2 integration.

---

## What RFM Provides and Does Not Provide

| Capability | RFM Status |
|------------|:----------:|
| Heartbeats to Falcon cloud | Yes |
| Host registration (unique AID) | Yes |
| Console visibility (host appears as managed) | Yes |
| Basic host metadata reporting (OS, kernel, sensor version) | Yes |
| Grouping tag support | Yes |
| Behavioral detection (IOA) | No |
| Real-time file scanning | No |
| Prevention / quarantine | No |
| Network monitoring | No |
| Vulnerability assessment | No |
| ML/NGAV static analysis | No |

---

## Verifying RFM Status

### Inside the WSL2 Distribution

```bash
# Check sensor state
sudo /opt/CrowdStrike/falconctl -g --rfm-state --version --aid

# Expected output on WSL2:
# rfm-state=true
# version=7.x.x
# aid=<unique-agent-id>
```

If `rfm-state=false`, the sensor believes it is on a supported kernel — investigate
whether a custom kernel is in use or the sensor version predates the whitelist check.

### In the Falcon Console

- The host should appear in **Host Management** with the reported AID.
- The **Sensor Health** column may show "Reduced Functionality" or a warning indicator.
- If the host does not appear, check network connectivity (the sensor needs outbound
  HTTPS to the Falcon cloud).

### Confirming Windows Plugin Coverage

To verify the Windows-side plugin is providing detection for your WSL2 distributions:

1. Check the Windows Falcon sensor version: `"C:\Program Files\CrowdStrike\CSFalconService.exe" /version` — must be 7.26+.
2. In the Falcon console, check the **Prevention Policy** for the host — the WSL2
   Visibility toggle should be enabled.
3. Run a test detection inside WSL2 (e.g., a CrowdStrike detection test command) and
   verify an alert appears in the console attributed to the Windows host.

---

## Recommended Architecture

We recommend a three-layer approach. For the full architecture diagram, decision matrix,
and IT checklist, see
[CROWDSTRIKE-WSL2-SECURITY-BRIEF.md](../../../docs/CROWDSTRIKE-WSL2-SECURITY-BRIEF.md).

| Layer | Component | Purpose |
|:-----:|-----------|---------|
| 1 | Windows Falcon WSL2 Visibility Plugin | Detection (behavioral, file, network) |
| 2 | Intune/MDM WSL Hardening | Attack surface reduction |
| 3 | Linux Sensor in WSL2 (this module) | Compliance inventory (optional) |

Layer 1 provides the actual detection capability. Layer 3 (this module) is only needed
if compliance requires a registered Falcon agent inside every Linux environment.

---

## Windows Falcon WSL2 Visibility Plugin

**Version requirement**: Windows Falcon sensor 7.26+ (GA June 2025).

**Enablement**: Controlled via a toggle in the Falcon prevention policy configuration.
No software installation is needed inside the WSL2 distribution.

**Capabilities**:

- Process visibility: detects process creation, command-line arguments, parent process
  chains inside WSL2.
- Behavioral detection: CrowdStrike's IOA engine analyzes WSL2 activity using the same
  detection rules as native Windows processes.
- File activity monitoring: detects file creation, modification, and access within WSL2
  filesystems.
- Network telemetry: monitors network connections originating from WSL2.
- Covers all WSL2 distributions on the host simultaneously.

**Known limitation**: CrowdStrike's ML/NGAV static analysis engine does not analyze ELF
(Linux) binaries. Behavioral detection still catches malicious activity at execution
time, but dormant ELF malware on disk is not flagged by static scan.

---

## Intune/MDM Hardening

Microsoft Intune provides WSL-specific policies that reduce the attack surface. These
should be enabled regardless of which Falcon layers are active.

| Policy | Effect |
|--------|--------|
| Block custom kernels | Prevents replacing the Microsoft kernel with an unmonitored custom kernel |
| Block debug shell | Prevents access to the WSL2 init debug shell |
| Block disk mount | Prevents `wsl --mount` of raw disks into WSL2 |
| Control WSL access | Per-user enable/disable of WSL2 functionality |
| Block nested virtualization | Prevents running VMs inside WSL2 |

**Why custom kernel blocking matters**: A custom kernel could bypass both the Falcon
plugin's monitoring and any in-distribution sensor. This is the single most important
hardening policy for WSL2 security.

---

## MDE WSL Plugin

If the organization uses Microsoft Defender for Endpoint (MDE) alongside or instead of
CrowdStrike, MDE offers a parallel WSL2 visibility solution:

- **GA**: May 2024
- **Capabilities**: Similar to the CrowdStrike plugin — process, file, and network
  monitoring from the Windows side
- **Enablement**: MDE plugin for WSL2, configured via Microsoft Defender portal

In dual-EDR environments (CrowdStrike + Defender), both plugins can run simultaneously
for defense in depth. Coordinate with IT to determine which EDR platform is primary for
WSL2 coverage.

---

## Golden Image Considerations

When building distributable WSL images (tarballs) with the Falcon sensor baked in:

1. **Set `autoRemoveAid = true`**: Each imported instance needs a unique Agent ID (AID).
   Without this, cloned instances share the same AID, causing console confusion where
   multiple hosts appear as a single entry.

2. **CID baked in, token at runtime**: The Customer ID (CID) is not secret and can be
   baked into the image. The provisioning token should be provided at first boot via
   SOPS secret or environment-specific configuration, allowing the same image to be
   distributed to multiple users.

3. **Sensor version pinning**: Pin the `.deb` version in the Nix derivation. Sensor
   auto-updates are handled by the Falcon cloud after registration, but the initial
   version should be tested with your environment.

4. **Tag conventions**: Apply grouping tags at build time to ensure hosts register in
   the correct asset groups. Coordinate tag format with IT (e.g.,
   `Environment/Development`, `Team/Engineering`, `Platform/WSL2`).

---

## NixOS-Specific Notes

- The sensor runs inside a `buildFHSEnv` wrapper because it expects FHS paths
  (`/opt/CrowdStrike`, standard library locations) that NixOS does not provide natively.
- The `/opt/CrowdStrike` directory is created as a mutable tmpfiles directory (not in
  the Nix store) because the sensor writes runtime state (AID, channel files) there.
- `backend = "bpf"` is recommended over `"kernel"` for NixOS, as the BPF backend has
  looser kernel requirements than the kernel module backend. Note: BPF does **not**
  prevent RFM on WSL2 — it is recommended for compatibility reasons unrelated to the
  WSL2 limitation.

---

## When to Enable the Linux Sensor

Use this decision guide to determine whether to enable the Falcon sensor module in your
WSL2 configuration:

**Enable the sensor** if:

- Compliance framework requires a registered Falcon agent in every Linux environment,
  regardless of detection capability.
- Air-gapped environment where the Windows Falcon plugin is not available.
- Organization policy requires defense-in-depth with all three layers active.

**Do not enable the sensor** if:

- The Windows Falcon plugin (Layer 1) is deployed and compliance does not require
  in-distribution agent presence.
- You want to minimize WSL2 resource usage (the sensor consumes memory and CPU even
  in RFM).

When enabling, always set `acknowledgeWslRfm = true` to confirm you understand the
sensor operates in RFM on WSL2. The module will emit a build-time warning if this
acknowledgment is missing.

---

## Troubleshooting

### Sensor does not start

1. Check the FHS wrapper is functioning: `systemctl status falcon-sensor`.
2. Verify `/opt/CrowdStrike` exists and is writable (created by tmpfiles).
3. Check sensor logs: `journalctl -u falcon-sensor -e`.
4. Ensure the `.deb` package was extracted correctly during the Nix build.

### No heartbeats in Falcon console

1. Confirm the sensor is running: `ps aux | grep falcon`.
2. Verify network connectivity to the Falcon cloud (outbound HTTPS on port 443).
3. Check CID is correctly configured: `sudo /opt/CrowdStrike/falconctl -g --cid`.
4. If using a provisioning token, verify it was provided correctly.
5. Check proxy settings if the host requires a proxy for outbound connections.

### AID conflicts (multiple hosts sharing same AID)

This occurs when a golden image is imported multiple times without AID removal:

1. Enable `autoRemoveAid = true` in the module configuration.
2. For existing conflicts: stop the sensor, delete `/opt/CrowdStrike/falconctl.conf`,
   and restart — the sensor will generate a new AID.
3. Remove duplicate entries from the Falcon console manually.

### Sensor reports RFM but you expected full functionality

This is expected on WSL2. The `microsoft-standard-WSL2` kernel is not whitelisted.
If you see RFM on a non-WSL NixOS system, verify the kernel version is on
CrowdStrike's supported list for your sensor version.

### Windows plugin not detecting WSL2 activity

1. Verify Windows Falcon sensor version is 7.26+.
2. Check the prevention policy has the WSL2 Visibility toggle enabled.
3. Confirm WSL2 distributions are running (not in WSL1 mode).
4. Restart the Falcon service on Windows: `sc stop CSFalconService && sc start CSFalconService` (admin PowerShell).

---

## References

### CrowdStrike Documentation

- [Falcon Sensor for Linux Deployment Guide](https://falcon.crowdstrike.com/documentation/20/falcon-sensor-for-linux) —
  Installation, configuration, and supported kernels
- [Reduced Functionality Mode (RFM)](https://falcon.crowdstrike.com/documentation/20/falcon-sensor-for-linux#reduced-functionality-mode) —
  What RFM means and how to verify
- [WSL2 Visibility Plugin](https://falcon.crowdstrike.com/documentation/146/falcon-for-wsl2) —
  Plugin enablement and capabilities (sensor 7.26+)
- [Falcon Sensor Release Notes](https://falcon.crowdstrike.com/documentation/release-notes) —
  Version 7.26 WSL2 plugin GA announcement

### Microsoft Documentation

- [WSL2 Architecture Overview](https://learn.microsoft.com/en-us/windows/wsl/about) —
  Hyper-V VM, kernel, filesystem architecture
- [Intune WSL Settings](https://learn.microsoft.com/en-us/windows/wsl/intune) —
  MDM policies for WSL hardening
- [Microsoft Defender for Endpoint WSL2 Plugin](https://learn.microsoft.com/en-us/defender-endpoint/mde-plugin-wsl) —
  MDE WSL2 monitoring (GA May 2024)

### Security Research

- [Daniel Happe, "WSL2: The Blind Spot in Your EDR" (2023)](https://www.yourcomputergeek.com/blog/wsl2-blind-spot) —
  Penetration test demonstrating WSL2 as unmonitored attack surface

### Related Project Documentation

- [CrowdStrike WSL2 Security Brief](../../../docs/CROWDSTRIKE-WSL2-SECURITY-BRIEF.md) —
  IT-facing architecture recommendation and checklist
