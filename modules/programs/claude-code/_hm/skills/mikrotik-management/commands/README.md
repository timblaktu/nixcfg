# Mikrotik Management Skill - Helper Commands

This directory contains executable helper scripts that the mikrotik-management skill uses to interact with RouterOS switches.

## Future Scripts (L0.4+)

When Nix derivation testing utilities are integrated (task L0.4), this directory will contain:

- **query-vlans.sh** - Query VLAN configuration (JSON output)
- **configure-bridge.sh** - Create/modify bridge configurations
- **validate-interface.sh** - Verify interface state and configuration
- **apply-config.sh** - Apply RouterOS configuration from declarative format
- **backup-config.sh** - Export current configuration for disaster recovery

## Design Principles

All scripts will follow these conventions:

1. **--help flag**: Every script includes usage information
   ```bash
   ./query-vlans.sh --help
   ```

2. **JSON output**: Machine-readable output for Claude to parse
   ```bash
   ./query-vlans.sh 192.168.88.1 admin
   # Returns: [{"id": 100, "name": "vlan100", "interface": "ether2"}]
   ```

3. **Dry-run mode**: Support `--dry-run` flag to preview changes
   ```bash
   ./configure-bridge.sh --dry-run bridge-attic ether1 ether2
   # Prints commands without executing
   ```

4. **Error handling**: Exit codes and stderr for error conditions
   - Exit 0: Success
   - Exit 1: Configuration error
   - Exit 2: Connection error
   - Exit 3: Validation failure

5. **Nix integration**: Built with `pkgs.writers.makeBashScript`
   - Automatic shellcheck validation
   - Dependency management (ssh, jq, etc.)
   - Reproducible builds

## Current Status

**Status**: Placeholder (L0.4 task deferred)

The skill currently generates SSH commands directly. Helper scripts will be added when:
- L0.3 manual testing proves skill functionality
- Need for automation/CI emerges
- Nix-based testing infrastructure is beneficial

See Plan 013 task L0.4 for implementation details.
