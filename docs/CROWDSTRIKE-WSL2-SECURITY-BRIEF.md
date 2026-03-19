# CrowdStrike Falcon and WSL2: Security Architecture Brief

**Audience**: IT Security / Endpoint Protection team
**Version**: 1.0 (2026-03-18)
**Purpose**: Technical brief for evaluating CrowdStrike coverage of WSL2 environments

---

## Executive Summary

Windows Subsystem for Linux 2 (WSL2) runs a Microsoft-provided Linux kernel inside a
lightweight Hyper-V virtual machine. This kernel (`microsoft-standard-WSL2`) is **not on
CrowdStrike's supported kernel whitelist**, which means the Falcon Linux sensor enters
**Reduced Functionality Mode (RFM)** when installed inside a WSL2 distribution. In RFM,
the sensor sends heartbeats only — no behavioral detection, no real-time file scanning,
no prevention.

This is not a bug or misconfiguration. It is by design.

CrowdStrike's recommended solution is the **Windows-side Falcon WSL2 Visibility plugin**
(GA since Falcon sensor 7.26, June 2025), which monitors WSL2 processes, file activity,
and network connections from the Windows host without requiring any agent inside the
Linux distribution. This plugin, combined with Intune/MDM hardening policies and an
optional in-distribution Linux sensor for compliance inventory, forms a three-layer
security architecture that provides effective WSL2 coverage.

Our NixOS-WSL distribution includes a CrowdStrike Falcon sensor module that can be
enabled for compliance inventory purposes. This document explains the architecture,
our recommendation, and what we need from IT to proceed.

---

## The Problem: WSL2 as a Security Blind Spot

### Evidence

In a 2023 penetration test published by security researcher Daniel Happe, WSL2 was
demonstrated as a complete blind spot for endpoint detection. The tester installed Kali
Linux inside WSL2 and used standard offensive tools — Chisel for tunneling, BloodHound
for Active Directory reconnaissance, nmap for network scanning — all undetected by the
host's endpoint protection. No alerts were generated in any security console.

This is not unique to CrowdStrike. The underlying issue is architectural.

### Why WSL2 Is Different

WSL2 runs a real Linux kernel inside a Hyper-V utility VM:

- The kernel is **Microsoft-built and signed** (`microsoft-standard-WSL2`). Users cannot
  replace it with a custom kernel in managed environments (Intune can enforce this).
- The VM has its own PID namespace, filesystem, and network stack — separate from the
  Windows host.
- Windows-side EDR agents (Falcon, Defender, etc.) monitor the Windows kernel. They
  have no visibility into the Linux kernel running inside the Hyper-V VM unless
  specifically designed to bridge that boundary.

### CrowdStrike's Kernel Whitelist Model

The Falcon Linux sensor validates the running kernel against CrowdStrike's supported
kernel list during startup. If the kernel is not on the whitelist, the sensor enters
Reduced Functionality Mode rather than risk instability on an untested kernel.

Key facts:

- The `microsoft-standard-WSL2` kernel is not on the whitelist and will not be added.
  CrowdStrike explicitly excludes custom-compiled and non-distribution kernels.
- Using the BPF backend (instead of the kernel module backend) does **not** bypass the
  kernel identity check. RFM is triggered regardless of backend selection.
- NixOS-WSL does not build its own kernel — it uses the Microsoft-provided kernel directly
  (`boot.kernel.enable = false` in NixOS-WSL configuration). There is no path to compiling
  a whitelisted kernel for WSL2.

---

## Recommended Architecture: Three Layers

We recommend a three-layer approach where each layer addresses a different aspect of
WSL2 security:

### Layer 1: Windows Falcon WSL2 Visibility Plugin (Detection)

**What it does**: The Windows-side Falcon sensor (7.26+) includes a WSL2 plugin that
monitors all WSL2 distributions on the host from the Windows side. It provides:

- **Process visibility**: Detects process creation, command-line arguments, and parent
  process chains inside WSL2.
- **Behavioral detection**: CrowdStrike's behavioral IOA (Indicators of Attack) engine
  analyzes WSL2 activity using the same detection rules as native Windows processes.
- **File activity monitoring**: Detects file creation, modification, and access within
  WSL2 filesystems.
- **Network telemetry**: Monitors network connections originating from WSL2.

**Known limitation**: CrowdStrike's ML/NGAV (Next-Generation Antivirus) static analysis
engine does not analyze ELF (Linux) binaries. Behavioral detection still catches malicious
activity at execution time, but dormant ELF malware on disk is not flagged by static scan.

**How to enable**: The WSL2 plugin is controlled via a toggle in the Falcon prevention
policy configuration. No software installation is needed inside the WSL2 distribution.

