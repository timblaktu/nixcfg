# Mikrotik Management Skill - Test Cases

**Skill Version**: 2.2.0
**Last Updated**: 2026-06-05
**Test Environment**: Mikrotik CRS326-24G-2S+ at factory defaults

---

## Test Environment Prerequisites

### Hardware Setup
- [ ] Mikrotik CRS326-24G-2S+ switch powered on
- [ ] Direct ethernet cable from laptop to Mikrotik management port (ether1)
- [ ] Switch at factory defaults (IP: 192.168.88.1, User: admin, Password: blank)

### Laptop Configuration
- [ ] Static IP configured: 192.168.88.50/24
- [ ] No default gateway needed (direct connection)
- [ ] SSH client available (`ssh` command)

### Verification Commands
```bash
# Verify laptop network config
ip addr show | grep 192.168.88.50

# Test ping to switch
ping -c 3 192.168.88.1

# Test SSH connectivity (password is blank - just press Enter)
ssh admin@192.168.88.1 "/system resource print"
```

---

## Test Suite

### Test 1: Skill Triggering

**Purpose**: Verify the skill activates correctly with explicit and natural language triggers.

**Test Steps**:
1. [ ] Start new Claude Code session in nixcfg directory
2. [ ] Try explicit invocation: `/mikrotik-management`
   - Expected: Skill loads, shows RouterOS management capabilities
3. [ ] Try natural trigger: "I need to configure my Mikrotik switch"
   - Expected: Skill activates automatically
4. [ ] Try out-of-scope query: "What is the weather today?"
   - Expected: Skill does NOT activate (no false positives)

**Pass Criteria**: Skill triggers on relevant queries only, no false activations

---

### Test 2: Query Operations (Read-Only)

**Purpose**: Verify query operations retrieve accurate data without modifying state.

**Test Steps**:
1. [ ] Invoke skill: `/mikrotik-management`
2. [ ] Request: "List all VLANs on the switch"
   - Expected: SSH command generated, output parsed, empty list (factory defaults)
3. [ ] Request: "List all bridges"
   - Expected: Returns factory bridge if present, or empty list
4. [ ] Request: "Show all interface IP addresses"
   - Expected: Returns default 192.168.88.1/24 on bridge/ether1
5. [ ] Request: "List all bridge ports"
   - Expected: Returns factory port assignments (if any)

**Verification**:
```bash
# Manually verify no changes made
ssh admin@192.168.88.1 "/interface vlan print"
ssh admin@192.168.88.1 "/interface bridge print"
```

**Pass Criteria**: All queries return accurate data, no configuration changes detected

---

### Test 3: Dry-Run Mode

**Purpose**: Verify dry-run generates correct commands without applying them.

**Test Steps**:
1. [ ] Request: "Show me the commands to create a bridge named 'test-bridge'"
   - Expected: Displays `/interface bridge add name=test-bridge` (does NOT execute)
2. [ ] Request: "Generate commands for VLAN 100 on ether2"
   - Expected: Displays `/interface vlan add interface=ether2 vlan-id=100 name=vlan100` (does NOT execute)
3. [ ] Request: "What commands would add IP 10.0.0.1/24 to test-bridge?"
   - Expected: Displays `/ip address add address=10.0.0.1/24 interface=test-bridge` (does NOT execute)

**Verification**:
```bash
# Verify nothing actually created
ssh admin@192.168.88.1 "/interface bridge print"
ssh admin@192.168.88.1 "/interface vlan print"
ssh admin@192.168.88.1 "/ip address print"
```

**Pass Criteria**: Commands generated correctly, no state changes on switch

---

### Test 4: Configuration Application

**Purpose**: Verify skill can successfully apply configurations.

**Test Steps**:
1. [ ] Request: "Create a bridge named 'test-bridge' on the switch"
   - Expected: Executes command, confirms success
2. [ ] Verify bridge created:
   ```bash
   ssh admin@192.168.88.1 "/interface bridge print"
   # Should show test-bridge
   ```
3. [ ] Request: "Add ether3 and ether4 to test-bridge"
   - Expected: Executes port assignment commands
4. [ ] Verify ports assigned:
   ```bash
   ssh admin@192.168.88.1 "/interface bridge port print"
   # Should show ether3 and ether4 with bridge=test-bridge
   ```
5. [ ] Request: "Assign IP 10.0.0.1/24 to test-bridge"
   - Expected: Executes IP address command
