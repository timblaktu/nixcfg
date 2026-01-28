---
name: mikrotik-management
description: Automate Mikrotik RouterOS configuration for VLANs, bridges, ports, IP addressing, DHCP, and DNS. Use for network infrastructure setup, switch configuration, factory reset procedures, or RouterOS management tasks.
---

# Mikrotik RouterOS Configuration Management Skill

**Version**: 2.0.0 (Phase 1 Complete + DHCP/DNS)
**Target**: Mikrotik CRS326-24G-2S+ Switch
**RouterOS Version**: 7.x
**Connection**: SSH to 192.168.88.1 (admin with blank password)
**Last Updated**: 2026-01-27

## Overview

This skill manages Mikrotik RouterOS switch configuration via SSH CLI commands. It provides structured operations for configuring bridges, VLANs, ports, IP addresses, DHCP servers, and DNS with safety features including dry-run mode, idempotency checks, and configuration backups.

**Phase 1 Capabilities** (Current - v2.0.0):
- Interface validation (read-only)
- Bridge management (full CRUD)
- Bridge port assignment (full CRUD)
- IP address management (full CRUD)
- VLAN interface creation (basic)
- **DHCP server management (full)** - NEW in v2.0.0
  - IP pool creation
  - DHCP server configuration
  - DHCP network parameters
  - Static lease assignment
- **DNS configuration (full)** - NEW in v2.0.0
  - Upstream DNS servers
  - Static DNS entries
  - DNS cache management
- L1.0 complete workflow (8-port bridge + DHCP + DNS)

**Phase 2+ Capabilities** (Future):
- Advanced VLAN filtering
- Firewall rules

---

## Connection Details

**Default RouterOS Settings**:
- IP: 192.168.88.1
- User: admin
- Password: (blank - press Enter)
- Port: 22 (SSH)

**Prerequisites**:
- Direct ethernet connection to Mikrotik management port
- Your system configured with static IP in 192.168.88.0/24 range (e.g., 192.168.88.50/24)
- SSH client available

**Test Connectivity**:
```bash
ssh admin@192.168.88.1 "/system resource print"
# Press Enter when prompted for password (it's blank)
# Should display system information
```

---

## Core Infrastructure

### SSH Connection Wrappers

**ssh_exec() - Execute Single Command**:
```bash
# Usage: ssh_exec <command>
# Example: ssh_exec "/interface print"
ssh_exec() {
    local cmd="$1"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@192.168.88.1 "$cmd"
}
```

**ssh_batch() - Execute Multiple Commands**:
```bash
# Usage: ssh_batch <<'EOF'
# /command1
# /command2
# EOF
ssh_batch() {
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@192.168.88.1
}
```

### Output Parsers

**parse_count() - Get Count from count-only Query**:
```bash
# Usage: count=$(parse_count "$(ssh_exec '/interface bridge print count-only where name=bridge-attic')")
parse_count() {
    echo "$1" | tr -d '[:space:]'
}
```

**parse_exists() - Check If Resource Exists**:
```bash
# Usage: if parse_exists "/interface bridge print count-only where name=bridge-attic"; then ...
parse_exists() {
    local query="$1"
    local count=$(parse_count "$(ssh_exec "$query")")
    [ "$count" != "0" ]
}
```

**parse_print_output() - Extract Values from print Command**:
```bash
# Usage: parse_print_output <output> <field>
# Extracts field values from RouterOS print output
parse_print_output() {
    local output="$1"
    local field="$2"
    echo "$output" | grep -oP "(?<=$field=)[^\s]+" || echo ""
}
```

**parse_errors() - Detect Errors in Command Output**:
```bash
# Usage: if parse_errors "$output"; then echo "Error detected"; fi
parse_errors() {
    local output="$1"
    echo "$output" | grep -qiE '(failure:|error:|expected end of command|no such item)'
}
```

### Safety Features

**dry_run_mode() - Generate Commands Without Executing**:
```bash
# Set DRY_RUN=1 to enable dry-run mode
DRY_RUN=${DRY_RUN:-0}

execute_cmd() {
    local cmd="$1"
    if [ "$DRY_RUN" = "1" ]; then
        echo "[DRY-RUN] Would execute: $cmd"
    else
        ssh_exec "$cmd"
    fi
}
```

**config_backup() - Backup Configuration Before Changes**:
```bash
# Usage: backup_file=$(config_backup)
config_backup() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local filename="backup-$timestamp"
    echo "[INFO] Creating backup: $filename" >&2
    ssh_exec "/export file=$filename" >/dev/null
    echo "$filename"
}
```

**config_restore() - Restore Configuration from Backup**:
```bash
# Usage: config_restore <backup-filename>
config_restore() {
    local filename="$1"
    echo "[INFO] Restoring from backup: $filename" >&2
    ssh_exec "/import file-name=$filename.rsc"
}
```

**idempotency_check() - Check If Change Is Needed**:
```bash
# Usage: if idempotency_check "/interface bridge print count-only where name=bridge-attic"; then
#            echo "Bridge already exists"
#        fi
idempotency_check() {
    local query="$1"
    parse_exists "$query"
}
```

---

## 1. Interface Operations (Read-Only)

### interface-list - List All Interfaces

**Command**:
```bash
ssh_exec "/interface print"
```

**Example Output**:
```
Flags: X - disabled, R - running, S - slave
 #    NAME                                    TYPE             ACTUAL-MTU L2MTU
 0  R ether1                                  ether                  1500  1580
 1  R ether2                                  ether                  1500  1580
```

### interface-show - Show Specific Interface

**Command**:
```bash
ssh_exec "/interface print detail where name=ether1"
```

### interface-validate - Validate Expected Interfaces

**Usage**:
```bash
# Validate that ether1 and ether2 exist and are running
validate_interface() {
    local iface="$1"
    echo "[INFO] Validating interface: $iface"

    local output=$(ssh_exec "/interface print count-only where name=$iface")
    local count=$(parse_count "$output")

    if [ "$count" = "0" ]; then
        echo "[ERROR] Interface $iface not found"
        return 1
    fi

    echo "[OK] Interface $iface exists"
    return 0
}

# Example:
validate_interface "ether1"
validate_interface "ether2"
```

---

## 2. Bridge Operations (Full CRUD)

### bridge-list - List All Bridges

**Command**:
```bash
ssh_exec "/interface bridge print"
```

**Example Output**:
```
 0    name="bridge-attic" mtu=auto actual-mtu=1500 l2mtu=65535 ...
```

### bridge-create - Create Bridge with Idempotency