**Requirement**: Windows Falcon sensor version 7.26 or later must be deployed on developer
workstations.

### Layer 2: Intune/MDM Hardening (Attack Surface Reduction)

**What it does**: Microsoft Intune provides WSL-specific policies that reduce the attack
surface available to users within WSL2:

| Policy | Effect |
|--------|--------|
| Block custom kernels | Prevents users from replacing the Microsoft kernel with an unmonitored custom kernel |
| Block debug shell | Prevents access to the WSL2 init debug shell |
| Block disk mount | Prevents `wsl --mount` of raw disks into WSL2 |
| Control WSL access | Per-user enable/disable of WSL2 functionality |
| Block nested virtualization | Prevents running VMs inside WSL2 |

**Why this matters**: Even with the Falcon plugin providing detection, hardening reduces
the set of actions an attacker (or careless user) can take. Blocking custom kernels is
particularly important — a custom kernel could bypass both the Falcon plugin's monitoring
and any in-distribution sensor.

### Layer 3: Linux Sensor in WSL2 (Compliance Inventory)

**What it does**: Installing the Falcon Linux sensor inside the WSL2 distribution causes
it to enter RFM, where it:

- Sends periodic heartbeats to the Falcon cloud.
- Registers the host in the Falcon console with a unique Agent ID (AID).
- Reports basic host metadata (OS, kernel version, sensor version).
- Accepts grouping tags for asset management.

**What it does NOT do** (in RFM):

- No behavioral detection or IOA analysis.
- No real-time file scanning.
- No prevention or quarantine.
- No network monitoring.
- No vulnerability assessment.

**When to use**: Only if your compliance framework requires that every Linux environment
have a registered Falcon agent, regardless of detection capability. This is a policy
question, not a technical one — the Windows plugin (Layer 1) provides the actual detection.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Windows Host                                │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  CrowdStrike Falcon Sensor (Windows, v7.26+)            │   │
│  │  ┌────────────────────────────────┐                      │   │
│  │  │  WSL2 Visibility Plugin        │  ◄── Layer 1         │   │
│  │  │  (behavioral detection,        │      (Detection)     │   │
│  │  │   process/file/net telemetry)  │                      │   │
│  │  └────────────┬───────────────────┘                      │   │
│  └───────────────┼──────────────────────────────────────────┘   │
│                  │ monitors                                     │
│  ┌───────────────▼──────────────────────────────────────────┐   │
│  │  Intune/MDM Policies                  ◄── Layer 2        │   │
│  │  (block custom kernels, debug shell,      (Hardening)    │   │
│  │   disk mount, nested virtualization)                      │   │
│  └───────────────┬──────────────────────────────────────────┘   │
│                  │ constrains                                   │
│  ┌───────────────▼──────────────────────────────────────────┐   │
│  │  Hyper-V Utility VM                                      │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  WSL2 Distribution (NixOS-WSL)                     │  │   │
│  │  │                                                    │  │   │
│  │  │  ┌──────────────────────────────┐                  │  │   │
│  │  │  │ Falcon Linux Sensor (RFM)   │  ◄── Layer 3     │  │   │
│  │  │  │ (heartbeats only,           │      (Inventory)  │  │   │
│  │  │  │  compliance inventory)      │      [Optional]   │  │   │
│  │  │  └──────────────────────────────┘                  │  │   │
│  │  │                                                    │  │   │
│  │  │  microsoft-standard-WSL2 kernel (not whitelisted)  │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Decision Matrix

| Scenario | Layer 1 (Plugin) | Layer 2 (Intune) | Layer 3 (Sensor) | Notes |
|----------|:---:|:---:|:---:|-------|
| Standard developer workstation | Yes | Yes | No | Plugin provides detection; sensor adds no value |
| Compliance requires agent in every Linux env | Yes | Yes | Yes | Sensor provides inventory presence only |
| Air-gapped / no Windows Falcon | N/A | Yes | Yes | Only option; sensor is in RFM (heartbeats only) |
| Dual-EDR (CrowdStrike + Defender) | Yes | Yes | Optional | Consider MDE WSL plugin as additional layer |
| High-security environment | Yes | Yes | Yes | Defense in depth; all three layers |

---

## What We Need From IT

To proceed with deploying the WSL2 security architecture, we need the following from
the IT security team:

### Windows Falcon Plugin (Layer 1)

- [ ] **Falcon sensor version on developer workstations**: Is 7.26+ deployed? (Required
  for the WSL2 Visibility plugin.)
- [ ] **WSL2 plugin status**: Is the WSL2 Visibility toggle enabled in the prevention
  policy for developer workstation groups?
