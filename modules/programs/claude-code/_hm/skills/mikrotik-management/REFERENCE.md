# L0.1: Mikrotik Management Skill Design

**Status**: Draft - Awaiting Approval
**Created**: 2026-01-27
**Plan**: 013-distributed-nix-binary-caching.md
**Purpose**: Design reusable Mikrotik RouterOS configuration management skill

---

## Executive Summary

This document defines the architecture for a Claude Code Skill that manages Mikrotik RouterOS switch configuration. The skill will be used to automate L1.0 (Mikrotik network setup) and future Mikrotik management tasks, with focus on robustness, repeatability, and resilience to config resets.

---

## Design Requirements

### Functional Requirements

The skill will manage these top-level RouterOS entities:

#### 1. Interface Management
**RouterOS Path**: `/interface`

Operations:
- Query all interfaces and their properties (type, status, MAC, MTU)
- Enable/disable interfaces
- Configure interface properties (MTU, comment)
- Monitor interface statistics (rx/tx bytes, errors, drops)

**Phase 1 Scope**: Query interfaces only (read-only for validation)

#### 2. VLAN Management
**RouterOS Path**: `/interface vlan`, `/interface bridge vlan`

Operations:
- Query existing VLANs (both interface VLANs and bridge VLANs)
- Create VLAN interfaces on physical interfaces or bridges
- Configure VLAN IDs and tagging
- Assign ports to VLANs (tagged/untagged)
- Enable/disable VLAN filtering on bridges

**Phase 1 Scope**:
- Create VLAN interface on bridge
- Configure VLAN ID
- Basic validation

#### 3. Bridge Management
**RouterOS Path**: `/interface bridge`, `/interface bridge port`

Operations:
- Query existing bridges and their properties
- Create new bridges
- Configure bridge parameters (vlan-filtering, STP, IGMP snooping)
- Add/remove ports from bridges
- Configure port parameters (PVID, frame-types, horizon)
- Query bridge port status

**Phase 1 Scope**:
- Create bridge with vlan-filtering disabled
- Add physical ports (ether1, ether2) to bridge
- Basic validation

#### 4. Port Assignment (Bridge/VLAN Membership)
**RouterOS Path**: `/interface bridge port`, `/interface bridge vlan`

Operations:
- Assign physical ports to bridges
- Configure port VLAN membership (access/trunk)
- Set port PVID (native VLAN for untagged traffic)
- Configure frame-types (admit-all, admit-only-untagged, admit-only-vlan-tagged)
- Query port assignments and current membership

**Phase 1 Scope**:
- Add ether1 and ether2 to bridge-attic
- Basic port assignment only (no PVID or frame-types yet)

#### 5. IP Address Management
**RouterOS Path**: `/ip address`

Operations:
- Query IP addresses assigned to interfaces
- Add IP addresses to interfaces (static)
- Remove IP addresses from interfaces
- Configure address properties (network, interface, comment)
- Validate IP address configuration

**Phase 1 Scope**:
- Add 10.0.0.1/24 to bridge-attic
- Query addresses for validation

#### 6. DHCP Server Management
**RouterOS Path**: `/ip dhcp-server`, `/ip dhcp-server network`, `/ip pool`

Operations:
- Query DHCP server instances and their status
- Create/configure DHCP server on interface
- Define DHCP pools (IP range allocation)
- Configure DHCP networks (gateway, DNS, domain)
- Set static DHCP leases (MAC → IP binding)
- Query active DHCP leases

**Phase 1 Scope**: NOT IMPLEMENTED (deferred to Phase 2 or later)
**Use Case**: For future expansion when we need DHCP for clients on 10.0.0.0/24

#### 7. DNS Configuration
**RouterOS Path**: `/ip dns`, `/ip dns static`

Operations:
- Query DNS server configuration
- Configure DNS servers (upstream resolvers)
- Enable DNS cache
- Add static DNS entries (hostname → IP mappings)
- Query DNS cache statistics

**Phase 1 Scope**: NOT IMPLEMENTED (deferred to Phase 2 or later)
**Use Case**: For future DNS resolution of `nux.attic.local` or similar

#### 8. Configuration Validation
**Cross-Entity Operations**