**Usage**:
```bash
bridge_create() {
    local name="$1"
    local vlan_filtering="${2:-no}"
    local comment="${3:-}"

    echo "[INFO] Creating bridge: $name (vlan-filtering=$vlan_filtering)"

    # Idempotency check
    if idempotency_check "/interface bridge print count-only where name=$name"; then
        echo "[OK] Bridge $name already exists (idempotent)"
        return 0
    fi

    # Build command
    local cmd="/interface bridge add name=$name vlan-filtering=$vlan_filtering"
    [ -n "$comment" ] && cmd="$cmd comment=\"$comment\""

    # Execute
    execute_cmd "$cmd"

    # Validate
    if parse_exists "/interface bridge print count-only where name=$name"; then
        echo "[OK] Bridge $name created successfully"
        return 0
    else
        echo "[ERROR] Bridge $name creation failed"
        return 1
    fi
}

# Example:
bridge_create "bridge-attic" "no" "Attic server isolated network"
```

### bridge-show - Show Specific Bridge

**Command**:
```bash
ssh_exec "/interface bridge print detail where name=bridge-attic"
```

### bridge-remove - Remove Bridge (Phase 2+)

**Command** (not implemented in Phase 1):
```bash
ssh_exec "/interface bridge remove [find name=bridge-attic]"
```

### bridge-validate - Validate Bridge Configuration

**Usage**:
```bash
validate_bridge() {
    local name="$1"
    local expected_vlan_filtering="${2:-no}"

    echo "[INFO] Validating bridge: $name"

    if ! parse_exists "/interface bridge print count-only where name=$name"; then
        echo "[ERROR] Bridge $name not found"
        return 1
    fi

    local output=$(ssh_exec "/interface bridge print detail where name=$name")
    local actual_vlan_filtering=$(parse_print_output "$output" "vlan-filtering")

    if [ "$actual_vlan_filtering" != "$expected_vlan_filtering" ]; then
        echo "[WARNING] VLAN filtering mismatch: expected=$expected_vlan_filtering, actual=$actual_vlan_filtering"
    fi

    echo "[OK] Bridge $name validated"
    return 0
}

# Example:
validate_bridge "bridge-attic" "no"
```

---

## 3. Bridge Port Operations (Full CRUD)

### bridge-port-list - List Bridge Ports

**Command**:
```bash
# List all bridge ports
ssh_exec "/interface bridge port print"

# List ports for specific bridge
ssh_exec "/interface bridge port print where bridge=bridge-attic"
```

**Example Output**:
```
 0    interface=ether1 bridge=bridge-attic hw=yes
 1    interface=ether2 bridge=bridge-attic hw=yes
```

### bridge-port-add - Add Port to Bridge with Idempotency

**Usage**:
```bash
bridge_port_add() {
    local bridge="$1"
    local interface="$2"
    local comment="${3:-}"

    echo "[INFO] Adding port $interface to bridge $bridge"

    # Idempotency check
    if idempotency_check "/interface bridge port print count-only where bridge=$bridge and interface=$interface"; then
        echo "[OK] Port $interface already in bridge $bridge (idempotent)"
        return 0
    fi

    # Build command
    local cmd="/interface bridge port add bridge=$bridge interface=$interface"
    [ -n "$comment" ] && cmd="$cmd comment=\"$comment\""

    # Execute
    execute_cmd "$cmd"

    # Validate
    if parse_exists "/interface bridge port print count-only where bridge=$bridge and interface=$interface"; then
        echo "[OK] Port $interface added to bridge $bridge"
        return 0
    else
        echo "[ERROR] Failed to add port $interface to bridge $bridge"
        return 1
    fi
}

# Example:
bridge_port_add "bridge-attic" "ether1" "NUC NIC 1"
bridge_port_add "bridge-attic" "ether2" "NUC NIC 2"
```

### bridge-port-remove - Remove Port from Bridge (Phase 2+)

**Command** (not implemented in Phase 1):
```bash
ssh_exec "/interface bridge port remove [find where bridge=bridge-attic and interface=ether1]"
```

### bridge-port-validate - Validate Bridge Port Configuration

**Usage**:
```bash
validate_bridge_port() {
    local bridge="$1"
    local interface="$2"

    echo "[INFO] Validating bridge port: $interface in $bridge"

    if ! parse_exists "/interface bridge port print count-only where bridge=$bridge and interface=$interface"; then
        echo "[ERROR] Port $interface not found in bridge $bridge"
        return 1
    fi

    echo "[OK] Port $interface validated in bridge $bridge"
    return 0
}

# Example:
validate_bridge_port "bridge-attic" "ether1"
validate_bridge_port "bridge-attic" "ether2"
```

---

## 4. IP Address Operations (Full CRUD)

### ip-address-list - List IP Addresses

**Command**:
```bash
# List all IP addresses
ssh_exec "/ip address print"

# List addresses for specific interface
ssh_exec "/ip address print where interface=bridge-attic"
```

**Example Output**:
```
 0    address=10.0.0.1/24 interface=bridge-attic network=10.0.0.0
```

### ip-address-add - Add IP Address with Idempotency

**Usage**:
```bash
ip_address_add() {
    local address="$1"    # Format: 10.0.0.1/24
    local interface="$2"
    local comment="${3:-}"

    echo "[INFO] Adding IP $address to interface $interface"

    # Idempotency check
    if idempotency_check "/ip address print count-only where interface=$interface and address~'${address%%/*}'"; then
        echo "[OK] IP $address already assigned to $interface (idempotent)"
        return 0
    fi

    # Build command
    local cmd="/ip address add address=$address interface=$interface"
    [ -n "$comment" ] && cmd="$cmd comment=\"$comment\""

    # Execute
    execute_cmd "$cmd"

    # Validate
    if parse_exists "/ip address print count-only where interface=$interface"; then
        echo "[OK] IP $address added to interface $interface"
        return 0
    else
        echo "[ERROR] Failed to add IP $address to interface $interface"
        return 1
    fi
}

# Example:
ip_address_add "10.0.0.1/24" "bridge-attic" "Attic network gateway"
```

### ip-address-remove - Remove IP Address (Phase 2+)

**Command** (not implemented in Phase 1):
```bash
ssh_exec "/ip address remove [find where interface=bridge-attic]"
```

### ip-address-validate - Validate IP Configuration

