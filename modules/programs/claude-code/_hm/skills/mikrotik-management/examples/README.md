# Mikrotik Management Skill - Examples

Reference configurations for common Mikrotik RouterOS management tasks.

## Available Configurations

### [L1.0-attic-network.rsc](L1.0-attic-network.rsc)

Complete L1.0 attic network deployment for the CRS326-24G-2S+:
- Bridge: bridge-attic (8 ports, no VLAN filtering)
- IP: 10.0.0.1/24 on bridge-attic
- DHCP: pool 10.0.0.100-200, server on bridge-attic, static lease for NUC (10.0.0.10)
- DNS: upstream 1.1.1.1 + 8.8.8.8, static entries for nux.attic.local

**Usage**:
```bash
# Via skill workflow (recommended)
# Ask: "Deploy L1.0 configuration from examples/L1.0-attic-network.rsc"

# Via direct SSH upload
scp examples/L1.0-attic-network.rsc admin@192.168.88.1:/
ssh admin@192.168.88.1 "/import file-name=L1.0-attic-network.rsc"
```

**Before deploying**: Replace `XX:XX:XX:XX:XX:XX` in the static lease with the actual NUC MAC address.

## Adding New Examples

1. Use `.rsc` extension for RouterOS script files
2. Include header comments with target device, network description, and prerequisites
3. Use descriptive filenames (kebab-case)
4. Mark TODO items clearly for values that need customization (MAC addresses, etc.)