- [ ] **If not yet enabled**: Timeline for deploying sensor 7.26+ and enabling the plugin.

### Intune/MDM Hardening (Layer 2)

- [ ] **Current WSL Intune policies**: Which WSL-specific policies are currently active?
  (Custom kernel blocking, debug shell, disk mount, per-user access control.)
- [ ] **Policy gaps**: Are there WSL hardening policies we should request?

### Linux Sensor in WSL2 (Layer 3, if required)

- [ ] **Compliance requirement**: Does your compliance framework require a registered
  Falcon agent inside every Linux environment, even when detection is provided by the
  Windows plugin? (This determines whether we enable the Linux sensor.)
- [ ] **CrowdStrike Customer ID (CID)**: Format is `<hex>-<checksum>` (e.g.,
  `A1B2C3D4E5F6-12`). Not secret — can be embedded in the distribution image.
- [ ] **Provisioning token**: Required for host registration. Should be delivered via
  secret management (not embedded in the image).
- [ ] **Cloud region**: Which Falcon cloud? (us-1, us-2, eu-1, us-gov-1, us-gov-2)
- [ ] **Sensor package distribution**: How should we obtain the `.deb` installer?
  Options: Falcon console download, corporate artifact server, shared network path.
- [ ] **Tag conventions**: What tag format does the team use for asset grouping?
  (e.g., `Environment/Development`, `Team/Engineering`, `Platform/WSL2`)
- [ ] **Auto-update policy**: Should the sensor auto-update after initial installation,
  or should we pin to a specific version?

### Additional Context

- [ ] **Microsoft Defender for Endpoint (MDE)**: If the organization uses MDE alongside
  or instead of CrowdStrike, is the MDE WSL plugin (GA since May 2024) deployed?
  MDE provides parallel WSL2 visibility capabilities.
- [ ] **Audit/compliance contacts**: Who should we coordinate with for endpoint
  compliance validation after deployment?

---

## Our Module Capabilities

Our NixOS-WSL distribution includes a CrowdStrike Falcon sensor module with the
following capabilities. These are described here in plain language; the technical
implementation details are in the module's developer documentation.

### Sensor Installation and Configuration

- **Automated deployment**: The sensor is installed and configured as part of the
  system build process. No manual installation steps required after importing the
  WSL distribution.
- **Configuration options**: CID, provisioning token, cloud region, sensor backend
  (BPF recommended), grouping tags, proxy settings, and log verbosity are all
  configurable.
- **Secret management**: CID and provisioning token can be provided via encrypted
  secret files (compatible with enterprise secret management systems like SOPS or
  HashiCorp Vault), avoiding plaintext credentials in configuration.

### Golden Image Support

- **Unique Agent IDs**: Each imported copy of the distribution automatically receives
  a unique Agent ID (AID) on first start, preventing console confusion from cloned
  instances sharing the same AID.
- **CID baked in, token at runtime**: The CID (which is not secret) is embedded in the
  distribution image. The provisioning token is provided at first boot via secret
  management, allowing the same image to be distributed to multiple users.

### WSL2 Awareness

- **RFM acknowledgment**: The module includes a safety check that warns administrators
  when the sensor is enabled on WSL2, explaining that it will operate in Reduced
  Functionality Mode. This prevents accidental deployment under the assumption of
  full detection capability.
- **BPF backend default**: The module defaults to the BPF backend, which is the
  recommended backend for NixOS environments. (Note: BPF does not prevent RFM on
  WSL2 — it is recommended for compatibility reasons unrelated to the WSL2 limitation.)

### Integration with Distribution Layers

The sensor module integrates with our distribution's layered architecture:

- **Enterprise layer**: Sets organization-wide defaults (backend, tags, disabled by
  default pending IT credentials).
- **Team layer**: Teams can enable the sensor and apply team-specific tags.
- **Host layer**: Individual machines can override settings as needed.

---

## References

### CrowdStrike Documentation

- [Falcon Sensor for Linux Deployment Guide](https://falcon.crowdstrike.com/documentation/20/falcon-sensor-for-linux) —
  Installation, configuration, and supported kernels
- [Falcon Sensor Release Notes](https://falcon.crowdstrike.com/documentation/release-notes) —
  Version 7.26 WSL2 plugin GA announcement
- [Reduced Functionality Mode (RFM)](https://falcon.crowdstrike.com/documentation/20/falcon-sensor-for-linux#reduced-functionality-mode) —
  What RFM means and how to verify
- [WSL2 Visibility Plugin](https://falcon.crowdstrike.com/documentation/146/falcon-for-wsl2) —
  Plugin enablement and capabilities

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