Operations:
- Verify applied config matches expected state
- Parse RouterOS CLI output for all entities
- Report configuration drift
- Validate dependencies (e.g., IP address requires interface to exist)

**Phase 1 Scope**: Basic validation for bridge, ports, and IP addresses

#### 9. Safety Features
**System-Wide Operations**

Operations:
- Dry-run mode (generate commands without applying)
- Idempotent operations (safe to run multiple times)
- Configuration backup before changes (`/export file=backup-<timestamp>`)
- Configuration restore from backup (`/import file-name=<backup>`)
- Rollback capability if validation fails

**Phase 1 Scope**: All safety features implemented from the start

### Non-Functional Requirements

1. **Robustness**
   - Works with RouterOS default settings (192.168.88.1, admin/<blank>)
   - Survives config resets and reboots
   - No bootstrapping required

2. **Extensibility**
   - Modular design allows adding firewall, NAT, DHCP later
   - Template-based command generation
   - Clear separation of concerns

3. **Testability**
   - Repeatable test suite
   - Dry-run validation
   - Output parsing verification

---

## Architecture

### Communication Stack

```
Claude Code (Bash tool)
    ↓
SSH (admin@192.168.88.1)
    ↓
RouterOS CLI
    ↓
CRS326-24G-2S+ Switch
```

**Connection Details**:
- **Protocol**: SSH
- **Host**: 192.168.88.1 (RouterOS default)
- **User**: admin
- **Password**: <blank> (press Enter at password prompt)
- **Port**: 22 (default SSH port)
- **Connectivity**: Direct ethernet to switch management port

**Rationale**:
- SSH is enabled by default on all RouterOS devices
- Works immediately without any configuration
- Survives config resets (defaults back to 192.168.88.1)
- Most robust method for automation

### Skill Structure

The skill will be implemented as a Claude Code Skill with the following components:

```
.claude/skills/mikrotik-config.md
├── Overview & Usage
│   ├── Purpose and scope
│   ├── Phase 1 vs future capabilities
│   └── Quick start examples
│
├── Connection Management
│   ├── ssh-connect template (admin@192.168.88.1)
│   ├── ssh-exec template (execute single command)
│   ├── ssh-batch template (execute multiple commands)
│   └── Output parsing functions
│
├── 1. Interface Operations (Phase 1: read-only)
│   ├── interface-list template
│   ├── interface-show template (specific interface)
│   ├── interface-stats template
│   └── interface-validate function
│
├── 2. VLAN Operations (Phase 1: basic)
│   ├── vlan-list template
│   ├── vlan-create template (interface VLAN)
│   ├── vlan-show template
│   └── vlan-validate function
│
├── 3. Bridge Operations (Phase 1: full)
│   ├── bridge-list template
│   ├── bridge-create template
│   ├── bridge-show template
│   ├── bridge-configure template (vlan-filtering, etc.)
│   └── bridge-validate function
│
├── 4. Port Assignment Operations (Phase 1: full)
│   ├── bridge-port-list template
│   ├── bridge-port-add template
│   ├── bridge-port-remove template
│   ├── bridge-port-show template
│   └── bridge-port-validate function
│
├── 5. IP Address Operations (Phase 1: full)
│   ├── ip-address-list template
│   ├── ip-address-add template
│   ├── ip-address-remove template
│   ├── ip-address-show template
│   └── ip-address-validate function
│
├── 6. DHCP Server Operations (Phase 2+: not implemented)
│   ├── dhcp-server-list template
│   ├── dhcp-server-create template
│   ├── dhcp-pool-create template
│   ├── dhcp-network-add template
│   ├── dhcp-lease-list template
│   └── dhcp-validate function
│
├── 7. DNS Configuration (Phase 2+: not implemented)
│   ├── dns-config-show template
│   ├── dns-server-set template
│   ├── dns-static-add template
│   ├── dns-cache-list template
│   └── dns-validate function
│
├── Configuration Workflows
│   ├── L1.0 workflow (bridge + VLAN setup for Attic)
│   ├── Validation workflow (verify expected state)
│   └── Rollback workflow (restore from backup)
│
└── Utility Functions
    ├── dry-run mode (generate without executing)
    ├── config-backup (export to file)
    ├── config-restore (import from file)
    ├── output-parser (parse RouterOS CLI output)
    ├── idempotency-check (detect if change needed)
    └── error-handler (parse and report errors)
```