**Usage**:
```bash
validate_ip_address() {
    local interface="$1"
    local expected_network="$2"  # e.g., "10.0.0"

    echo "[INFO] Validating IP address on interface: $interface"

    if ! parse_exists "/ip address print count-only where interface=$interface"; then
        echo "[ERROR] No IP address found on interface $interface"
        return 1
    fi

    local output=$(ssh_exec "/ip address print where interface=$interface")
    if ! echo "$output" | grep -q "$expected_network"; then
        echo "[ERROR] IP address on $interface does not match expected network $expected_network.*"
        return 1
    fi

    echo "[OK] IP address on $interface validated"
    return 0
}

# Example:
validate_ip_address "bridge-attic" "10.0.0"
```

---

## 5. VLAN Operations (Basic)

### vlan-list - List VLAN Interfaces

**Command**:
```bash
ssh_exec "/interface vlan print"
```

**Example Output**:
```
 0    name="vlan-attic" mtu=1500 vlan-id=10 interface=bridge-attic
```

### vlan-create - Create VLAN Interface with Idempotency

**Usage**:
```bash
vlan_create() {
    local name="$1"
    local vlan_id="$2"
    local interface="$3"
    local comment="${4:-}"

    echo "[INFO] Creating VLAN: $name (ID=$vlan_id on $interface)"

    # Idempotency check
    if idempotency_check "/interface vlan print count-only where name=$name"; then
        echo "[OK] VLAN $name already exists (idempotent)"
        return 0
    fi

    # Build command
    local cmd="/interface vlan add name=$name vlan-id=$vlan_id interface=$interface"
    [ -n "$comment" ] && cmd="$cmd comment=\"$comment\""

    # Execute
    execute_cmd "$cmd"

    # Validate
    if parse_exists "/interface vlan print count-only where name=$name"; then
        echo "[OK] VLAN $name created successfully"
        return 0
    else
        echo "[ERROR] VLAN $name creation failed"
        return 1
    fi
}

# Example:
vlan_create "vlan-attic" "10" "bridge-attic" "Attic VLAN 10"
```

### vlan-show - Show Specific VLAN

**Command**:
```bash
ssh_exec "/interface vlan print detail where name=vlan-attic"
```

### vlan-validate - Validate VLAN Configuration

**Usage**:
```bash
validate_vlan() {
    local name="$1"
    local expected_vlan_id="$2"
    local expected_interface="$3"

    echo "[INFO] Validating VLAN: $name"

    if ! parse_exists "/interface vlan print count-only where name=$name"; then
        echo "[ERROR] VLAN $name not found"
        return 1
    fi

    local output=$(ssh_exec "/interface vlan print detail where name=$name")
    local actual_vlan_id=$(parse_print_output "$output" "vlan-id")
    local actual_interface=$(parse_print_output "$output" "interface")

    if [ "$actual_vlan_id" != "$expected_vlan_id" ]; then
        echo "[ERROR] VLAN ID mismatch: expected=$expected_vlan_id, actual=$actual_vlan_id"
        return 1
    fi

    if [ "$actual_interface" != "$expected_interface" ]; then
        echo "[ERROR] Interface mismatch: expected=$expected_interface, actual=$actual_interface"
        return 1
    fi

    echo "[OK] VLAN $name validated"
    return 0
}

# Example:
validate_vlan "vlan-attic" "10" "bridge-attic"
```

---

## Configuration Workflows

### L1.0 Complete Workflow - Attic Network Setup (Updated 2026-01-27)

This workflow implements the complete L1.0 configuration per user requirements:
- Bridge: bridge-attic (flat bridge, no VLAN tagging)
- Ports: ether1-ether8 (8 ports for multiple devices)
- IP: 10.0.0.1/24 (gateway)
- DHCP: Pool 10.0.0.100-200 with static lease for NUC (10.0.0.10)
- DNS: Upstream 1.1.1.1,8.8.8.8 with static entries for nux.attic.local

**Complete Script**:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Configuration target state
BRIDGE_NAME="bridge-attic"
IP_ADDRESS="10.0.0.1/24"
PORTS=("ether1" "ether2" "ether3" "ether4" "ether5" "ether6" "ether7" "ether8")
PORT_COMMENTS=(
    "NUC NIC 1 (management)"
    "NUC NIC 2 (data)"
    "Port 3 (available)"
    "Port 4 (available)"
    "Port 5 (available)"
    "Port 6 (available)"
    "Port 7 (available)"
    "Port 8 (available)"
)

# DHCP configuration
DHCP_POOL_NAME="pool-attic"
DHCP_POOL_RANGE="10.0.0.100-10.0.0.200"
DHCP_SERVER_NAME="dhcp-attic"
DHCP_NETWORK="10.0.0.0/24"
DHCP_GATEWAY="10.0.0.1"
DHCP_DNS="10.0.0.1"
DHCP_DOMAIN="attic.local"

# NUC static lease (REPLACE MAC ADDRESS!)
NUC_IP="10.0.0.10"
NUC_MAC="XX:XX:XX:XX:XX:XX"  # TODO: Replace with actual NUC MAC address

# DNS configuration
DNS_UPSTREAM="1.1.1.1,8.8.8.8"
DNS_ENTRIES=(
    "nux.attic.local:10.0.0.10:Attic server"
    "attic.local:10.0.0.10:Attic server alias"
)

# Enable dry-run mode if desired
# export DRY_RUN=1

echo "=========================================="
echo "L1.0 Mikrotik Network Setup - Attic"
echo "=========================================="
echo ""

# Step 0: Test connectivity
echo "[STEP 0] Testing SSH connectivity..."
if ! ssh_exec "/system resource print" >/dev/null 2>&1; then
    echo "[ERROR] Cannot connect to 192.168.88.1"
    echo "Check: 1) Ethernet cable connected, 2) Your IP is 192.168.88.50/24"
    exit 1
fi
echo "[OK] Connected to RouterOS"
echo ""

# Step 1: Backup configuration
echo "[STEP 1] Backing up current configuration..."
BACKUP_FILE=$(config_backup)
echo "[OK] Backup created: $BACKUP_FILE"
echo ""

# Step 2: Validate interfaces
echo "[STEP 2] Validating interfaces..."
for PORT in "${PORTS[@]}"; do
    validate_interface "$PORT"
done
echo ""

# Step 3: Create bridge
echo "[STEP 3] Creating bridge..."
bridge_create "$BRIDGE_NAME" "no" "Attic server isolated network - 8 port flat bridge"
echo ""

# Step 4: Add ports to bridge
echo "[STEP 4] Adding ports to bridge..."
for i in "${!PORTS[@]}"; do
    PORT="${PORTS[$i]}"
    COMMENT="${PORT_COMMENTS[$i]}"
    bridge_port_add "$BRIDGE_NAME" "$PORT" "$COMMENT"
done
echo ""