6. [ ] Verify IP assigned:
   ```bash
   ssh admin@192.168.88.1 "/ip address print where interface=test-bridge"
   # Should show 10.0.0.1/24
   ```
7. [ ] Request: "Create VLAN 100 interface on test-bridge"
   - Expected: Creates vlan100 interface
8. [ ] Verify VLAN created:
   ```bash
   ssh admin@192.168.88.1 "/interface vlan print"
   # Should show vlan100
   ```

**Pass Criteria**: All configurations applied successfully, verified via manual queries

---

### Test 5: Idempotency

**Purpose**: Verify applying the same configuration twice doesn't cause errors or duplicates.

**Test Steps**:
1. [ ] Request: "Create bridge named 'test-bridge-2'"
   - Expected: Success
2. [ ] Request again: "Create bridge named 'test-bridge-2'"
   - Expected: Skill detects existing bridge, no duplicate created (or graceful error)
3. [ ] Verify only one test-bridge-2 exists:
   ```bash
   ssh admin@192.168.88.1 "/interface bridge print" | grep test-bridge-2 | wc -l
   # Should return 1
   ```
4. [ ] Request: "Add ether5 to test-bridge-2"
   - Expected: Success
5. [ ] Request again: "Add ether5 to test-bridge-2"
   - Expected: Skill detects existing assignment, no duplicate (or graceful error)
6. [ ] Verify only one port assignment:
   ```bash
   ssh admin@192.168.88.1 "/interface bridge port print where bridge=test-bridge-2" | grep ether5 | wc -l
   # Should return 1
   ```

**Pass Criteria**: No duplicates created, errors handled gracefully

---

### Test 6: Configuration Validation

**Purpose**: Verify skill validates applied configuration matches intent.

**Test Steps**:
1. [ ] Request: "Create bridge 'test-val' with ports ether6 and ether7, assign IP 10.10.10.1/24"
   - Expected: Multi-step operation executes
2. [ ] Request: "Validate the test-val bridge configuration"
   - Expected: Skill queries and confirms:
     - Bridge exists with name 'test-val'
     - Ports ether6 and ether7 are members
     - IP 10.10.10.1/24 is assigned
3. [ ] Manually introduce drift:
   ```bash
   ssh admin@192.168.88.1 "/interface bridge port remove [find where interface=ether7]"
   ```
4. [ ] Request: "Validate the test-val bridge configuration again"
   - Expected: Skill detects ether7 is missing, reports drift

**Pass Criteria**: Validation correctly identifies matching and drifted configurations

---

### Test 7: Error Handling

**Purpose**: Verify skill handles invalid operations gracefully.

**Test Steps**:
1. [ ] Request: "Create VLAN with ID 5000" (invalid - max is 4094)
   - Expected: Skill validates VLAN ID range, shows error before SSH
2. [ ] Request: "Add non-existent interface ether99 to bridge"
   - Expected: Skill detects invalid interface or RouterOS returns error
3. [ ] Request: "Assign duplicate IP 192.168.88.1/24 to bridge" (conflicts with default)
   - Expected: RouterOS error caught, reported clearly
4. [ ] Request: "Remove system-critical interface (ether1 with mgmt IP)"
   - Expected: Skill warns about removing management interface (safety check)

**Pass Criteria**: All errors caught and reported with helpful messages

---

### Test 8: Cleanup

**Purpose**: Verify all test resources can be removed cleanly.

**Test Steps**:
1. [ ] Request: "List all resources starting with 'test-'"
   - Expected: Shows all test bridges, VLANs, IPs created during testing
2. [ ] Request: "Remove all resources starting with 'test-'"
   - Expected: Skill generates cleanup commands:
     ```
     /interface vlan remove [find where name~"test-"]
     /ip address remove [find where interface~"test-"]
     /interface bridge port remove [find where bridge~"test-"]
     /interface bridge remove [find where name~"test-"]
     ```
3. [ ] Execute cleanup
4. [ ] Verify factory state restored:
   ```bash
   ssh admin@192.168.88.1 "/interface bridge print"
   ssh admin@192.168.88.1 "/interface vlan print"
   ssh admin@192.168.88.1 "/ip address print"
   # Should only show default configuration
   ```

**Pass Criteria**: All test resources removed, factory defaults restored

---

### Test 9: DHCP Operations

**Purpose**: Verify DHCP pool, server, network, and lease management.

**Prerequisites**: Bridge `bridge-attic` with IP `10.0.0.1/24` must exist (deploy L1.0 or complete Tests 2-4 first).

