# Plan 028: CrowdStrike WSL2 Security Analysis & IT Preparation

**Branch**: `feat/usb-jetson-pa161878`
**Created**: 2026-03-18
**Prerequisite for**: Plan 026 Task 6 (IT Demonstration)

## Context

The CrowdStrike Falcon sensor module (`modules/programs/crowdstrike-falcon/`) was built
as part of Plan 026 to support enterprise endpoint security in distributable NixOS-WSL
images. However, thorough research reveals a fundamental architectural limitation:

**The `microsoft-standard-WSL2` kernel is not on CrowdStrike's supported kernel whitelist
and never will be.** The sensor enters Reduced Functionality Mode (RFM) — heartbeats only,
no detection, no prevention. This is not a bug or misconfiguration; it's by design.

CrowdStrike's actual solution for WSL2 is the **Windows-side Falcon WSL2 Visibility plugin**
(GA since sensor 7.26, June 2025), which monitors WSL2 from the host without requiring
any agent inside the distribution.

Before presenting to IT, we need:
1. An IT-readable technical brief explaining the landscape and our recommendation
2. Complete, accurate module documentation replacing the current incomplete version
3. Module code that warns users about RFM and forces explicit acknowledgment

## Research Summary

| Finding | Detail |
|---------|--------|
| WSL2 kernel on CS whitelist? | No — `microsoft-standard-WSL2` not supported, custom kernels explicitly excluded |
| BPF backend bypasses RFM? | No — kernel identity check still triggers RFM regardless of backend |
| NixOS can build custom kernel? | No — NixOS-WSL sets `boot.kernel.enable = false` |
| Windows Falcon plugin version | 7.26+ (GA June 2025), enabled via prevention policy toggle |
| Plugin capabilities | Process visibility, command-line telemetry, behavioral detection |
| Plugin limitations | ML/NGAV doesn't analyze ELF binaries (static analysis gap) |
| Intune WSL controls | Block custom kernels, debug shell, disk mount; per-user WSL access |
| MDE WSL plugin | GA May 2024, parallel solution if org uses Microsoft Defender |
| 2023 pen-test (Happe) | WSL2 was complete blind spot: Kali, Chisel, BloodHound, nmap undetected |
| Linux sensor value on WSL2 | Compliance inventory only (host appears in Falcon console as managed) |

## Tasks

### Task 1: IT Security Technical Brief

| Field | Value |
|-------|-------|
| Status | `TASK:COMPLETE` |
| Output | `docs/CROWDSTRIKE-WSL2-SECURITY-BRIEF.md` |
| Commit | `37e5773` |
| Audience | IT security team (no Nix knowledge assumed) |

**Objective**: Self-contained document an IT security team member can read independently to
understand the WSL2/CrowdStrike landscape, what we built, and what decisions they need to make.

**Document sections**:

1. **Executive Summary** — WSL2 kernel not whitelisted → sensor enters RFM → Windows plugin
   is the real detection mechanism → our module provides compliance inventory
2. **The Problem: WSL2 as Security Blind Spot** — 2023 pen-test evidence, WSL2 architecture
   (Hyper-V VM, Microsoft kernel), CrowdStrike kernel whitelist model
3. **Recommended Architecture: Three Layers**
   - Layer 1: Windows Falcon WSL2 Visibility Plugin (detection)
   - Layer 2: Intune/MDM Hardening (attack surface reduction)
   - Layer 3: Linux Sensor in WSL2 (compliance inventory, optional)
4. **Architecture Diagram** (ASCII art showing Windows host → WSL2 VM → sensor layers)
5. **Decision Matrix** — scenarios vs recommended approach
6. **What We Need From IT** — checklist:
   - Windows Falcon plugin deployment status (is 7.26+ on hosts?)
   - CID, provisioning token, cloud region
   - Sensor `.deb` distribution method
   - Tag conventions for asset grouping
   - Intune policy status for WSL controls
   - Whether compliance requires Linux sensor presence in WSL
   - MDE WSL plugin status (if dual-EDR)
7. **Our Module Capabilities** — capability descriptions in plain language (no Nix syntax)
8. **References** — CrowdStrike docs, Microsoft docs, pen-test article

**Definition of Done**:
- [x] File exists at `docs/CROWDSTRIKE-WSL2-SECURITY-BRIEF.md`
- [x] Zero Nix syntax in the document
- [x] Document stands alone without needing other files
- [x] Version numbers accurate (7.26 for plugin GA, not 7.23)
- [ ] Committed with descriptive message
- [ ] `nix flake check --no-build` passes

---

### Task 2: Rewrite WSL-LIMITATIONS.md

| Field | Value |
|-------|-------|
| Status | `TASK:COMPLETE` |
| Output | `modules/programs/crowdstrike-falcon/docs/WSL-LIMITATIONS.md` (in-place rewrite) |
| Commit | `12af7d0` |
| Audience | Developers configuring the module + IT staff following cross-references |

**Objective**: Replace the current 69-line incomplete document with comprehensive technical
reference incorporating all research findings.

**Current gaps to fix**:
- Version reference wrong (says v7.23, should be 7.26 for GA)
- No Intune hardening section
- No MDE WSL plugin info
- No 2023 pen-test context
- "When to Use Each Approach" table too simplistic
- No troubleshooting section
- Not cross-referenced with security brief