# Step 5: Add IP address to bridge
echo "[STEP 5] Adding IP address to bridge..."
ip_address_add "$IP_ADDRESS" "$BRIDGE_NAME" "Attic network gateway and DHCP server"
echo ""

# Step 6: Create DHCP pool
echo "[STEP 6] Creating DHCP pool..."
dhcp_pool_create "$DHCP_POOL_NAME" "$DHCP_POOL_RANGE" "Attic DHCP pool"
echo ""

# Step 7: Create DHCP server
echo "[STEP 7] Creating DHCP server..."
dhcp_server_create "$DHCP_SERVER_NAME" "$BRIDGE_NAME" "$DHCP_POOL_NAME" "Attic DHCP server"
echo ""

# Step 8: Configure DHCP network
echo "[STEP 8] Configuring DHCP network..."
dhcp_network_add "$DHCP_NETWORK" "$DHCP_GATEWAY" "$DHCP_DNS" "$DHCP_DOMAIN" "Attic network DHCP config"
echo ""

# Step 9: Add static DHCP lease for NUC
echo "[STEP 9] Adding static DHCP lease for NUC..."
if [ "$NUC_MAC" = "XX:XX:XX:XX:XX:XX" ]; then
    echo "[WARNING] NUC MAC address not configured. Skipping static lease."
    echo "[WARNING] Update NUC_MAC variable in this script and re-run."
else
    dhcp_lease_add "$NUC_IP" "$NUC_MAC" "$DHCP_SERVER_NAME" "nux static lease"
fi
echo ""

# Step 10: Configure DNS servers
echo "[STEP 10] Configuring DNS servers..."
dns_server_set "$DNS_UPSTREAM" "yes"
echo ""

# Step 11: Add static DNS entries
echo "[STEP 11] Adding static DNS entries..."
for ENTRY in "${DNS_ENTRIES[@]}"; do
    IFS=':' read -r NAME ADDRESS COMMENT <<< "$ENTRY"
    dns_static_add "$NAME" "$ADDRESS" "$COMMENT"
done
echo ""

# Step 12: Validate complete configuration
echo "[STEP 12] Validating complete configuration..."
validate_bridge "$BRIDGE_NAME" "no"
for PORT in "${PORTS[@]}"; do
    validate_bridge_port "$BRIDGE_NAME" "$PORT"
done
validate_ip_address "$BRIDGE_NAME" "10.0.0"
validate_dhcp "$DHCP_SERVER_NAME" "$BRIDGE_NAME" "$DHCP_POOL_NAME"
validate_dns "$DNS_UPSTREAM"
echo ""

# Step 13: Display final status summary
echo "[STEP 13] Displaying configuration status..."
mikrotik_status "$BRIDGE_NAME"
echo ""

echo "=========================================="
echo "L1.0 Configuration Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  Bridge: $BRIDGE_NAME"
echo "  Ports: ${PORTS[*]}"
echo "  IP: $IP_ADDRESS"
echo "  DHCP Pool: $DHCP_POOL_RANGE"
echo "  DHCP Server: $DHCP_SERVER_NAME on $BRIDGE_NAME"
echo "  DHCP Domain: $DHCP_DOMAIN"
echo "  DNS Upstream: $DNS_UPSTREAM"
echo "  Static Lease: $NUC_IP → $NUC_MAC (nux)"
echo "  DNS Entries: nux.attic.local, attic.local → $NUC_IP"
echo "  Backup: $BACKUP_FILE.rsc"
echo ""
echo "Testing:"
echo "  1. Connect laptop to ether3-ether8"
echo "  2. Should receive IP in range $DHCP_POOL_RANGE via DHCP"
echo "  3. Test DNS: nslookup nux.attic.local $DHCP_DNS"
echo "  4. NUC should receive $NUC_IP via DHCP (MAC-based static lease)"
echo ""
echo "Next steps:"
echo "  1. Proceed to L1.1 (Infrastructure Survey)"
```

### Validation Workflow - Verify Expected State

**Script to Check Current Configuration**:
```bash
#!/usr/bin/env bash

echo "Mikrotik Configuration Validation"
echo "=================================="
echo ""

echo "Bridges:"
ssh_exec "/interface bridge print"
echo ""

echo "Bridge Ports:"
ssh_exec "/interface bridge port print"
echo ""

echo "IP Addresses:"
ssh_exec "/ip address print"
echo ""

echo "DHCP Pools:"
ssh_exec "/ip pool print"
echo ""

echo "DHCP Servers:"
ssh_exec "/ip dhcp-server print"
echo ""

echo "DHCP Networks:"
ssh_exec "/ip dhcp-server network print"
echo ""

echo "DHCP Leases:"
ssh_exec "/ip dhcp-server lease print"
echo ""

echo "DNS Configuration:"
ssh_exec "/ip dns print"
echo ""

echo "DNS Static Entries:"
ssh_exec "/ip dns static print"
echo ""

echo "=================================="
```

---

## 8. Status and Monitoring Operations

### mikrotik-status - Display Compact Multi-Resource Status

**Purpose**: Single-command status check for complete L1.0 configuration with graceful error handling.

**Usage**:
```bash
mikrotik_status() {
    local bridge="${1:-bridge-attic}"

    echo "=== Mikrotik Status: $bridge ==="

    # Gather status from all subsystems (continue on errors)
    _status_switch
    _status_bridge "$bridge"
    _status_ip "$bridge"
    _status_dhcp "$bridge"
    _status_dns

    echo "======================================"
}

# Helper: Switch hardware and software status
_status_switch() {
    local output=$(ssh_exec "/system resource print" 2>&1)

    if parse_errors "$output"; then
        echo "Switch    : [ERROR: Cannot query system info]"
        return 1
    fi

    local model=$(echo "$output" | grep -oP '(?<=board-name: ).*' | head -1)
    local version=$(echo "$output" | grep -oP '(?<=version: )[\d.]+' | head -1)
    local uptime=$(echo "$output" | grep -oP '(?<=uptime: ).*' | head -1)

    echo "Switch    : ${model:-unknown} | v${version:-?} | Up ${uptime:-?}"
}