---

## RouterOS CLI Command Templates

This section provides working command templates for each functional area.

### 1. Interface Operations

**List all interfaces**:
```bash
ssh admin@192.168.88.1 "/interface print"
```

**Show specific interface details**:
```bash
ssh admin@192.168.88.1 "/interface print detail where name=ether1"
```

**Get interface statistics**:
```bash
ssh admin@192.168.88.1 "/interface monitor-traffic ether1 once"
```

**Enable/disable interface** (Phase 2+):
```bash
ssh admin@192.168.88.1 "/interface enable ether1"
ssh admin@192.168.88.1 "/interface disable ether1"
```

**Set interface comment** (Phase 2+):
```bash
ssh admin@192.168.88.1 "/interface set ether1 comment='NUC connection'"
```

---

### 2. VLAN Operations

**List all VLANs**:
```bash
ssh admin@192.168.88.1 "/interface vlan print"
```

**Create VLAN interface**:
```bash
ssh admin@192.168.88.1 "/interface vlan add name=vlan-attic interface=bridge-attic vlan-id=10 comment='Attic VLAN'"
```

**Show specific VLAN**:
```bash
ssh admin@192.168.88.1 "/interface vlan print where name=vlan-attic"
```

**Remove VLAN** (Phase 2+):
```bash
ssh admin@192.168.88.1 "/interface vlan remove [find name=vlan-attic]"
```

**Bridge VLAN table operations** (Phase 2+ for VLAN-aware bridges):
```bash
# List bridge VLAN table
ssh admin@192.168.88.1 "/interface bridge vlan print"

# Add VLAN to bridge with tagged/untagged ports
ssh admin@192.168.88.1 "/interface bridge vlan add bridge=bridge-attic tagged=ether1 untagged=ether2 vlan-ids=10"
```

---

### 3. Bridge Operations

**List all bridges**:
```bash
ssh admin@192.168.88.1 "/interface bridge print"
```

**Create bridge**:
```bash
ssh admin@192.168.88.1 "/interface bridge add name=bridge-attic vlan-filtering=no comment='Attic server isolated network'"
```

**Show specific bridge**:
```bash
ssh admin@192.168.88.1 "/interface bridge print detail where name=bridge-attic"
```

**Configure bridge properties** (Phase 2+):
```bash
# Enable VLAN filtering
ssh admin@192.168.88.1 "/interface bridge set bridge-attic vlan-filtering=yes"

# Enable IGMP snooping
ssh admin@192.168.88.1 "/interface bridge set bridge-attic igmp-snooping=yes"

# Configure STP
ssh admin@192.168.88.1 "/interface bridge set bridge-attic protocol-mode=rstp"
```

**Remove bridge** (Phase 2+):
```bash
ssh admin@192.168.88.1 "/interface bridge remove [find name=bridge-attic]"
```

---

### 4. Port Assignment Operations

**List all bridge ports**:
```bash
ssh admin@192.168.88.1 "/interface bridge port print"
```

**List ports for specific bridge**:
```bash
ssh admin@192.168.88.1 "/interface bridge port print where bridge=bridge-attic"
```

**Add port to bridge**:
```bash
ssh admin@192.168.88.1 "/interface bridge port add bridge=bridge-attic interface=ether1 comment='NUC NIC 1'"
ssh admin@192.168.88.1 "/interface bridge port add bridge=bridge-attic interface=ether2 comment='NUC NIC 2'"
```

**Show specific bridge port**:
```bash
ssh admin@192.168.88.1 "/interface bridge port print where bridge=bridge-attic and interface=ether1"
```

**Configure port VLAN properties** (Phase 2+ for VLAN-aware bridges):
```bash
# Set PVID (native VLAN for untagged traffic)
ssh admin@192.168.88.1 "/interface bridge port set [find where interface=ether2] pvid=10"

# Configure frame types (access port - untagged only)
ssh admin@192.168.88.1 "/interface bridge port set [find where interface=ether2] frame-types=admit-only-untagged-and-priority-tagged"

# Configure frame types (trunk port - tagged only)
ssh admin@192.168.88.1 "/interface bridge port set [find where interface=ether1] frame-types=admit-only-vlan-tagged"
```