**New document structure**:

1. **Summary** — 3 sentences: what happens, why, what to do
2. **Why the Sensor Enters RFM on WSL2** — kernel whitelist, BPF doesn't bypass, NixOS
   `boot.kernel.enable = false`
3. **What RFM Provides / Does Not Provide** — explicit capability matrix
4. **Verifying RFM Status** — `falconctl` commands, Falcon console expectations, how to
   confirm Windows plugin is providing coverage
5. **Recommended Architecture** — abbreviated three-layer model, cross-ref to security brief
6. **Windows Falcon WSL2 Visibility Plugin** — version, enablement, capabilities, ELF gap
7. **Intune/MDM Hardening** — new section with policy list
8. **MDE WSL Plugin** — new section for dual-EDR environments
9. **Golden Image Considerations** — keep existing content (autoRemoveAid, CID baking, etc.)
10. **NixOS-Specific Notes** — keep existing content (FHS wrapper, tmpfiles, BPF recommendation)
11. **When to Enable the Linux Sensor** — decision guide for module consumers
12. **Troubleshooting** — sensor won't start, no heartbeats, AID conflicts
13. **References**

**Definition of Done**:
- [ ] File rewritten with all sections above
- [ ] Version corrected to 7.26
- [ ] Cross-reference to `docs/CROWDSTRIKE-WSL2-SECURITY-BRIEF.md`
- [ ] No factual inaccuracies vs research
- [ ] Committed
- [ ] `nix flake check --no-build` passes

---

### Task 3: Module Code Updates & Cross-References

| Field | Value |
|-------|-------|
| Status | `TASK:COMPLETE` |
| Blocked by | Tasks 1 and 2 (cross-references to both documents) |
| Commit | `b79debe` |
| Files modified | See list below |

**Objective**: Update module source code and existing docs to reflect research findings,
add `acknowledgeWslRfm` option, and wire cross-references.

**Changes**:

**A. `modules/programs/crowdstrike-falcon/crowdstrike-falcon.nix`**:

1. Add header comment warning about WSL2 RFM with security brief reference
2. Add new option `services.falcon-sensor.acknowledgeWslRfm` (bool, default false):
   ```
   Whether you acknowledge that on WSL2, the sensor enters Reduced Functionality
   Mode (heartbeats only, no detection). Set to true to suppress the WSL RFM
   warning. See docs/CROWDSTRIKE-WSL2-SECURITY-BRIEF.md.
   ```
3. Add assertion: when `wsl.enable && falcon-sensor.enable && !acknowledgeWslRfm`,
   emit warning message explaining RFM and pointing to the security brief
4. Update `backend` option description to note BPF does not prevent RFM on WSL2
5. Update `enable` option description to mention WSL2 RFM

**B. `modules/system/settings/wsl-enterprise/wsl-enterprise.nix`**:

6. Update CrowdStrike import comment (lines ~69-71) with RFM context and brief reference
7. Update enterprise defaults comment (lines ~241-247) noting compliance-only on WSL2

**C. `docs/DISTRIBUTION.md`**:

8. Update CrowdStrike bullet (~line 212) to reference security brief

**D. `docs/SHARED-MODULES.md`**:

9. Update `crowdstrike-falcon` export description (~line 73) with RFM note and brief reference

**Definition of Done**:
- [ ] New `acknowledgeWslRfm` option works (eval test passes)
- [ ] Assertion fires when `wsl.enable && enable && !acknowledgeWslRfm`
- [ ] Assertion does NOT fire when `acknowledgeWslRfm = true`
- [ ] Assertion does NOT fire on non-WSL systems
- [ ] All comments and option descriptions updated
- [ ] Cross-references to security brief in DISTRIBUTION.md and SHARED-MODULES.md
- [ ] Committed
- [ ] `nix flake check --no-build` passes

---

## Execution Order

```
Task 1 (Security Brief) ─────────────────┐
                                          ├── Task 3 (Code + Cross-refs)
Task 2 (WSL-LIMITATIONS.md rewrite) ─────┘
```

Tasks 1 and 2 are independent. Task 3 depends on both (adds cross-references to both docs).
One task per session.

## Validation

After all three tasks:
- `nix flake check --no-build` passes
- `rg 'acknowledgeWslRfm' modules/` shows the new option and assertion
- `rg '7\.23' modules/programs/crowdstrike-falcon/` returns zero matches (old version removed)
- `rg 'SECURITY-BRIEF' docs/` shows cross-references in DISTRIBUTION.md and SHARED-MODULES.md
- Security brief is readable by someone with zero Nix knowledge
- Plan 026 Task 6 checklist items are covered by the security brief's "What We Need From IT"

## Relationship to Plan 026

Plan 026 Task 6 ("IT Demonstration") is blocked until this plan completes. After Plan 028:
- The security brief (Task 1) can be sent to IT before the meeting
- The updated documentation (Task 2) provides technical backup
- The module code (Task 3) is ready for IT to provide their CID/token/config
- Plan 026 Task 6 becomes: schedule meeting, present brief, collect credentials, configure
