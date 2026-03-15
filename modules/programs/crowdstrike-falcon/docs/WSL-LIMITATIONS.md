# CrowdStrike Falcon Sensor on WSL2: Limitations and Alternatives

## Reduced Functionality Mode (RFM)

WSL2 runs the `microsoft-standard-WSL2` kernel, which is **not** on CrowdStrike's
supported kernel whitelist. When the Falcon sensor detects an unsupported kernel,
it enters **Reduced Functionality Mode (RFM)**:

- **Heartbeats**: Sensor sends heartbeats to the Falcon cloud (visible in console).
- **No detections**: No behavioral analysis, no real-time file scanning, no IOC alerting.
- **Compliance inventory**: The host appears in the Falcon console as managed, satisfying
  asset inventory requirements even without active protection.

### Verifying RFM Status

```bash
sudo /opt/CrowdStrike/falconctl -g --rfm-state --version --aid
```

Expected output on WSL2:
```
rfm-state=true
version=7.x.x
aid=<unique-agent-id>
```

## Recommended Alternative: Windows Falcon Plugin (v7.23+)

CrowdStrike's recommended approach for WSL2 visibility is the **Windows-side Falcon
plugin** (available since Falcon v7.23, June 2025):

- A plugin to the Windows Falcon sensor extends monitoring **into** WSL2 distributions.
- No agent installation required inside the WSL2 distribution.
- Full detection capability (behavioral analysis, file monitoring, network visibility).
- Covers all WSL2 distributions on the host simultaneously.

### When to Use Each Approach

| Scenario | Approach | Why |
|----------|----------|-----|
| Enterprise compliance requires agent presence | Linux sensor (this module) | Satisfies inventory/audit even in RFM |
| Actual threat detection needed in WSL2 | Windows Falcon plugin | Full detection capability |
| Both compliance and detection | Both approaches | Belt and suspenders |
| Air-gapped / no Windows Falcon | Linux sensor (this module) | Only option available |

## Golden Image Considerations

When building distributable WSL images (tarballs) with the Falcon sensor baked in:

1. **Set `autoRemoveAid = true`**: Each imported instance needs a unique Agent ID (AID).
   Without this, cloned instances share the same AID, causing console confusion.

2. **CID baked in, token at runtime**: The Customer ID (CID) is not secret and can be
   baked into the image. The provisioning token should be provided at first boot (via
   SOPS secret or environment-specific configuration).

3. **Sensor version pinning**: Pin the `.deb` version in the Nix derivation. Sensor
   auto-updates are handled by the Falcon cloud after registration, but the initial
   version should be tested with your WSL kernel.

## NixOS-Specific Notes

- The sensor runs inside a `buildFHSEnv` wrapper because it expects FHS paths
  (`/opt/CrowdStrike`, standard library locations) that NixOS does not provide natively.
- The `/opt/CrowdStrike` directory is created as a mutable tmpfiles directory (not in
  the Nix store) because the sensor writes runtime state (AID, channel files) there.
- `backend = "bpf"` is recommended over `"kernel"` for NixOS, as the BPF backend has
  looser kernel requirements than the kernel module backend.