**Remove port from bridge** (Phase 2+):
```bash
ssh admin@192.168.88.1 "/interface bridge port remove [find where bridge=bridge-attic and interface=ether1]"
```

---

### 5. IP Address Operations

**List all IP addresses**:
```bash
ssh admin@192.168.88.1 "/ip address print"
```

**List addresses for specific interface**:
```bash
ssh admin@192.168.88.1 "/ip address print where interface=bridge-attic"
```

**Add IP address to interface**:
```bash
ssh admin@192.168.88.1 "/ip address add address=10.0.0.1/24 interface=bridge-attic comment='Attic network gateway'"
```

**Show specific IP address**:
```bash
ssh admin@192.168.88.1 "/ip address print detail where address~'10.0.0.1'"
```

**Remove IP address** (Phase 2+):
```bash
ssh admin@192.168.88.1 "/ip address remove [find where interface=bridge-attic]"
```

**Verify IP is assigned and interface is up**:
```bash
ssh admin@192.168.88.1 "/ip address print where interface=bridge-attic and disabled=no"
```

---

### 6. DHCP Server Operations (Phase 2+ - Not Implemented)

**List DHCP servers**:
```bash
ssh admin@192.168.88.1 "/ip dhcp-server print"
```

**Create DHCP server**:
```bash
# Create IP pool first
ssh admin@192.168.88.1 "/ip pool add name=pool-attic ranges=10.0.0.100-10.0.0.200"

# Create DHCP server
ssh admin@192.168.88.1 "/ip dhcp-server add name=dhcp-attic interface=bridge-attic address-pool=pool-attic disabled=no"

# Configure DHCP network (gateway, DNS, domain)
ssh admin@192.168.88.1 "/ip dhcp-server network add address=10.0.0.0/24 gateway=10.0.0.1 dns-server=1.1.1.1,8.8.8.8 domain=attic.local"
```

**List active DHCP leases**:
```bash
ssh admin@192.168.88.1 "/ip dhcp-server lease print"
```

**Add static DHCP lease (MAC → IP binding)**:
```bash
ssh admin@192.168.88.1 "/ip dhcp-server lease add address=10.0.0.10 mac-address=AA:BB:CC:DD:EE:FF server=dhcp-attic comment='nux static lease'"
```

---

### 7. DNS Configuration (Phase 2+ - Not Implemented)

**Show DNS configuration**:
```bash
ssh admin@192.168.88.1 "/ip dns print"
```

**Configure DNS servers (upstream resolvers)**:
```bash
ssh admin@192.168.88.1 "/ip dns set servers=1.1.1.1,8.8.8.8 allow-remote-requests=yes"
```

**Add static DNS entry**:
```bash
ssh admin@192.168.88.1 "/ip dns static add name=nux.attic.local address=10.0.0.10 comment='Attic server'"
```

**List static DNS entries**:
```bash
ssh admin@192.168.88.1 "/ip dns static print"
```

**List DNS cache**:
```bash
ssh admin@192.168.88.1 "/ip dns cache print"
```

---

### Configuration Management Operations

**Backup configuration**:
```bash
ssh admin@192.168.88.1 "/export file=backup-$(date +%Y%m%d-%H%M%S)"
```

**List backup files**:
```bash
ssh admin@192.168.88.1 "/file print where name~'backup'"
```

**Restore configuration**:
```bash
ssh admin@192.168.88.1 "/import file-name=backup-20260127-120000.rsc"
```

**Factory reset** (DANGEROUS - for testing only):
```bash
ssh admin@192.168.88.1 "/system reset-configuration no-defaults=yes skip-backup=yes"
```

---

## Skill Interface Design

### Usage Pattern

The skill will be invoked via Claude Code's Skill tool:

```nix
Skill { skill: "mikrotik-config" }
```

Upon invocation, the skill prompt will expand with:
1. Connection instructions
2. Available operations
3. Command templates
4. Validation procedures

### Operation Modes

