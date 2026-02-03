# Mikrotik Management Skill - Test Cases

**Skill Version**: 1.0.0 (Phase 1)
**Last Updated**: 2026-01-27
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

**Overall Result**: ⬜ ALL PASS / ⬜ PARTIAL / ⬜ FAIL

**Issues Identified**:
-
-
-

**Recommendations**:
-
-
-