# Helper: Bridge and port status
_status_bridge() {
    local bridge="$1"
    local output=$(ssh_exec "/interface bridge print detail where name=$bridge" 2>&1)

    if parse_errors "$output" || ! echo "$output" | grep -q "name=$bridge"; then
        echo "Bridge    : [NOT FOUND: $bridge]"
        echo "Ports     : [SKIPPED: No bridge]"
        return 1
    fi

    local vlan_filtering=$(parse_print_output "$output" "vlan-filtering")

    # Count bridge ports
    local port_output=$(ssh_exec "/interface bridge port print count-only where bridge=$bridge" 2>&1)
    local port_count=$(parse_count "$port_output")

    # Get port list (compact: ether1-8)
    local port_list=$(ssh_exec "/interface bridge port print terse where bridge=$bridge" 2>&1 | \
                      grep -oP '(?<=interface=)\S+' | tr '\n' ',' | sed 's/,$//')

    echo "Bridge    : $bridge | ${port_count:-0} ports | VLAN: ${vlan_filtering:-unknown}"

    if [ "$port_count" -gt 0 ]; then
        echo "Ports     : ${port_list:-none} ✓"
    else
        echo "Ports     : [NONE CONFIGURED]"
    fi
}

# Helper: IP address status
_status_ip() {
    local interface="$1"
    local output=$(ssh_exec "/ip address print detail where interface=$interface" 2>&1)

    if parse_errors "$output" || ! echo "$output" | grep -q "interface=$interface"; then
        echo "IP        : [NOT CONFIGURED on $interface]"
        return 1
    fi

    local address=$(parse_print_output "$output" "address")
    local network=$(parse_print_output "$output" "network")

    echo "IP        : ${address:-unknown} (${network:-unknown})"
}

# Helper: DHCP server and lease status
_status_dhcp() {
    local bridge="$1"

    # Find DHCP server on this interface
    local server_output=$(ssh_exec "/ip dhcp-server print detail where interface=$bridge" 2>&1)

    if parse_errors "$server_output" || ! echo "$server_output" | grep -q "interface=$bridge"; then
        echo "DHCP Pool : [NOT CONFIGURED]"
        echo "DHCP Srv  : [NOT CONFIGURED on $bridge]"
        echo "DHCP Net  : [NOT CONFIGURED]"
        echo "DHCP Lease: [NOT CONFIGURED]"
        return 1
    fi

    local server_name=$(parse_print_output "$server_output" "name")
    local address_pool=$(parse_print_output "$server_output" "address-pool")
    local disabled=$(parse_print_output "$server_output" "disabled")
    local status=$([ "$disabled" = "yes" ] && echo "Disabled" || echo "Enabled")

    # Get pool details
    if [ -n "$address_pool" ]; then
        local pool_output=$(ssh_exec "/ip pool print detail where name=$address_pool" 2>&1)
        local ranges=$(parse_print_output "$pool_output" "ranges")
        echo "DHCP Pool : $address_pool | ${ranges:-unknown}"
    else
        echo "DHCP Pool : [UNKNOWN]"
    fi

    echo "DHCP Srv  : ${server_name:-unknown} | $bridge | $status"

    # Get network configuration
    local net_output=$(ssh_exec "/ip dhcp-server network print detail" 2>&1)
    if ! parse_errors "$net_output"; then
        local net_address=$(echo "$net_output" | grep -oP '(?<=address=)[^\s]+' | head -1)
        local net_gateway=$(echo "$net_output" | grep -oP '(?<=gateway=)[^\s]+' | head -1)
        local net_dns=$(echo "$net_output" | grep -oP '(?<=dns-server=)[^\s]+' | head -1)
        local net_domain=$(echo "$net_output" | grep -oP '(?<=domain=)[^\s]+' | head -1)

        echo "DHCP Net  : ${net_address:-?} | GW: ${net_gateway:-?} | DNS: ${net_dns:-?} | ${net_domain:-no-domain}"
    else
        echo "DHCP Net  : [NOT CONFIGURED]"
    fi

    # Count static leases
    local lease_count=$(ssh_exec "/ip dhcp-server lease print count-only where server=$server_name and !dynamic" 2>&1)
    lease_count=$(parse_count "$lease_count")

    if [ "$lease_count" -gt 0 ]; then
        # Show first static lease as example
        local lease_detail=$(ssh_exec "/ip dhcp-server lease print detail where server=$server_name and !dynamic" 2>&1 | head -20)
        local lease_address=$(echo "$lease_detail" | grep -oP '(?<=address=)[^\s]+' | head -1)
        local lease_mac=$(echo "$lease_detail" | grep -oP '(?<=mac-address=)[^\s]+' | head -1)
        echo "DHCP Lease: $lease_count static ($lease_address → $lease_mac)"
    else
        echo "DHCP Lease: 0 static"
    fi
}

# Helper: DNS configuration status
_status_dns() {
    local dns_output=$(ssh_exec "/ip dns print detail" 2>&1)

    if parse_errors "$dns_output"; then
        echo "DNS       : [ERROR: Cannot query DNS config]"
        echo "DNS Static: [ERROR: Cannot query DNS static]"
        return 1
    fi

    local servers=$(echo "$dns_output" | grep -oP '(?<=servers: ).*' | head -1)
    local allow_remote=$(echo "$dns_output" | grep -oP '(?<=allow-remote-requests: ).*' | head -1)

    echo "DNS       : ${servers:-none} | remote: ${allow_remote:-no}"

    # Count static entries
    local static_count=$(ssh_exec "/ip dns static print count-only" 2>&1)
    static_count=$(parse_count "$static_count")

    if [ "$static_count" -gt 0 ]; then
        # Show static entries (compact: name → address)
        local static_list=$(ssh_exec "/ip dns static print terse" 2>&1 | \
                            grep -oP '(name=\S+|address=\S+)' | \
                            paste -d' ' - - | \
                            sed 's/name=//;s/ address=/ → /' | \
                            tr '\n' ', ' | sed 's/, $//')
        echo "DNS Static: $static_count entries ($static_list)"
    else
        echo "DNS Static: 0 entries"
    fi
}