**Test Steps**:
1. [ ] Request: "Create a DHCP pool named pool-attic with range 10.0.0.100-10.0.0.200"
   - Expected: Pool created via `/ip pool add`
2. [ ] Request: "Create a DHCP server named dhcp-attic on bridge-attic using pool-attic"
   - Expected: Server created via `/ip dhcp-server add`
3. [ ] Request: "Configure DHCP network 10.0.0.0/24 with gateway 10.0.0.1, DNS 10.0.0.1, domain attic.local"
   - Expected: Network params configured via `/ip dhcp-server network add`
4. [ ] Request: "Add a static DHCP lease for 10.0.0.10 with MAC XX:XX:XX:XX:XX:XX"
   - Expected: Static lease created via `/ip dhcp-server lease add`
5. [ ] Request: "List all DHCP leases"
   - Expected: Shows static lease and any active dynamic leases

**Verification**:
```bash
ssh admin@192.168.88.1 "/ip pool print"
ssh admin@192.168.88.1 "/ip dhcp-server print"
ssh admin@192.168.88.1 "/ip dhcp-server network print"
ssh admin@192.168.88.1 "/ip dhcp-server lease print"
```

**Pass Criteria**: All DHCP components created correctly, static lease visible

---

### Test 10: DNS Operations

**Purpose**: Verify DNS upstream configuration and static entry management.

**Test Steps**:
1. [ ] Request: "Configure upstream DNS servers 1.1.1.1 and 8.8.8.8 with remote requests enabled"
   - Expected: DNS servers set via `/ip dns set`
2. [ ] Request: "Add DNS static entry nux.attic.local pointing to 10.0.0.10"
   - Expected: Static entry created via `/ip dns static add`
3. [ ] Request: "Show DNS configuration"
   - Expected: Displays upstream servers, allow-remote-requests, cache status
4. [ ] Request: "List DNS static entries"
   - Expected: Shows nux.attic.local entry
5. [ ] Request: "Flush DNS cache"
   - Expected: Cache flushed via `/ip dns cache flush`

**Verification**:
```bash
ssh admin@192.168.88.1 "/ip dns print"
ssh admin@192.168.88.1 "/ip dns static print"
```

**Pass Criteria**: DNS configured correctly, static entries resolve, cache operations work

---

### Test 11: Configuration State Management

**Purpose**: Verify backup, export, and state inspection operations.

**Test Steps**:
1. [ ] Request: "Create a binary backup of the current configuration"
   - Expected: Backup created via `/system backup save`, file stored on device
2. [ ] Request: "Export the current configuration as text"
   - Expected: Text export via `/export`, output displayed or saved
3. [ ] Request: "What is the current configuration state - is this L1.0 or factory default?"
   - Expected: Skill inspects bridge, DHCP, DNS presence and reports state
4. [ ] Request: "Download the text export to local filesystem"
   - Expected: Export retrieved via SCP/SSH and saved locally
5. [ ] Verify backup files exist on device:
   ```bash
   ssh admin@192.168.88.1 "/file print"
   ```

**Pass Criteria**: Binary backup and text export created, state detection accurate

---

### Test 12: Factory Reset and Immutable Deployment

**Purpose**: Verify factory reset safety guardrails and reset-then-configure workflow.

**Test Steps**:
1. [ ] Request: "Reset the switch to factory defaults"
   - Expected: Skill shows safety warning, asks for confirmation before proceeding
2. [ ] Confirm reset
   - Expected: Reset executed via `/system reset-configuration`, switch reboots
3. [ ] Wait for switch to come back online (factory IP 192.168.88.1)
4. [ ] Request: "Deploy L1.0 configuration from scratch (immutable deployment)"
   - Expected: Full L1.0 workflow executed - bridge, ports, IP, DHCP, DNS
5. [ ] Verify full configuration:
   ```bash
   ssh admin@192.168.88.1 "/interface bridge print"
   ssh admin@192.168.88.1 "/interface bridge port print"
   ssh admin@192.168.88.1 "/ip address print"
   ssh admin@192.168.88.1 "/ip dhcp-server print"
   ssh admin@192.168.88.1 "/ip dns print"
   ```

**Pass Criteria**: Reset completes safely, full L1.0 config deployed from clean slate

---

### Test 13: Local .rsc Design Workflow

**Purpose**: Verify local config file generation, editing, and deployment.