**1. Query Mode** (read-only):
```bash
# List all VLANs
ssh admin@192.168.88.1 "/interface vlan print"

# List all bridges
ssh admin@192.168.88.1 "/interface bridge print"

# Show bridge ports
ssh admin@192.168.88.1 "/interface bridge port print"
```

**2. Dry-Run Mode** (generate commands without applying):
- Output RouterOS CLI commands to stdout
- User can review before execution
- Useful for learning and verification

**3. Apply Mode** (execute configuration):
- Execute commands via SSH
- Parse output for success/failure
- Validate applied configuration

**4. Validate Mode** (verify configuration):
- Check if expected config matches actual state
- Report any drift
- Idempotent check (safe to re-run)

---

## Configuration State Model

For L1.0, we need to manage this configuration state across multiple RouterOS entities:

```yaml
target_config:
  # 1. Interfaces (read-only validation in Phase 1)
  interfaces:
    validate:
      - name: "ether1"
        expected_status: "running"
        expected_type: "ether"
      - name: "ether2"
        expected_status: "running"
        expected_type: "ether"

  # 2. VLANs (basic creation in Phase 1)
  vlans:
    - name: "vlan-attic"
      vlan_id: 10
      interface: "bridge-attic"
      comment: "Attic VLAN 10"

  # 3. Bridges (full management in Phase 1)
  bridges:
    - name: "bridge-attic"
      vlan_filtering: false
      comment: "Attic server isolated network"

  # 4. Port Assignments (full management in Phase 1)
  bridge_ports:
    - bridge: "bridge-attic"
      interface: "ether1"
      comment: "NUC NIC 1"
    - bridge: "bridge-attic"
      interface: "ether2"
      comment: "NUC NIC 2"

  # 5. IP Addresses (full management in Phase 1)
  ip_addresses:
    - address: "10.0.0.1/24"
      interface: "bridge-attic"
      comment: "Attic network gateway"

  # 6. DHCP Server (Phase 2+ - not implemented)
  dhcp_servers: []
  # Future example:
  # - name: "dhcp-attic"
  #   interface: "bridge-attic"
  #   address_pool: "pool-attic"
  #   pool_ranges: "10.0.0.100-10.0.0.200"
  #   network:
  #     address: "10.0.0.0/24"
  #     gateway: "10.0.0.1"
  #     dns_servers: ["1.1.1.1", "8.8.8.8"]
  #     domain: "attic.local"

  # 7. DNS Configuration (Phase 2+ - not implemented)
  dns_config: {}
  # Future example:
  # servers: ["1.1.1.1", "8.8.8.8"]
  # allow_remote_requests: true
  # static_entries:
  #   - name: "nux.attic.local"
  #     address: "10.0.0.10"
```

### State Management Workflow

The skill will use this workflow for each configuration entity:

1. **Query Current State**
   - Execute appropriate `/interface/bridge/ip address print` commands
   - Parse output into structured data
   - Build current state model

2. **Compare with Target State**
   - Diff current vs target for each entity
   - Identify additions, modifications, deletions needed
   - Check dependencies (e.g., bridge must exist before adding ports)