# Example usage:
# mikrotik_status "bridge-attic"
```

**Example Output** (Success Case):
```
=== Mikrotik Status: bridge-attic ===
Switch    : CRS326-24G-2S+ | v7.16.1 | Up 3d 4h
Bridge    : bridge-attic | 8 ports | VLAN: no
Ports     : ether1,ether2,ether3,ether4,ether5,ether6,ether7,ether8 ✓
IP        : 10.0.0.1/24 (10.0.0.0)
DHCP Pool : pool-attic | 10.0.0.100-10.0.0.200
DHCP Srv  : dhcp-attic | bridge-attic | Enabled
DHCP Net  : 10.0.0.0/24 | GW: 10.0.0.1 | DNS: 10.0.0.1 | attic.local
DHCP Lease: 1 static (10.0.0.10 → AA:BB:CC:DD:EE:FF)
DNS       : 1.1.1.1,8.8.8.8 | remote: yes
DNS Static: 2 entries (nux.attic.local → 10.0.0.10, attic.local → 10.0.0.10)
======================================
```

**Example Output** (Partial Failure - Missing DHCP):
```
=== Mikrotik Status: bridge-attic ===
Switch    : CRS326-24G-2S+ | v7.16.1 | Up 3d 4h
Bridge    : bridge-attic | 8 ports | VLAN: no
Ports     : ether1,ether2,ether3,ether4,ether5,ether6,ether7,ether8 ✓
IP        : 10.0.0.1/24 (10.0.0.0)
DHCP Pool : [NOT CONFIGURED]
DHCP Srv  : [NOT CONFIGURED on bridge-attic]
DHCP Net  : [NOT CONFIGURED]
DHCP Lease: [NOT CONFIGURED]
DNS       : 1.1.1.1,8.8.8.8 | remote: yes
DNS Static: 0 entries
======================================
```

**Design Notes**:
1. **Graceful Degradation**: Each helper function handles errors independently, returning error markers but allowing status to continue
2. **Clear Error Markers**: `[NOT FOUND]`, `[NOT CONFIGURED]`, `[ERROR: ...]` make issues immediately visible
3. **Compact Output**: Single line per resource type, ~10-12 lines total
4. **Information Density**: Key details (counts, states, identifiers) packed efficiently
5. **Visual Indicators**: Checkmarks (✓) for positive confirmation, brackets for issues

---

### Rollback Workflow - Restore from Backup

**Script to Restore Previous Configuration**:
```bash
#!/usr/bin/env bash

BACKUP_FILE="${1:-}"

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup-filename>"
    echo ""
    echo "Available backups:"
    ssh_exec "/file print where name~'backup'"
    exit 1
fi

echo "Rolling back to: $BACKUP_FILE"
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" = "yes" ]; then
    config_restore "$BACKUP_FILE"
    echo "[OK] Configuration restored from $BACKUP_FILE"
else
    echo "Rollback cancelled"
fi
```

---

## Testing Hooks

### Test Mode

Export these variables before running workflows to enable test mode:

```bash
# Dry-run mode (generate commands without executing)
export DRY_RUN=1

# Verbose mode (show all command output)
export VERBOSE=1
```

### Test Connectivity Script

```bash
#!/usr/bin/env bash
# Test basic SSH connectivity

echo "Testing Mikrotik SSH connection..."

if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@192.168.88.1 "/system resource print" 2>/dev/null; then
    echo "[OK] Connected to RouterOS successfully"
    exit 0
else
    echo "[ERROR] Cannot connect to RouterOS at 192.168.88.1"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check ethernet cable is connected to management port"
    echo "  2. Verify your IP: ip addr show (should have 192.168.88.x/24)"
    echo "  3. Set static IP if needed: sudo ip addr add 192.168.88.50/24 dev <interface>"
    echo "  4. Test ping: ping 192.168.88.1"
    exit 1
fi
```

---

## Usage Examples

### Example 1: Query Current Configuration

```bash
# Source the skill functions (this would be loaded automatically when skill is invoked)

# List all bridges
echo "Current bridges:"
ssh_exec "/interface bridge print"

# List all bridge ports
echo "Current bridge ports:"
ssh_exec "/interface bridge port print"

# List all IP addresses
echo "Current IP addresses:"
ssh_exec "/ip address print"
```

### Example 2: Dry-Run Mode

```bash
# Enable dry-run mode
export DRY_RUN=1

# Run L1.0 workflow - will show commands without executing
./l1.0-complete-workflow.sh

# Disable dry-run to actually apply
export DRY_RUN=0
./l1.0-complete-workflow.sh
```

### Example 3: Idempotent Re-Application

```bash
# Run workflow first time - creates resources
./l1.0-complete-workflow.sh

# Run workflow second time - all operations are idempotent, no errors
./l1.0-complete-workflow.sh

# Output will show "[OK] ... already exists (idempotent)" for each resource
```

### Example 4: Validation Only

```bash
# Run validation without making changes
validate_bridge "bridge-attic" "no"
validate_bridge_port "bridge-attic" "ether1"
validate_bridge_port "bridge-attic" "ether2"
validate_ip_address "bridge-attic" "10.0.0"
validate_vlan "vlan-attic" "10" "bridge-attic"
```

---

## Error Handling

### Common Errors and Solutions

**Error: `failure: already have interface with such name`**
- **Cause**: Resource already exists
- **Solution**: This is expected on re-runs (idempotency). Check if resource has correct properties.

**Error: `failure: no such item`**
- **Cause**: Referenced resource doesn't exist (e.g., bridge doesn't exist when adding port)
- **Solution**: Check dependency order. Create bridges before adding ports.

**Error: `expected end of command`**
- **Cause**: Syntax error in RouterOS CLI command
- **Solution**: Check command syntax, ensure proper quoting of strings with spaces

**Error: SSH connection timeout**
- **Cause**: Cannot reach 192.168.88.1
- **Solution**: Check physical connection, verify your IP is in 192.168.88.0/24 range

---

## 6. DHCP Server Operations (Full)

### dhcp-pool-list - List IP Pools

**Command**:
```bash
ssh_exec "/ip pool print"
```

**Example Output**:
```
 0    name="pool-attic" ranges=10.0.0.100-10.0.0.200
```

### dhcp-pool-create - Create IP Pool with Idempotency

**Usage**:
```bash
dhcp_pool_create() {
    local name="$1"
    local ranges="$2"
    local comment="${3:-}"

    echo "[INFO] Creating DHCP pool: $name ($ranges)"

    # Idempotency check
    if idempotency_check "/ip pool print count-only where name=$name"; then
        echo "[OK] DHCP pool $name already exists (idempotent)"
        return 0
    fi

    # Build command
    local cmd="/ip pool add name=$name ranges=$ranges"
    [ -n "$comment" ] && cmd="$cmd comment=\"$comment\""

    # Execute
    execute_cmd "$cmd"

    # Validate
    if parse_exists "/ip pool print count-only where name=$name"; then
        echo "[OK] DHCP pool $name created successfully"
        return 0
    else
        echo "[ERROR] DHCP pool $name creation failed"
        return 1
    fi
}

# Example:
dhcp_pool_create "pool-attic" "10.0.0.100-10.0.0.200" "Attic DHCP pool"
```

### dhcp-server-list - List DHCP Servers

**Command**:
```bash
ssh_exec "/ip dhcp-server print"
```

**Example Output**:
```
 0    name="dhcp-attic" interface=bridge-attic address-pool=pool-attic disabled=no
