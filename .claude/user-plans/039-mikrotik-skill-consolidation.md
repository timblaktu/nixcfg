# Plan 039: Mikrotik Skill Consolidation Before Hardware Testing

**Created**: 2026-06-05
**Status**: Planning - Ready for execution
**Priority**: High - user has physical access to CRS326-24G-2S+ now
**Parent**: Plan 013 (Distributed Nix Binary Caching) - Phase 0 prerequisites
**Branch**: TBD (ask user before starting)

---

## Context

The mikrotik-management skill has been developed iteratively across 8 commits (dc93240..4a3f1f9) from initial creation through v2.2.0. The skill itself is feature-complete for L1.0 deployment (bridge, ports, IP, DHCP, DNS, config management, local .rsc design). However, the surrounding documentation, test cases, and plan files are fragmented and stale - reflecting the iterative development history rather than the current state. This plan consolidates everything before the first real hardware test session.

### Current State Assessment

**Skill source** (`modules/programs/claude-code/_hm/skills/mikrotik-management/`):
- `SKILL.md` (73KB) - Functionally at v2.2.0 (includes Section 11: Local Config Design) but header says v2.1.0
- `REFERENCE.md` (32KB) - L0.1 design doc, still accurate
- `test-cases.md` (8.6KB) - Header says v1.0.0, only covers Phase 1 (bridge/port/IP/VLAN), misses DHCP/DNS/config-mgmt/local-design
- `commands/README.md` - Placeholder, no actual scripts
- `examples/README.md` - Placeholder, no actual .rsc files

**Plan files** (`.claude/user-plans/`):
- `013-distributed-nix-binary-caching.md` - Says "L1.0 READY (skill v2.2.0)" but last updated 2026-01-28
- `013-L1.0-implementation-plan.md` - Phase 1B says DHCP/DNS "NOT YET IMPLEMENTED IN SKILL" (wrong since v2.0.0). Contains standalone bash scripts that duplicate skill workflows
- `013-L1.0-status-printing-feature.md` - Fully designed (4 format options, verbosity levels, error handling), never implemented
- `archive/mikrotik-interactive-design.md` - Session guide for v2.2.0 local design workflow, archived prematurely

### Problems

1. **Version mismatch**: SKILL.md header says v2.1.0, plan 013 says v2.2.0, test-cases says v1.0.0
2. **Stale L1.0 plan**: Says DHCP/DNS not in skill - wrong for 5 months
3. **Test coverage gap**: Tests don't cover DHCP, DNS, config management, local .rsc design, or status printing
4. **Status printing**: Fully designed, never built - would be the primary feedback tool during hardware testing
5. **No example configs**: examples/ dir is empty despite having a complete L1.0 spec
6. **No helper scripts**: commands/ dir is empty despite being referenced in plan 013

---

## Tasks

### Task 1: Version Alignment and Header Cleanup
**Status**: `TASK:PENDING`

Update version strings and metadata across all mikrotik skill files to reflect actual state.

**Changes**:
- `SKILL.md` line 8: `2.1.0` -> `2.2.0`, update Last Updated date
- `test-cases.md` line 3: `1.0.0` -> `2.2.0`, update Last Updated date
- `test-cases.md` line 4: update date

**DoD**: All files reference v2.2.0 consistently.

---

### Task 2: Update Test Cases for v2.2.0 Coverage
**Status**: `TASK:PENDING`

Extend `test-cases.md` to cover all v2.2.0 capabilities. The existing 8 tests are a good skeleton for core infrastructure. Need to add tests for:

**New test cases to add**:
- Test 9: DHCP Operations - pool creation, server config, network params, static leases, lease queries
- Test 10: DNS Operations - upstream server config, static entries, cache queries
- Test 11: Configuration State Management - backup (binary + text export), restore, state inspection (detect L1.0 vs factory)
- Test 12: Factory Reset and Immutable Deployment - reset with safety guardrails, reset-then-configure workflow
- Test 13: Local .rsc Design Workflow - config_design_local generation, .rsc editing, config_deploy_from_rsc, config_parse_rsc
- Test 14: Status Printing (depends on Task 3) - compact status display for all components, error handling for missing components
- Test 15: Drift Detection - apply config, manually change something, detect drift

**Preserve**: Existing tests 1-8 structure and format. Update references to v2.2.0.

**DoD**: test-cases.md covers all SKILL.md sections. Every capability in the skill has at least one test.

---

### Task 3: Implement Status Printing Feature
**Status**: `TASK:PENDING`

Add Section 12 to SKILL.md implementing compact status display. Design doc is at `.claude/user-plans/013-L1.0-status-printing-feature.md`.

**Design decisions** (from analysis of design doc options):
- **Format**: Hierarchical (Example D) - most informative for hardware debugging
- **Integration**: Skill function (Option B) - self-contained, discoverable in SKILL.md
- **Verbosity**: Start with fixed format (Option A) - add component-specific queries later if needed
- **Error handling**: Show partial status, mark missing components as "N/A", don't abort on single component failure