**Test Steps**:
1. [ ] Request: "Generate an L1.0 configuration file locally"
   - Expected: `.rsc` file created with bridge, ports, IP, DHCP, DNS commands
2. [ ] Review the generated file - verify RouterOS syntax is valid
3. [ ] Edit the file (e.g., change DHCP pool range to 10.0.0.150-10.0.0.250)
4. [ ] Request: "Deploy the local .rsc configuration to the switch"
   - Expected: File uploaded and executed via SSH
5. [ ] Request: "Parse the .rsc file and show what it would configure"
   - Expected: Human-readable summary of .rsc contents

**Verification**:
```bash
ssh admin@192.168.88.1 "/ip pool print"
# Should show updated pool range if edited
```

**Pass Criteria**: .rsc generation, deployment, and parsing all work correctly

---

### Test 14: Status Printing

**Purpose**: Verify compact status display for all configuration components.

**Test Steps**:
1. [ ] On factory-default switch, request: "Show switch status"
   - Expected: Shows switch model/version, reports no bridge/DHCP/DNS configured
2. [ ] Deploy L1.0 configuration, then request: "Show switch status"
   - Expected: Hierarchical display showing all components:
     ```
     Switch: CRS326-24G-2S+ (RouterOS 7.x, uptime ...)
     +-- Bridge: bridge-attic
         +-- Ports: 8 active
         +-- IP: 10.0.0.1/24
         +-- DHCP: dhcp-attic (pool 10.0.0.100-200)
         +-- DNS: 1.1.1.1, 8.8.8.8
     ```
3. [ ] Disconnect ethernet cable, request: "Show switch status"
   - Expected: Connection failure reported gracefully, no crash
4. [ ] With partial config (bridge only, no DHCP), request: "Show switch status"
   - Expected: Shows bridge info, marks DHCP/DNS as "Not configured"

**Pass Criteria**: Status works for all states - factory, partial, full, disconnected

---

### Test 15: Drift Detection

**Purpose**: Verify detection of configuration changes that differ from expected state.

**Test Steps**:
1. [ ] Deploy L1.0 configuration
2. [ ] Request: "Validate configuration against L1.0 spec"
   - Expected: All checks pass
3. [ ] Manually introduce drift:
   ```bash
   ssh admin@192.168.88.1 "/interface bridge port remove [find where interface=ether8]"
   ssh admin@192.168.88.1 "/ip dns set servers=9.9.9.9"
   ```
4. [ ] Request: "Validate configuration against L1.0 spec"
   - Expected: Reports drift - ether8 missing from bridge, DNS servers changed
5. [ ] Request: "Fix the detected drift"
   - Expected: Re-adds ether8 to bridge, restores DNS servers to 1.1.1.1,8.8.8.8

**Pass Criteria**: Drift accurately detected and reported, remediation works

---

## Test Results

**Date**: ___________
**Tester**: ___________
**Switch Serial**: ___________

| Test # | Test Name | Status | Notes |
|--------|-----------|--------|-------|
| 1 | Skill Triggering | ⬜ PASS / ⬜ FAIL | |
| 2 | Query Operations | ⬜ PASS / ⬜ FAIL | |
| 3 | Dry-Run Mode | ⬜ PASS / ⬜ FAIL | |
| 4 | Configuration Application | ⬜ PASS / ⬜ FAIL | |
| 5 | Idempotency | ⬜ PASS / ⬜ FAIL | |
| 6 | Configuration Validation | ⬜ PASS / ⬜ FAIL | |
| 7 | Error Handling | ⬜ PASS / ⬜ FAIL | |
| 8 | Cleanup | ⬜ PASS / ⬜ FAIL | |
| 9 | DHCP Operations | ⬜ PASS / ⬜ FAIL | |
| 10 | DNS Operations | ⬜ PASS / ⬜ FAIL | |
| 11 | Config State Management | ⬜ PASS / ⬜ FAIL | |
| 12 | Factory Reset & Deploy | ⬜ PASS / ⬜ FAIL | |
| 13 | Local .rsc Design | ⬜ PASS / ⬜ FAIL | |
| 14 | Status Printing | ⬜ PASS / ⬜ FAIL | |
| 15 | Drift Detection | ⬜ PASS / ⬜ FAIL | |

**Overall Result**: ⬜ ALL PASS / ⬜ PARTIAL / ⬜ FAIL

**Issues Identified**:
-
-
-

**Recommendations**:
-
-
-