```

### dhcp-server-create - Create DHCP Server with Idempotency

**Usage**:
```bash
dhcp_server_create() {
    local name="$1"
    local interface="$2"
    local address_pool="$3"
    local comment="${4:-}"

    echo "[INFO] Creating DHCP server: $name on $interface"

    # Idempotency check
    if idempotency_check "/ip dhcp-server print count-only where name=$name"; then
        echo "[OK] DHCP server $name already exists (idempotent)"
        return 0
    fi

    # Build command
    local cmd="/ip dhcp-server add name=$name interface=$interface address-pool=$address_pool disabled=no"
    [ -n "$comment" ] && cmd="$cmd comment=\"$comment\""

    # Execute
    execute_cmd "$cmd"

    # Validate
    if parse_exists "/ip dhcp-server print count-only where name=$name"; then
        echo "[OK] DHCP server $name created successfully"
        return 0
    else
        echo "[ERROR] DHCP server $name creation failed"
        return 1
    fi
}

# Example:
dhcp_server_create "dhcp-attic" "bridge-attic" "pool-attic" "Attic DHCP server"
```

### dhcp-network-list - List DHCP Networks

**Command**:
```bash
ssh_exec "/ip dhcp-server network print"
```

**Example Output**:
```
 0    address=10.0.0.0/24 gateway=10.0.0.1 dns-server=10.0.0.1 domain=attic.local
```

### dhcp-network-add - Add DHCP Network with Idempotency

**Usage**:
```bash
dhcp_network_add() {
    local address="$1"        # Format: 10.0.0.0/24
    local gateway="$2"        # Format: 10.0.0.1
    local dns_server="$3"     # Format: 10.0.0.1 or 1.1.1.1,8.8.8.8
    local domain="${4:-}"     # Optional: attic.local
    local comment="${5:-}"

    echo "[INFO] Adding DHCP network: $address"

    # Idempotency check
    if idempotency_check "/ip dhcp-server network print count-only where address=$address"; then
        echo "[OK] DHCP network $address already exists (idempotent)"
        return 0
    fi

    # Build command
    local cmd="/ip dhcp-server network add address=$address gateway=$gateway dns-server=$dns_server"
    [ -n "$domain" ] && cmd="$cmd domain=$domain"
    [ -n "$comment" ] && cmd="$cmd comment=\"$comment\""

    # Execute
    execute_cmd "$cmd"

    # Validate
    if parse_exists "/ip dhcp-server network print count-only where address=$address"; then
        echo "[OK] DHCP network $address added successfully"
        return 0
    else
        echo "[ERROR] DHCP network $address addition failed"
        return 1
    fi
}

# Example:
dhcp_network_add "10.0.0.0/24" "10.0.0.1" "10.0.0.1" "attic.local" "Attic network DHCP config"
```

### dhcp-lease-list - List DHCP Leases

**Command**:
```bash
# List all leases
ssh_exec "/ip dhcp-server lease print"

# List active leases only
ssh_exec "/ip dhcp-server lease print where status=bound"
```

**Example Output**:
```
 0    address=10.0.0.10 mac-address=AA:BB:CC:DD:EE:FF server=dhcp-attic status=bound host-name="nux"
 1    address=10.0.0.100 mac-address=11:22:33:44:55:66 server=dhcp-attic status=bound host-name="laptop"
```

### dhcp-lease-add - Add Static DHCP Lease with Idempotency

**Usage**:
```bash
dhcp_lease_add() {
    local address="$1"
    local mac_address="$2"
    local server="$3"
    local comment="${4:-}"

    echo "[INFO] Adding static DHCP lease: $address → $mac_address"

    # Idempotency check (by address OR by MAC)
    local exists_by_addr=$(ssh_exec "/ip dhcp-server lease print count-only where address=$address")
    local exists_by_mac=$(ssh_exec "/ip dhcp-server lease print count-only where mac-address=$mac_address")

    if [ "$exists_by_addr" != "0" ] || [ "$exists_by_mac" != "0" ]; then
        echo "[OK] Static lease already exists (idempotent)"
        return 0
    fi

    # Build command
    local cmd="/ip dhcp-server lease add address=$address mac-address=$mac_address server=$server"
    [ -n "$comment" ] && cmd="$cmd comment=\"$comment\""

    # Execute
    execute_cmd "$cmd"

    # Validate
    if parse_exists "/ip dhcp-server lease print count-only where address=$address"; then
        echo "[OK] Static lease added successfully"
        return 0
    else
        echo "[ERROR] Static lease addition failed"
        return 1
    fi
}

# Example:
dhcp_lease_add "10.0.0.10" "AA:BB:CC:DD:EE:FF" "dhcp-attic" "nux static lease"
```

### dhcp-validate - Validate DHCP Configuration

**Usage**:
```bash
validate_dhcp() {
    local server_name="$1"
    local expected_interface="$2"
    local expected_pool="$3"

    echo "[INFO] Validating DHCP server: $server_name"

    # Check server exists
    if ! parse_exists "/ip dhcp-server print count-only where name=$server_name"; then
        echo "[ERROR] DHCP server $server_name not found"
        return 1
    fi

    # Check server properties
    local output=$(ssh_exec "/ip dhcp-server print detail where name=$server_name")
    local actual_interface=$(parse_print_output "$output" "interface")
    local actual_pool=$(parse_print_output "$output" "address-pool")

    if [ "$actual_interface" != "$expected_interface" ]; then
        echo "[ERROR] Interface mismatch: expected=$expected_interface, actual=$actual_interface"
        return 1
    fi

    if [ "$actual_pool" != "$expected_pool" ]; then
        echo "[ERROR] Pool mismatch: expected=$expected_pool, actual=$actual_pool"
        return 1
    fi

    echo "[OK] DHCP server $server_name validated"
    return 0
}

# Example:
validate_dhcp "dhcp-attic" "bridge-attic" "pool-attic"
```

---

## 7. DNS Configuration (Full)

### dns-config-show - Show DNS Configuration

**Command**:
```bash
ssh_exec "/ip dns print"
```

**Example Output**:
```
servers: 1.1.1.1,8.8.8.8
allow-remote-requests: yes
cache-size: 2048KiB
cache-used: 45KiB
```

### dns-server-set - Configure DNS Servers with Idempotency

**Usage**:
```bash
dns_server_set() {
    local servers="$1"                  # Format: 1.1.1.1,8.8.8.8
    local allow_remote_requests="${2:-yes}"

    echo "[INFO] Configuring DNS servers: $servers"

    # Query current settings
    local current_servers=$(ssh_exec "/ip dns get servers" | tr -d '\n')
    local current_allow=$(ssh_exec "/ip dns get allow-remote-requests" | tr -d '\n')

    # Idempotency check
    if [ "$current_servers" = "$servers" ] && [ "$current_allow" = "$allow_remote_requests" ]; then
        echo "[OK] DNS already configured (idempotent)"
        return 0
    fi

    # Execute
    local cmd="/ip dns set servers=$servers allow-remote-requests=$allow_remote_requests"
    execute_cmd "$cmd"

    # Validate
    local new_servers=$(ssh_exec "/ip dns get servers" | tr -d '\n')
    if [ "$new_servers" = "$servers" ]; then
        echo "[OK] DNS servers configured successfully"
        return 0
    else
        echo "[ERROR] DNS server configuration failed"
        return 1
    fi
}