3. **Generate Reconciliation Commands**
   - Generate RouterOS CLI commands to reconcile differences
   - Respect dependency order (interfaces → bridges → ports → IPs)
   - Include idempotency checks (don't add if already exists)

4. **Apply Changes** (if not dry-run)
   - Backup current config first (`/export file=backup-<timestamp>`)
   - Execute generated commands via SSH
   - Parse output for errors
   - Validate after each critical operation

5. **Validate Final State**
   - Re-query all affected entities
   - Verify final state matches target state
   - Report any drift or failures
   - Suggest rollback if validation fails

### Dependency Graph (Phase 1)

```
Interfaces (ether1, ether2) [pre-existing, validated]
    ↓
Bridge (bridge-attic) [created]
    ↓
Bridge Ports (ether1→bridge, ether2→bridge) [created]
    ↓
IP Address (10.0.0.1/24→bridge-attic) [created]
    ↓
VLAN Interface (vlan-attic on bridge-attic) [created]
```

Operations must follow this order to avoid dependency errors.

---

## Output Parsing Strategy

RouterOS CLI output varies by command. We need parsers for:

### 1. Print Commands (list items)

**Input**:
```
Flags: X - disabled, R - running, S - slave
 #    NAME                                    TYPE             ACTUAL-MTU L2MTU  MAX-L2MTU MAC-ADDRESS
 0  R ether1                                  ether                  1500  1580      10218 E4:38:83:XX:XX:XX
 1  R ether2                                  ether                  1500  1580      10218 E4:38:83:XX:XX:XX
```

**Parser Strategy**:
- Skip flag/header lines
- Extract numbered entries
- Parse columns by whitespace or alignment

### 2. Where Queries (filtered results)

**Input**:
```
 0    name="bridge-attic" mtu=auto actual-mtu=1500 l2mtu=65535 ...
```

**Parser Strategy**:
- Look for `name="<value>"` patterns
- Extract key=value pairs
- Return structured data

### 3. Error Detection

**Success indicators**:
- No output (for add/set commands)
- Numbered list (for print commands)

**Error indicators**:
- `failure:` prefix
- `expected end of command` (syntax error)
- `no such item` (resource not found)

---

## Safety Mechanisms

### 1. Configuration Backup

Before ANY changes, backup current config:
```bash
ssh admin@192.168.88.1 "/export file=backup-$(date +%Y%m%d-%H%M%S)"
```

Backups are stored on the switch in `/` and can be restored if needed.

### 2. Idempotent Operations

Commands should be idempotent (safe to run multiple times):

**Bad** (creates duplicates):
```bash
/interface bridge add name=bridge-attic
/interface bridge add name=bridge-attic  # ERROR: already exists
```

**Good** (checks first):
```bash
# Check if bridge exists
EXISTS=$(ssh admin@192.168.88.1 "/interface bridge print count-only where name=bridge-attic")
if [ "$EXISTS" = "0" ]; then
  ssh admin@192.168.88.1 "/interface bridge add name=bridge-attic"
fi
```

### 3. Dry-Run Mode

Generate commands without executing:
```bash
echo "Would execute: /interface bridge add name=bridge-attic vlan-filtering=no"
echo "Would execute: /interface bridge port add bridge=bridge-attic interface=ether1"
```

User can review, then execute manually or via apply mode.

### 4. Validation After Changes

After applying config, always validate:
```bash
# Verify bridge exists
ssh admin@192.168.88.1 "/interface bridge print where name=bridge-attic"

# Verify ports are added
ssh admin@192.168.88.1 "/interface bridge port print where bridge=bridge-attic"

# Count expected resources
EXPECTED_PORTS=2
ACTUAL_PORTS=$(ssh admin@192.168.88.1 "/interface bridge port print count-only where bridge=bridge-attic")
if [ "$ACTUAL_PORTS" != "$EXPECTED_PORTS" ]; then
  echo "ERROR: Expected $EXPECTED_PORTS ports, found $ACTUAL_PORTS"
fi
```

---

## Testing Strategy

### Test Suite Structure

```
tests/mikrotik-skill-validation.sh
├── Test 1: SSH Connectivity
│   └── Verify: Can connect to 192.168.88.1 with admin/<blank>
├── Test 2: Query Operations
│   ├── Verify: Can list VLANs
│   ├── Verify: Can list bridges
│   └── Verify: Can list bridge ports
├── Test 3: Dry-Run Mode
│   ├── Verify: Generates correct commands
│   └── Verify: Does NOT apply changes
├── Test 4: Idempotency
│   ├── Apply config once
│   ├── Apply config again
│   └── Verify: No errors, no duplicates
├── Test 5: Validation
│   ├── Apply test config
│   ├── Run validation
│   └── Verify: Reports correct state
└── Test 6: Cleanup
    └── Remove test resources
```

### Test Execution Environment

**Prerequisites**:
- Direct ethernet connection to Mikrotik mgmt port
- User's laptop configured with static IP in 192.168.88.0/24 range (e.g., 192.168.88.50/24)
- SSH client installed

**Test Data**:
- Use prefix `test-` for all test resources
- Example: `test-bridge`, `test-vlan-100`
- Cleanup after each test

---

## Implementation Plan (L0.2)

### Phase 1 Implementation (Minimal Scope for L1.0)

This implementation focuses on the entities needed for L1.0 (Mikrotik network setup):

#### Step 1: Core Infrastructure
1. Create skill file: `.claude/skills/mikrotik-config.md`
2. Implement SSH connection wrapper
   - `ssh_connect()` - Test connectivity
   - `ssh_exec()` - Execute single command
   - `ssh_batch()` - Execute multiple commands
3. Implement output parser functions
   - `parse_print_output()` - Parse `/print` command output
   - `parse_where_output()` - Parse filtered queries
   - `parse_errors()` - Detect and extract error messages
4. Add safety features
   - `dry_run_mode()` - Generate commands without executing
   - `config_backup()` - Export current config
   - `idempotency_check()` - Detect if change is needed

#### Step 2: Interface Operations (Read-Only)
1. Implement `interface-list` operation
   - List all interfaces with status
   - Filter by name, type, or status
2. Implement `interface-validate` operation
   - Verify expected interfaces exist
   - Check interface status (running/disabled)
3. Add to skill documentation with examples

#### Step 3: Bridge Operations (Full)
1. Implement `bridge-list` operation
   - List all bridges
   - Show detailed properties
2. Implement `bridge-create` operation
   - Create bridge with specified properties
   - Include idempotency check
3. Implement `bridge-validate` operation
   - Verify bridge exists with correct properties
4. Add to skill documentation with examples

#### Step 4: Port Assignment Operations (Full)
1. Implement `bridge-port-list` operation
   - List all bridge ports
   - Filter by bridge name
2. Implement `bridge-port-add` operation
   - Add interface to bridge
   - Include idempotency check
3. Implement `bridge-port-validate` operation
   - Verify ports are assigned to correct bridge
4. Add to skill documentation with examples

#### Step 5: IP Address Operations (Full)
1. Implement `ip-address-list` operation
   - List all IP addresses
   - Filter by interface
2. Implement `ip-address-add` operation
   - Add IP to interface
   - Include idempotency check
3. Implement `ip-address-validate` operation
   - Verify IP is assigned to interface
4. Add to skill documentation with examples

#### Step 6: VLAN Operations (Basic)
1. Implement `vlan-list` operation
   - List all VLAN interfaces
2. Implement `vlan-create` operation
   - Create VLAN interface on bridge
   - Include idempotency check
3. Implement `vlan-validate` operation
   - Verify VLAN exists with correct properties
4. Add to skill documentation with examples

#### Step 7: Configuration Workflows
1. Implement L1.0 complete workflow
   - Validate interfaces (ether1, ether2)
   - Create bridge (bridge-attic)
   - Add ports to bridge (ether1, ether2)
   - Add IP to bridge (10.0.0.1/24)
   - Create VLAN interface (vlan-attic, VLAN ID 10)
   - Validate all configuration
2. Create workflow documentation
3. Add rollback capability
4. Create usage examples

#### Step 8: Testing Integration
1. Add test hooks to skill
2. Document expected test coverage
3. Create example test invocations
4. Link to L0.3 test suite

### Phase 2+ Extensions (Future - Beyond L1.0)

These will be added after Phase 1 is validated:

#### DHCP Server Operations
- Query DHCP servers, pools, networks, leases
- Create DHCP server with pool and network config
- Add static DHCP leases
- Validate DHCP configuration

#### DNS Configuration
- Query DNS settings
- Configure upstream DNS servers
- Add static DNS entries
- Validate DNS configuration

#### Advanced Bridge Features
- VLAN filtering enablement
- Bridge VLAN table management
- Port VLAN properties (PVID, frame-types)
- STP/RSTP configuration
- IGMP snooping

#### Interface Management
- Enable/disable interfaces
- Configure interface properties
- Monitor interface statistics

#### Configuration Management
- Export/import configurations
- Configuration diffing
- Automated rollback on validation failure
- Multi-switch management

---

## Future Extensions (Beyond Phase 1)

### Phase 2: Firewall & NAT (for L1.0 completion)
- Firewall rule management
- NAT configuration
- Traffic filtering

### Phase 3: DHCP Server
- DHCP pool management
- Static lease assignment
- DNS integration

### Phase 4: Advanced Features
- Configuration diffing
- Rollback capability
- Configuration templates
- Multi-switch management

---

## Risk Mitigation

### Risk 1: SSH Connection Failures

**Mitigation**:
- Use RouterOS defaults (192.168.88.1, admin/<blank>)
- Verify connectivity before any operations
- Clear error messages for connection issues

### Risk 2: Config Reset During Testing

**Impact**: Config resets will restore defaults (192.168.88.1)
**Mitigation**: Design assumes defaults, no bootstrapping needed

### Risk 3: Partial Configuration Application

**Scenario**: Command succeeds but validation fails
**Mitigation**:
- Backup before changes
- Validate after each operation
- Document rollback procedure

### Risk 4: Output Parsing Errors

**Scenario**: RouterOS output format changes
**Mitigation**:
- Use stable CLI commands (not beta features)
- Extensive parser testing
- Graceful error handling

---

## Success Criteria

L0.1 is complete when:
- [x] Design document created and approved
- [x] Architecture decisions documented (SSH via RouterOS CLI, RouterOS defaults)
- [x] Functional requirements defined (7 RouterOS entities: Interfaces, VLANs, Bridges, Ports, IP Addresses, DHCP, DNS)
- [x] Command templates defined (comprehensive examples for all entities)
- [x] Configuration state model defined (YAML target config with dependency graph)
- [x] Safety mechanisms specified (dry-run, idempotency, backup, validation, rollback)
- [x] Testing strategy outlined (6-test suite with idempotency and validation checks)
- [x] Implementation plan ready for L0.2 (8-step Phase 1 plan)

---

## Appendix: RouterOS CLI Reference

### Key Commands for Phase 1

```bash
# Bridge Management
/interface bridge add name=<name> [vlan-filtering=yes|no] [comment="<text>"]
/interface bridge remove [find name=<name>]
/interface bridge print [where name=<name>]
/interface bridge set <id> vlan-filtering=yes

# Bridge Port Management
/interface bridge port add bridge=<bridge-name> interface=<interface-name> [comment="<text>"]
/interface bridge port remove [find where bridge=<bridge-name> and interface=<interface-name>]
/interface bridge port print [where bridge=<bridge-name>]

# IP Address Management
/ip address add address=<ip>/<mask> interface=<interface-name> [comment="<text>"]
/ip address remove [find where interface=<interface-name>]
/ip address print [where interface=<interface-name>]

# VLAN Management
/interface vlan add name=<name> vlan-id=<id> interface=<interface-name> [comment="<text>"]
/interface vlan remove [find name=<name>]
/interface vlan print [where name=<name>]

# Bridge VLAN Table (for VLAN-aware bridges)
/interface bridge vlan add bridge=<bridge-name> tagged=<ports> untagged=<ports> vlan-ids=<id>
/interface bridge vlan print [where bridge=<bridge-name>]

# Configuration Management
/export file=<filename>                    # Backup config
/import file-name=<filename>               # Restore config
/system reset-configuration no-defaults    # Factory reset
```

### Useful Query Commands

```bash
# Count items
/interface bridge print count-only [where <filter>]

# Check if exists (returns 1 or 0)
/interface bridge print count-only where name=bridge-attic

# Get specific properties
/interface bridge print where name=bridge-attic

# Find by multiple criteria
/interface bridge port print where bridge=bridge-attic and interface=ether1
```

---

## Notes for L0.2 Implementation

1. **Start with read-only operations** - Implement query commands first, test thoroughly
2. **Build incrementally** - VLAN operations first, then bridge operations
3. **Test after each addition** - Don't wait until everything is implemented
4. **Use real hardware** - Test on actual CRS326-24G-2S+ switch
5. **Document as you go** - Add usage examples to skill file

---

## References

- [MikroTik RouterOS Documentation](https://help.mikrotik.com/docs/display/ROS/)
- [Bridge VLAN Configuration](https://help.mikrotik.com/docs/display/ROS/Bridging+and+Switching)
- [First Time Configuration](https://help.mikrotik.com/docs/display/ROS/First+Time+Configuration)
- Plan 013: `.claude/user-plans/013-distributed-nix-binary-caching.md`
- L1.0 Guide: `docs/wip-L1.0-mikrotik-setup.md` (previous manual approach)