**Implementation**:
- Add `mikrotik_status()` function to SKILL.md Section 12
- Component functions: `_status_switch`, `_status_bridge`, `_status_ip`, `_status_dhcp`, `_status_dns`
- Uses targeted SSH queries (Approach 2 from design doc) to minimize round-trips
- Handles: no configuration, partial configuration, full L1.0 configuration, connection failure

**Output format**:
```
Switch: CRS326-24G-2S+ (RouterOS 7.14, uptime 5d 3h)
+-- Bridge: bridge-attic
    +-- VLAN Filtering: off
    +-- Ports: 8 active
    |   +-- ether1 (NUC NIC 1 - management)
    |   +-- ether2 (NUC NIC 2 - data)
    |   +-- ether3-8 (available)
    +-- IP: 10.0.0.1/24
    +-- DHCP: dhcp-attic
    |   +-- Pool: 10.0.0.100-200
    |   +-- Active Leases: 2
    |   +-- Static Leases: 1 (10.0.0.10 -> nux)
    +-- DNS: 1.1.1.1, 8.8.8.8
        +-- Static: nux.attic.local -> 10.0.0.10
```

**DoD**: `mikrotik_status` function in SKILL.md. Works on factory-default switch (shows minimal info) and fully-configured L1.0 switch (shows everything). Handles SSH connection failure gracefully.

---

### Task 4: Create L1.0 Example .rsc Configuration
**Status**: `TASK:PENDING`

Generate the concrete L1.0 network config as a `.rsc` file in `examples/`. This is the actual config that will be deployed to the switch.

**Source spec** (from `013-L1.0-implementation-plan.md`):
- Bridge: bridge-attic, VLAN filtering off
- Ports: ether1-ether8 on bridge-attic
- IP: 10.0.0.1/24 on bridge-attic
- DHCP pool: 10.0.0.100-10.0.0.200
- DHCP server: dhcp-attic on bridge-attic
- DHCP network: 10.0.0.0/24, gateway 10.0.0.1, DNS 10.0.0.1, domain attic.local
- DNS upstream: 1.1.1.1, 8.8.8.8, allow-remote-requests=yes
- DNS static: nux.attic.local -> 10.0.0.10, attic.local -> 10.0.0.10
- Static lease: 10.0.0.10 for NUC (MAC TBD)

**Files to create**:
- `examples/L1.0-attic-network.rsc` - Complete RouterOS script for the L1.0 network
- Update `examples/README.md` with description and usage instructions

**DoD**: Valid .rsc file that can be deployed via `config_deploy_from_rsc`. NUC MAC address placeholder clearly marked as TODO.

---

### Task 5: Update L1.0 Implementation Plan
**Status**: `TASK:PENDING`

Clean up `013-L1.0-implementation-plan.md` to reflect current state.

**Changes**:
- Remove "NOT YET IMPLEMENTED IN SKILL" from Phase 1B header (lines 103-146) - DHCP/DNS are in skill since v2.0.0
- Update Phase 1B status marker from warning to checkmark
- Replace standalone bash scripts (lines 314-431 for Phase 1A, 466-617 for Phase 1B) with references to:
  - Skill workflows in SKILL.md (L1.0 complete workflow, immutable deployment)
  - Example .rsc file from Task 4
  - Status printing from Task 3
- Merge Phase 1A and Phase 1B into a single unified deployment (no reason to split now that skill supports everything)
- Update "Implementation Strategy" to remove Option A vs Option B framing (skill enhancement is done)
- Update success criteria checkboxes

**DoD**: Plan accurately reflects current capabilities. No stale "not implemented" claims. References skill workflows instead of duplicating them.

---

### Task 6: Add Helper Scripts to commands/
**Status**: `TASK:PENDING`

Create minimal standalone helper scripts that can be used outside the skill context.

**Scripts**:
- `commands/mikrotik-status.sh` - Standalone version of the status function (useful from plain terminal)
- `commands/mikrotik-backup.sh` - Quick backup to local filesystem
- Update `commands/README.md` with usage instructions

**Design principles** (from existing README.md):
- Standalone bash scripts, no Nix dependencies
- SSH to configurable target (default 192.168.88.1)
- Human-readable output
- Safe (read-only by default)

**DoD**: Scripts are executable, work from any terminal with SSH access to the switch. README documents usage.

---

## Execution Order

Tasks 1-4 are independent and can be parallelized.
Task 5 depends on Tasks 3 and 4 (references their outputs).
Task 6 depends on Task 3 (ports status function to standalone script).

```
Task 1 (version alignment) ----\
Task 2 (test cases)        -----+---> Task 5 (update L1.0 plan)
Task 3 (status printing)  -----+---> Task 6 (helper scripts)
Task 4 (example .rsc)     ----/
```

## After This Plan

With consolidation done, the next session is hardware testing:
1. Connect to CRS326-24G-2S+ (factory defaults, 192.168.88.1)
2. Run test cases 1-3 (triggering, queries, dry-run) to validate skill works
3. Deploy L1.0 config using example .rsc file
4. Run status printing to verify
5. Run remaining test cases (idempotency, validation, drift detection)
6. Document results in test-cases.md
