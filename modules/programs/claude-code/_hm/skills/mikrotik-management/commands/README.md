# Mikrotik Management Skill - Helper Commands

Standalone bash scripts for common Mikrotik RouterOS operations. These work from any terminal with SSH access to the switch - no Nix or Claude Code required.

## Available Scripts

### mikrotik-status.sh

Compact hierarchical status display (standalone version of SKILL.md Section 12).

```bash
./mikrotik-status.sh                    # Default: 192.168.88.1, admin
./mikrotik-status.sh 10.0.0.1           # Custom host
./mikrotik-status.sh 10.0.0.1 myuser    # Custom host and user
```

### mikrotik-backup.sh

Quick backup to local filesystem. Creates both binary (.backup) and text (.rsc) exports.

```bash
./mikrotik-backup.sh                          # Default host, save to current dir
./mikrotik-backup.sh 10.0.0.1                 # Custom host
./mikrotik-backup.sh 10.0.0.1 admin ./backups # Custom host, user, output dir
```

## Design Principles

- **Standalone**: Pure bash + SSH, no dependencies beyond standard Unix tools
- **Safe**: Read-only by default (status is read-only; backup creates files but doesn't modify config)
- **Configurable**: SSH target via positional arguments (default 192.168.88.1)
- **Human-readable**: Output designed for terminal display