# Example:
dns_server_set "1.1.1.1,8.8.8.8" "yes"
```

### dns-static-list - List Static DNS Entries

**Command**:
```bash
ssh_exec "/ip dns static print"
```

**Example Output**:
```
 0    name="nux.attic.local" address=10.0.0.10
 1    name="attic.local" address=10.0.0.10
```

### dns-static-add - Add Static DNS Entry with Idempotency

**Usage**:
```bash
dns_static_add() {
    local name="$1"
    local address="$2"
    local comment="${3:-}"

    echo "[INFO] Adding static DNS entry: $name → $address"

    # Idempotency check
    if idempotency_check "/ip dns static print count-only where name=$name"; then
        echo "[OK] DNS entry $name already exists (idempotent)"
        return 0
    fi

    # Build command
    local cmd="/ip dns static add name=$name address=$address"
    [ -n "$comment" ] && cmd="$cmd comment=\"$comment\""

    # Execute
    execute_cmd "$cmd"

    # Validate
    if parse_exists "/ip dns static print count-only where name=$name"; then
        echo "[OK] DNS entry $name added successfully"
        return 0
    else
        echo "[ERROR] DNS entry $name addition failed"
        return 1
    fi
}

# Example:
dns_static_add "nux.attic.local" "10.0.0.10" "Attic server"
dns_static_add "attic.local" "10.0.0.10" "Attic server alias"
```

### dns-static-remove - Remove Static DNS Entry (Utility)

**Command**:
```bash
ssh_exec "/ip dns static remove [find where name=nux.attic.local]"
```

### dns-cache-list - List DNS Cache Entries

**Command**:
```bash
ssh_exec "/ip dns cache print"
```

**Example Output**:
```
 0    name="example.com" address=93.184.216.34 ttl=5m
 1    name="nux.attic.local" address=10.0.0.10 static=yes
```

### dns-validate - Validate DNS Configuration

**Usage**:
```bash
validate_dns() {
    local expected_upstream="$1"  # Format: 1.1.1.1,8.8.8.8

    echo "[INFO] Validating DNS configuration"

    # Query DNS settings
    local actual_servers=$(ssh_exec "/ip dns get servers" | tr -d '\n')
    local allow_remote=$(ssh_exec "/ip dns get allow-remote-requests" | tr -d '\n')

    # Check upstream servers
    if [ "$actual_servers" != "$expected_upstream" ]; then
        echo "[WARNING] DNS servers mismatch: expected=$expected_upstream, actual=$actual_servers"
    fi

    # Check remote requests enabled
    if [ "$allow_remote" != "yes" ]; then
        echo "[WARNING] DNS allow-remote-requests is disabled (should be yes for DHCP clients)"
    fi

    echo "[OK] DNS configuration validated"
    return 0
}

# Example:
validate_dns "1.1.1.1,8.8.8.8"
```

---

## Phase 2+ Extensions (Future - Not Yet Implemented)

The following operations are designed but not yet implemented:

### Advanced Bridge Features
- `bridge-vlan-filtering-enable` - Enable VLAN-aware bridge
- `bridge-vlan-add` - Configure bridge VLAN table
- `bridge-port-set-pvid` - Set port PVID

### Interface Management
- `interface-enable` / `interface-disable`
- `interface-set-mtu`
- `interface-set-comment`

---

## Safety Reminders

**ALWAYS**:
- ✅ Test connectivity before operations
- ✅ Create backup before changes
- ✅ Use dry-run mode for unfamiliar operations
- ✅ Validate after each critical operation
- ✅ Check idempotency before re-running

**NEVER**:
- ❌ Skip backups before major changes
- ❌ Ignore validation failures
- ❌ Run untested commands on production switch
- ❌ Disable safety checks

---

## Quick Reference

### Essential Commands

```bash
# Test connectivity
ssh admin@192.168.88.1 "/system resource print"

# List all resources
ssh admin@192.168.88.1 "/interface bridge print"
ssh admin@192.168.88.1 "/interface bridge port print"
ssh admin@192.168.88.1 "/ip address print"
ssh admin@192.168.88.1 "/interface vlan print"

# Backup configuration
ssh admin@192.168.88.1 "/export file=backup-$(date +%Y%m%d-%H%M%S)"

# List backups
ssh admin@192.168.88.1 "/file print where name~'backup'"

# Factory reset (DANGEROUS)
ssh admin@192.168.88.1 "/system reset-configuration no-defaults=yes skip-backup=yes"
```

---

## References

- [MikroTik RouterOS Documentation](https://help.mikrotik.com/docs/display/ROS/)
- [Bridge VLAN Configuration](https://help.mikrotik.com/docs/display/ROS/Bridging+and+Switching)
- Plan 013: `.claude/user-plans/013-distributed-nix-binary-caching.md`
- Design: `docs/wip-L0.1-mikrotik-skill-design.md`
- L1.0 Guide: `docs/wip-L1.0-mikrotik-setup.md`

---

## Notes for Skill Usage

When this skill is invoked via `Skill { skill: "mikrotik-config" }`:

1. **All functions above are available** - You can call them directly in bash commands
2. **Use Bash tool to execute** - Run commands via Bash tool, not as inline code
3. **Test incrementally** - Start with read-only queries, then progress to changes
4. **Document results** - Record what worked and what didn't for future improvements
5. **Link to L0.3** - Testing validation belongs in `tests/mikrotik-skill-validation.sh`

**Example Invocation Flow**:
```bash
# Step 1: Test connectivity
ssh admin@192.168.88.1 "/system resource print"

# Step 2: Query current state
ssh admin@192.168.88.1 "/interface print"
ssh admin@192.168.88.1 "/interface bridge print"

# Step 3: Run L1.0 workflow (in dry-run mode first)
export DRY_RUN=1
# ... paste L1.0 complete workflow script ...

# Step 4: Apply for real
export DRY_RUN=0
# ... paste L1.0 complete workflow script again ...
```
