# Plan 013: Distributed Nix Binary Caching with Attic

**Created**: 2026-01-27
**Status**: Planning - L0.1-L0.2 complete, L0.3 blocked (hardware), L1.0 READY (skill v2.2.0 + local design workflow complete)
**Priority**: High - Directly improves developer productivity and build times
**Current Phase**: Phase 0 (Mikrotik prerequisites) - skill v2.2.0 implemented with local config design, ready for hardware deployment
**Last Updated**: 2026-01-28 - Skill extended to v2.2.0 (added Section 11: Local Configuration Design & Deployment)

---

## Infrastructure Decisions (Finalized 2026-01-27)

### Phase 1 Office Deployment

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Hardware** | AMD64 NUC (Ryzen 7 5825U, 32GB RAM, 1TB SSD, dual NICs) | Existing infrastructure, powerful CPU, ample RAM |
| **Storage** | 500GB on existing 1TB SSD (ext4 filesystem) | Fast time-to-value; optimize later based on usage data |
| **Deployment** | NixOS `services.atticd` module (NOT containers) | First-class module, declarative config, easy iteration |
| **Database** | SQLite (embedded, `/var/lib/atticd/server.db`) | Simpler for single-node; no separate PostgreSQL needed |
| **Network** | Mikrotik CRS326-24G-2S+ isolated LAN (10.0.0.0/24) | Full control, proper network isolation from corporate LAN |
| **Dual NICs** | Separate management + data networks (same IP, traffic isolation) | Security isolation, monitoring separation |
| **Filesystem** | ext4 (mature, reliable, lowest latency) | Safe default; proven with Nix; simpler than ZFS |

### Storage Filesystem Research

Based on [NixOS community feedback](https://github.com/NixOS/nixpkgs/issues/119100) and [filesystem benchmarks](https://linuxcommunity.io/t/benchmarking-linux-filesystems-zfs-xfs-btrfs-vs-ext4/6405):

- **ext4**: ✅ **CHOSEN** - Lowest latency, most mature, proven with Nix store
- **XFS**: Strong alternative - highest throughput for large files/heavy I/O, but ext4 sufficient for Phase 1
- **ZFS**: Overkill - excellent for replication (zfs send/receive), but adds complexity and memory overhead
- **btrfs**: ❌ AVOID - copy-on-write issues with Nix store unless CoW disabled

**Phase 3 (AWS)**: Will use S3 backend (Attic's primary design), making local filesystem choice irrelevant for replication.

---

## Executive Summary

**Objective**: Deploy Attic binary cache infrastructure to optimize Nix builds across all environments - developer laptops, office servers, remote teams, and CI systems.

**Key Insight**: This is NOT a "CI validation project" - it's a **distributed build optimization strategy** that happens to also benefit CI. The cache serves developers first, CI second.

**Architecture Philosophy**:
- Start local (office deployment, zero AWS cost)
- Prove value with developer workflows
- Replicate proven design to AWS (lift-and-shift)
- Add CI integration as final consumer
- Optional: replicate to additional locations (India office, other AWS regions)

**Success Criteria**:
- Developers see 80%+ cache hit rate on typical builds
- Build times reduced from 30-60 min → 5-15 min (with warm cache)
- Office Attic instance serving local team successfully
- AWS instance operational for CI and remote access
- No multi-region AWS needed (India team uses local office cache)

---

## Background and Rationale

### The Problem

Nix builds are slow when starting from scratch:
- First build of n3x tests: 30-60 minutes (downloads all dependencies, builds everything)
- Developer iteration: Change one line → 5+ min rebuild (even with local nix store)
- Cross-compilation (x86_64 + aarch64): Doubles the artifacts needed
- CI cold starts: Every PR triggers full rebuild without cache

### Why Attic? (vs Cachix, S3 direct, Magic Nix Cache)

| Feature | Attic | Cachix | S3 Direct | Magic Nix Cache |
|---------|-------|---------|-----------|-----------------|
| **Self-hosted** | ✅ On-prem or cloud | ❌ SaaS only | ✅ S3 | ❌ SaaS only |
| **Nix-aware GC** | ✅ Keeps referenced paths | ❌ Time-based | ❌ S3 lifecycle | ❌ Public only |
| **Chunk dedup** | ✅ Only new chunks | ✅ Yes | ❌ Full NARs | ✅ Yes |
| **Replication** | ✅ Multi-instance | ❌ Single SaaS | ⚠️ Manual | ❌ Single SaaS |
| **Private cache** | ✅ Full control | ✅ Paid tier | ✅ S3 private | ❌ Public only |
| **Office deployment** | ✅ No cloud needed | ❌ Internet required | ⚠️ S3 required | ❌ Internet required |

**Key for n3x**: Cross-compilation toolchains for N100 (x86_64) and Jetson (aarch64) share 80%+ dependencies. Attic's chunk-level deduplication dramatically reduces storage.

### Cost Analysis (Corrected for Local-First Approach)

**Scenario A: Office-Only Deployment**
- Hardware: Existing server/NAS (no incremental cost)
- Storage: 200GB local disk (~$0 marginal cost)
- Network: Office LAN (gigabit, free)
- **Total**: ~$0/month (uses existing infrastructure)

**Scenario B: Office + AWS Replication**
- Office: $0/month (as above)
- AWS Attic: $6-60/month (depending on shared vs dedicated infrastructure)
- CI cost reduction: $324/mo → $36/mo = **$288/mo savings**
- **Net savings**: $228-282/month (even with dedicated AWS infrastructure)

**Scenario C: AWS-Only (original plan - WRONG)**
- AWS Attic: $60/month
- CI cost reduction: $288/month
- No local developer benefit until AWS deployed
- **Net savings**: $228/month BUT slower to realize value

**Verdict**: Start with Scenario A (office deployment), prove value locally, then add AWS replication for CI.

---

## Architecture Overview

### Phase 1 Target: Local Office Deployment

```
┌─────────────────────────────────────────────────────┐
│              Office Network (10.0.0.0/8)            │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐ │
│  │ Developer    │  │ Developer    │  │ Build    │ │
│  │ Laptop 1     │  │ Laptop 2     │  │ Server   │ │
│  │ (Tim)        │  │ (Teammate)   │  │          │ │
│  └──────┬───────┘  └──────┬───────┘  └────┬─────┘ │
│         │                  │                │       │
│         └──────────────────┴────────────────┘       │
│                            │                         │
│                    LAN (gigabit)                     │
│                            │                         │
│                  ┌─────────▼──────────┐             │
│                  │  Attic Server       │             │
│                  │  (office-attic)     │             │
│                  │                     │             │
│                  │  - Docker/Podman    │             │
│                  │  - PostgreSQL       │             │
│                  │  - Local storage    │             │
│                  │  - http://attic.local│            │
│                  └─────────────────────┘             │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Phase 3 Target: Office + AWS Replication

```
┌──────────────────────────┐         ┌─────────────────────────────┐
│   Office Network         │         │         AWS Cloud            │
│                          │         │                             │
│  ┌────────────────┐      │         │  ┌────────────────────┐    │
│  │ Developers     │      │         │  │  GitHub Actions    │    │
│  │ (US team)      │◄─────┼─────────┼─►│  CI Runners        │    │
│  └────────┬───────┘      │         │  └────────┬───────────┘    │
│           │              │         │           │                 │
│  ┌────────▼────────┐     │         │  ┌────────▼───────────┐    │
│  │ Attic (office)  │     │         │  │ Attic (AWS)        │    │
│  │ attic.local     │◄────┼─────────┼─►│ attic.company.com  │    │
│  └─────────────────┘     │         │  └────────────────────┘    │
│                          │         │                             │
└──────────────────────────┘         └─────────────────────────────┘
          ▲                                       ▲
          │                                       │
          │         ┌─────────────────────┐       │
          └─────────│  India Team         │───────┘
                    │  (VPN to office)    │
                    └─────────────────────┘
```

**Key Design Principle**: Each Attic instance is independent but can be configured to replicate. India team accesses office cache via VPN (no AWS multi-region needed).

---

## Progress Tracking

| Task ID | Task Name | Status | Definition of Done |
|---------|-----------|--------|-------------------|
| **Phase 0: Mikrotik Automation Prerequisites** ||||
| L0.1 | Design Mikrotik management skill | COMPLETE | Skill architecture documented in REFERENCE.md (7 RouterOS entities, Phase 1 scope) |
| L0.2 | Implement Mikrotik management skill | COMPLETE | SKILL.md created at ~/src/nixcfg/home/modules/claude-code/skills/mikrotik-management/, registered in skills.nix |
| L0.3 | Create test-cases.md and validate manually | BLOCKED | test-cases.md created (8-test suite), manual validation DEFERRED (awaiting hardware setup - see task notes) |
| L0.4 | Integrate Nix derivation testing utilities | DEFERRED | (Future) Use pkgs.writers.makeBashScript for helper commands, add build-time validation |
| **Phase 1: Local Office Deployment** ||||
| L1.0 | Mikrotik network setup (using skill) | READY | Skill v2.2.0 complete with local config design workflow, DHCP/DNS, config mgmt (backup/restore/reset), implementation plan ready (.claude/user-plans/013-L1.0-implementation-plan.md), awaiting hardware access for deployment |
| L1.1 | Survey office infrastructure | PENDING | NUC specs documented (Ryzen 7 5825U, 32GB RAM, 1TB SSD, dual NICs), filesystem choice confirmed |
| L1.2 | Design NixOS Attic deployment | PENDING | NixOS module config designed, ext4 storage layout planned, dual NIC topology documented |
| L1.3 | Deploy Attic via NixOS module | PENDING | `services.atticd` enabled, systemd service running, accessible at http://10.0.0.10:8080 |
| L1.4 | Configure SQLite database | PENDING | Database initialized at /var/lib/atticd/server.db, Attic migrations run successfully |
| L1.5 | Configure ext4 local storage | PENDING | Storage mounted at /var/lib/atticd/storage (ext4), test push succeeds, storage metrics baseline |
| L1.6 | Generate signing keys | PENDING | RSA key pair generated via openssl, public key documented for client config |
| L1.7 | Test developer workflow | PENDING | Developer laptop configured, successful cache hit on second build, speedup measured |
| L1.8 | Document local setup | PENDING | docs/ATTIC-OFFICE-SETUP.md created with NixOS config, network topology, troubleshooting |
| **Phase 2: Developer Workflow Optimization** ||||
| D2.1 | Create Nix flake cache config | PENDING | Add office Attic to flake.nix substituters |
| D2.2 | Test cross-arch caching | PENDING | Verify x86_64 and aarch64 builds share deduplicated chunks |
| D2.3 | Measure cache hit rates | PENDING | Collect metrics on cache hit/miss rates, build time improvements |
| D2.4 | Optimize GC policy | PENDING | Tune retention settings based on actual usage patterns |
| D2.5 | Create developer onboarding docs | PENDING | Step-by-step guide for new devs to configure Attic access |
| **Phase 3: AWS Attic Deployment (Lift-and-Shift)** ||||
| A3.1 | Review ATTIC-INFRASTRUCTURE-DESIGN.md | PENDING | DevOps team answers infrastructure questionnaire |
| A3.2 | Adapt office config for AWS | PENDING | Translate Docker Compose → Pulumi/Terraform IaC |
| A3.3 | Deploy AWS infrastructure | PENDING | ECS/Fargate + RDS + S3 + ALB deployed, health checks passing |
| A3.4 | Configure replication (optional) | PENDING | Office ↔ AWS cache sync (if desired), or keep independent |
| A3.5 | Test AWS cache from laptop | PENDING | Developer can pull from https://attic.company.com successfully |
| A3.6 | Update Nix flake for fallback | PENDING | Configure clients to try office first, AWS second |
| **Phase 4: CI Integration (GitHub Actions)** ||||
| C4.1 | Create portable CI scripts | PENDING | .ci/scripts/ directory with setup-nix.sh, run-test.sh, etc. |
| C4.2 | Implement GitHub Actions workflow | PENDING | .github/workflows/test-vlans.yml using AWS Attic cache |
| C4.3 | Test cache hit rates in CI | PENDING | Verify CI builds use cache effectively (>70% hit rate) |
| C4.4 | Measure CI cost reduction | PENDING | Document before/after CI costs, confirm savings |
| C4.5 | Add status badges to README | PENDING | CI status visible in repository README |
| **Phase 5: Optional Enhancements** ||||
| E5.1 | Deploy India office Attic | PENDING | If VPN latency poor, deploy local instance in India |
| E5.2 | Add monitoring dashboards | PENDING | Grafana/Prometheus for cache metrics, storage growth |
| E5.3 | Implement GitLab CI support | PENDING | Port GitHub Actions scripts to .gitlab-ci.yml |
| E5.4 | Document multi-site replication | PENDING | Guide for adding new Attic replicas in other locations |

---

## Phase 1: Local Office Deployment (PRIORITY 1)

### Goal
Deploy Attic binary cache in office network with zero cloud dependency. Prove value with local developer workflows before investing in AWS infrastructure.

### Prerequisites
- [x] Office network: Mikrotik CRS326-24G-2S+ switch for isolated LAN (10.0.0.0/24)
- [x] Server: AMD64 NUC - Ryzen 7 5825U, 32GB DDR4, 1TB SSD, dual NICs
- [x] Storage: 500GB allocated on existing 1TB SSD (ext4 filesystem)
- [x] Deployment: NixOS with `services.atticd` module

### Architecture Decision: NixOS Module Deployment

**Decision**: Use NixOS `services.atticd` module (NOT containers) for Phase 1

**Rationale**:
- ✅ First-class NixOS module with declarative TOML config
- ✅ Automatic systemd service management with sandboxing
- ✅ Simple local storage: `storage.type = "local"` with ext4
- ✅ SQLite database (no separate PostgreSQL needed for single-node)
- ✅ Easy to test/iterate with `nixos-rebuild switch`
- ✅ Config translates to AWS later (same TOML, just swap storage: local → S3)

**Components**:
1. **Attic server** (NixOS service via `services.atticd`)
2. **SQLite database** (embedded, `/var/lib/atticd/server.db`)
3. **Local storage** (ext4 volume, `/var/lib/atticd/storage`)

**Network**:
- Management NIC: 10.0.0.10/24 (SSH, monitoring)
- Data NIC: 10.0.0.10/24 (cache traffic, port 8080)
- (Same IP, different physical NICs for traffic isolation)

### Implementation Steps

#### Phase 0: Mikrotik Automation Prerequisites (L0.1 - L0.4)

**Rationale**: Before manually configuring the Mikrotik switch (L1.0), create reusable automation tools to make network configuration reproducible and documented.

---

##### L0.1: Design Mikrotik Management Skill ✅ COMPLETE
**Status**: Complete (2026-01-27)

**Tasks**:
- Document RouterOS entities and configuration patterns
- Design skill architecture with SSH wrappers, dry-run mode, validation
- Scope Phase 1 implementation: Interfaces, VLANs, Bridges, Ports, IP Addresses

**Deliverable**:
- `~/src/nixcfg/home/modules/claude-code/skills/mikrotik-management/REFERENCE.md`
- Architecture covers 7 RouterOS entities with 8-step implementation plan

---

##### L0.2: Implement Mikrotik Management Skill ✅ COMPLETE
**Status**: Complete (2026-01-27)

**Tasks**:
- Create SKILL.md with RouterOS command templates
- Implement SSH connection patterns and output parsing
- Add dry-run mode, validation, and safety checks
- Register skill in nixcfg skills.nix module

**Deliverable**:
- `~/src/nixcfg/home/modules/claude-code/skills/mikrotik-management/SKILL.md`
- Skill deployed to `~/.claude/skills/mikrotik-management/` via Home Manager
- Skill triggers on "Configure Mikrotik switch" or `/mikrotik-management`

**Files**:
- Source: `~/src/nixcfg/home/modules/claude-code/skills/mikrotik-management/SKILL.md`
- Generated: `~/.claude/skills/mikrotik-management/` (via skills.nix activation)

---

##### L0.3: Create test-cases.md and Validate Manually 🚧 BLOCKED
**Status**: Blocked - Awaiting hardware setup (2026-01-27)

**Progress**:
- ✅ test-cases.md created with 8-test suite (updated from 6)
- ✅ Test checklist comprehensive: skill triggering, queries, dry-run, config application, idempotency, validation, error handling, cleanup
- ❌ Manual validation NOT run - hardware prerequisites not met

**Blocking Issue** (2026-01-27):
- No physical access to Mikrotik CRS326-24G-2S+ switch
- WSL environment at 172.25.249.32/20 (no 192.168.88.0/24 connectivity)
- Options for unblocking:
  - Option A: Configure Windows host with static IP 192.168.88.50/24, test from Windows
  - Option B: USB ethernet + WSL bridge (advanced)
- **Decision**: Defer L0.3 validation, proceed with L1.0 planning

**Prerequisites** (Not Currently Met):
- Mikrotik CRS326-24G-2S+ switch powered on
- Direct ethernet connection to management port
- Laptop configured with static IP 192.168.88.50/24
- Switch at factory defaults (192.168.88.1, admin/<blank>)

**Deliverable** (Partial):
- ✅ test-cases.md created at `~/src/nixcfg/home/modules/claude-code/skills/mikrotik-management/test-cases.md`
- ⏸️ Manual validation DEFERRED (resume when hardware available)
- ⏸️ Test results documentation DEFERRED

---

##### L0.4: Integrate Nix Derivation Testing Utilities 🔄 DEFERRED
**Status**: Deferred (future enhancement)

**Tasks** (when needed):
- Use `pkgs.writers.makeBashScript` for helper commands in `commands/` directory
- Add build-time validation (shellcheck, syntax checks) via Nix checks
- Consider creating `checks.x86_64-linux.mikrotik-skill-validation` derivation
- Integrate with CI/CD for automated skill testing

**Rationale for deferral**: Manual validation (L0.3) proves the skill works. Nix-based testing is valuable but not blocking for L1.0+ deployment tasks.

---

#### Phase 1: Local Office Deployment (L1.0 - L1.8)

##### L1.0: Mikrotik Network Setup (Using Skill)
**Status**: Pending (blocked by L0.3 validation)

**Prerequisites**:
- L0.3 test-cases.md validation complete (skill proven working)
- Mikrotik CRS326-24G-2S+ switch accessible
- Laptop configured for switch management network

**Tasks**:
- Use `/mikrotik-management` skill to configure CRS326-24G-2S+ for isolated LAN (10.0.0.0/24)
- Create bridge-attic with VLAN 10 for Attic network
- Configure DHCP server for 10.0.0.0/24 range (or static assignment)
- Connect NUC dual NICs to ether1/ether2 on switch
  - NIC 1: Management interface (SSH, monitoring)
  - NIC 2: Data interface (cache traffic)
- Test connectivity from developer laptop to 10.0.0.10
- Document configuration in skill examples directory (optional)

**Deliverable**:
- Isolated network operational via skill-generated config
- NUC reachable at 10.0.0.10
- Switch configuration reproducible via skill commands

---

#### L1.1: Survey Office Infrastructure
**Tasks**:
- Document NUC hardware specs:
  - CPU: AMD Ryzen 7 5825U (8C/16T)
  - RAM: 32GB DDR4
  - Storage: 1TB SSD (2x M.2 slots available)
  - Network: Dual NICs (1Gbps or 2.5Gbps)
- Verify NixOS installation (or plan nixos-anywhere deployment)
- Confirm filesystem choice: ext4 for reliability
- Document current storage usage, allocate 500GB for Attic

**Deliverable**: Infrastructure survey document with NUC specs and deployment plan

---

#### L1.2: Design NixOS Attic Deployment
**Tasks**:
- Create NixOS configuration for Attic server:
  - Import `attic` flake input, use `nixosModules.atticd`
  - Configure `services.atticd.settings` with local storage
  - Design ext4 partition layout (500GB dedicated volume or shared)
  - Plan dual NIC configuration (management vs data)
- Design RSA signing key storage (encrypted file in /var/lib/atticd/keys)
- Document security: firewall rules, SSH hardening

**Reference**: See "Appendix A: NixOS Configuration Example" below

**Deliverable**: NixOS configuration drafted, architecture documented

---

#### L1.3: Deploy Attic via NixOS Module
**Tasks**:
- Add Attic flake input to NUC's flake.nix
- Enable `services.atticd` module with settings:
  - `mode = "monolithic"` (single-node server)
  - `storage.type = "local"`
  - `storage.path = "/var/lib/atticd/storage"`
  - `database.url = "sqlite:///var/lib/atticd/server.db?mode=rwc"`
- Run `nixos-rebuild switch` to deploy
- Verify systemd service: `systemctl status atticd`
- Test health endpoint: `curl http://10.0.0.10:8080/`

**Deliverable**: Attic service running, accessible on isolated network

---

#### L1.4: Configure SQLite Database
**Tasks**:
- Verify SQLite database created at `/var/lib/atticd/server.db`
- Check Attic migrations ran successfully: `journalctl -u atticd -n 50`
- Test database connectivity: `attic cache list` (should show empty list)
- Document database backup strategy (sqlite3 .dump or filesystem snapshots)

**Deliverable**: Database initialized, no errors in logs

---

#### L1.5: Configure ext4 Local Storage
**Tasks**:
- Verify storage path exists and writable: `/var/lib/atticd/storage`
- Check filesystem: `df -hT /var/lib/atticd/storage` (should show ext4)
- Create test cache: `atticd-atticadm make-token --sub test | attic login test http://10.0.0.10:8080 -` then `attic cache create n3x`
- Test push: Build simple derivation, push to cache
  ```bash
  nix build nixpkgs#hello
  attic push n3x result
  ```
- Verify artifact stored: `du -sh /var/lib/atticd/storage`
- Establish storage metrics baseline (size, inode count)

**Deliverable**: Successful test push, storage metrics documented

---

#### L1.6: Generate Signing Keys
**Tasks**:
- Generate RSA key pair for Attic token signing:
  ```bash
  openssl genrsa -traditional 4096 > /var/lib/atticd/keys/token-signing.key
  base64 -w0 /var/lib/atticd/keys/token-signing.key > /var/lib/atticd/keys/token-signing.key.b64
  ```
- Extract public key for JWT verification (if needed later)
- Configure `services.atticd.environmentFile` with:
  - `ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=<contents of .b64 file>`
- Restart atticd service: `systemctl restart atticd`
- Document public key in `docs/ATTIC-OFFICE-SETUP.md`

**Deliverable**: RSA key pair generated, service configured, public key documented

---

#### L1.7: Test Developer Workflow
**Tasks**:
- Generate developer access token on Attic server:
  ```bash
  atticd-atticadm make-token --sub developer --validity '180d' --pull 'n3x' --push 'n3x'
  ```
- Configure developer laptop to use office cache:
  ```bash
  # On developer laptop
  attic login office http://10.0.0.10:8080 <token>
  attic use n3x
  ```
  Or add to `~/.config/nix/nix.conf`:
  ```
  extra-substituters = http://10.0.0.10:8080/n3x
  extra-trusted-public-keys = n3x:PUBLIC_KEY_HERE
  ```
- Test cold build (no cache): `time nix build .#checks.x86_64-linux.k3s-cluster-simple`
- Push to cache: `attic push n3x result`
- Clear local build: `rm result && nix-collect-garbage -d`
- Test warm build (with cache): Should be 5-15 min vs 30-60 min
- Verify cache hit in logs: `nix build --print-build-logs`

**Deliverable**: Developer laptop using office cache, 70%+ speedup measured

---

#### L1.8: Document Local Setup
**Tasks**:
- Create `docs/ATTIC-OFFICE-SETUP.md` with:
  - Network topology diagram (Mikrotik switch, NUC dual NICs, developer laptops)
  - NixOS configuration reference (services.atticd settings)
  - Server access instructions (SSH to 10.0.0.10, systemctl commands)
  - Client configuration (attic login, nix.conf settings)
  - Troubleshooting guide (connection issues, cache misses, firewall rules)
  - Maintenance procedures (GC policy, SQLite backups, storage monitoring)
  - Token generation for new team members
- Share with team (internal wiki or Slack)

**Deliverable**: Documentation published, team onboarded to office cache

---

## Phase 2: Developer Workflow Optimization

### Goal
Maximize developer productivity gains from office cache. Tune configuration, measure improvements, create repeatable workflows.

### Implementation Steps (D2.1 - D2.5)

#### D2.1: Create Nix Flake Cache Config
**Tasks**:
- Add office Attic to n3x flake.nix:
  ```nix
  nixConfig = {
    extra-substituters = [ "http://attic.local:8080/n3x" ];
    extra-trusted-public-keys = [ "n3x:PUBLIC_KEY_HERE" ];
  };
  ```
- Test flake builds use cache automatically
- Document flake-based vs nix.conf config

**Deliverable**: Flake configured for automatic cache usage

---

#### D2.2: Test Cross-Arch Caching
**Tasks**:
- Build x86_64 derivation, push to cache
- Build aarch64 derivation (cross-compiled or native)
- Verify chunk deduplication (storage shouldn't double)
- Test cache hits across architectures

**Deliverable**: Cross-arch deduplication verified, storage metrics documented

---

#### D2.3: Measure Cache Hit Rates
**Tasks**:
- Collect metrics over 1-2 weeks:
  - Cache hit/miss rate
  - Build time improvements (before/after)
  - Storage growth
- Create dashboard or report

**Deliverable**: Metrics report showing cache effectiveness

---

#### D2.4: Optimize GC Policy
**Tasks**:
- Review current retention settings
- Analyze storage growth trends
- Tune GC interval and retention days:
  ```toml
  [garbage-collection]
  interval = "24h"
  retention_days = 90  # Adjust based on usage
  ```
- Test GC doesn't delete actively-used paths

**Deliverable**: GC policy tuned for office usage patterns

---

#### D2.5: Create Developer Onboarding Docs
**Tasks**:
- Write step-by-step guide for new developers:
  1. Install Nix
  2. Configure office cache access
  3. Verify cache works (test build)
  4. Troubleshooting tips
- Include screenshots, example commands
- Review with team, incorporate feedback

**Deliverable**: Onboarding guide tested with new team member

---

## Phase 3: AWS Attic Deployment (Lift-and-Shift)

### Goal
Replicate proven office deployment to AWS for CI and remote access. Use existing ATTIC-INFRASTRUCTURE-DESIGN.md as implementation guide.

### Prerequisites
- [ ] Phase 1 complete (office cache operational)
- [ ] DevOps team answers infrastructure questionnaire (ATTIC-INFRASTRUCTURE-DESIGN.md)
- [ ] AWS account access, IAM permissions
- [ ] Decision on dedicated vs shared infrastructure (ECS, RDS, ALB)

### Reference Documents
- **Technical Design**: `docs/plans/ATTIC-INFRASTRUCTURE-DESIGN.md`
- **Original Plan**: `docs/plans/CI-VALIDATION-PLAN.md` (Phase 3B)

### Implementation Steps (A3.1 - A3.6)

#### A3.1: Review ATTIC-INFRASTRUCTURE-DESIGN.md
**Tasks**:
- DevOps team reviews design document
- Answers all questions in "Questions for DevOps Team" section
- Makes decisions on 9 decision matrices
- Schedules deployment timeline (7-10 hours estimated)

**Deliverable**: Completed questionnaire, finalized architecture decisions

---

#### A3.2: Adapt Office Config for AWS
**Tasks**:
- Translate Docker Compose → Pulumi/Terraform IaC
- Use same Attic configuration (server.toml)
- Use same signing keys (or generate new if preferred)
- Adapt storage: local filesystem → S3
- Adapt database: containerized PostgreSQL → RDS

**Deliverable**: Pulumi/Terraform code ready for deployment

---

#### A3.3: Deploy AWS Infrastructure
**Tasks**:
- Run `pulumi up` or `terraform apply`
- Verify all components healthy:
  - ECS tasks running
  - RDS accessible from ECS
  - S3 bucket created
  - ALB health checks passing
- Test health endpoint: `curl https://attic.company.com/v1/healthz`

**Deliverable**: AWS Attic instance deployed and healthy

---

#### A3.4: Configure Replication (Optional)
**Tasks**:
- **Option A**: Independent caches (office and AWS separate)
  - Simpler, no sync needed
  - Each cache grows independently
- **Option B**: One-way sync (office → AWS or AWS → office)
  - Use `attic` CLI or S3 sync
  - Keeps caches consistent
- **Option C**: Bidirectional sync
  - Complex, use with caution

**Recommendation**: Start with Option A (independent), add sync later if needed

**Deliverable**: Replication strategy documented and implemented (if chosen)

---

#### A3.5: Test AWS Cache from Laptop
**Tasks**:
- Configure laptop to use AWS cache:
  ```nix
  substituters = https://attic.company.com/n3x https://cache.nixos.org
  ```
- Test cache pull (should work from anywhere with internet)
- Verify TLS certificate valid
- Test push (requires auth token)

**Deliverable**: AWS cache accessible from developer laptop

---

#### A3.6: Update Nix Flake for Fallback
**Tasks**:
- Configure clients to try office first (LAN), AWS second:
  ```nix
  nixConfig = {
    extra-substituters = [
      "http://attic.local:8080/n3x"      # Office (fast, LAN-only)
      "https://attic.company.com/n3x"    # AWS (slower, always available)
      "https://cache.nixos.org"          # Upstream fallback
    ];
  };
  ```
- Test failover (disconnect from office network, build should use AWS)

**Deliverable**: Flake configured for intelligent cache fallback

---

## Phase 4: CI Integration (GitHub Actions)

### Goal
Leverage AWS Attic cache in CI to reduce build times and costs. This is the simplest phase - just configure CI to use existing cache.

### Prerequisites
- [ ] Phase 3 complete (AWS Attic operational)
- [ ] GitHub Actions workflows already exist (from VLAN testing work)
- [ ] Attic push token generated and stored in GitHub Secrets

### Reference Documents
- **CI Plan**: `docs/plans/CI-VALIDATION-PLAN.md` (Phases 3, 4A, 4B, 4C)

### Implementation Steps (C4.1 - C4.5)

#### C4.1: Create Portable CI Scripts
**Tasks**:
- Create `.ci/scripts/` directory with:
  - `setup-nix.sh` - Install Nix with cache config
  - `setup-attic.sh` - Install Attic CLI, login to AWS cache
  - `run-test.sh` - Run test with retry logic
  - `report-results.sh` - Format test results
- Make scripts portable (work on GitHub Actions, GitLab CI, local)

**Reference**: See CI-VALIDATION-PLAN.md Phase 3 for script examples

**Deliverable**: Portable CI scripts tested locally

---

#### C4.2: Implement GitHub Actions Workflow
**Tasks**:
- Create `.github/workflows/nix-cache.yml`:
  ```yaml
  - uses: DeterminateSystems/nix-installer-action@main
    with:
      extra-conf: |
        extra-substituters = https://attic.company.com/n3x
        extra-trusted-public-keys = n3x:${{ secrets.ATTIC_PUBLIC_KEY }}

  - name: Install Attic
    run: nix profile install github:zhaofengli/attic

  - name: Login to Attic
    run: attic login ci https://attic.company.com ${{ secrets.ATTIC_TOKEN }}

  - name: Run tests
    run: .ci/scripts/run-test.sh k3s-cluster-vlans

  - name: Push to cache
    if: success()
    run: attic push n3x result
  ```
- Test workflow on feature branch

**Deliverable**: GitHub Actions workflow using AWS Attic cache

---

#### C4.3: Test Cache Hit Rates in CI
**Tasks**:
- Trigger multiple CI runs
- Monitor build logs for cache hits
- Measure build time reduction:
  - First run (cold cache): ~15-30 min
  - Second run (warm cache): ~5-10 min
- Target: >70% cache hit rate after warmup

**Deliverable**: CI cache hit metrics documented

---

#### C4.4: Measure CI Cost Reduction
**Tasks**:
- Calculate baseline cost (before cache):
  - 3 tests × 45 min × $0.008/min × 30 runs/month = $324/month
- Calculate new cost (with cache):
  - 3 tests × 5 min × $0.008/min × 30 runs/month = $36/month
- Document savings: **$288/month** (89% reduction)
- Add Attic infrastructure cost: $6-60/month
- Net savings: **$228-282/month**

**Deliverable**: Cost analysis report showing ROI

---

#### C4.5: Add Status Badges to README
**Tasks**:
- Add GitHub Actions status badge to n3x README.md
- Add cache status badge (optional, custom)
- Link to CI results page

**Deliverable**: README updated with CI status visibility

---

## Phase 5: Optional Enhancements

### E5.1: Deploy India Office Attic
**Condition**: Only if VPN latency to office cache is poor

**Tasks**:
- Replicate Phase 1 deployment in India office
- Configure replication with US office (optional)
- Update client fallback chain to include India cache

---

### E5.2: Add Monitoring Dashboards
**Tasks**:
- Deploy Prometheus + Grafana (office and/or AWS)
- Configure Attic metrics collection
- Create dashboards for:
  - Cache hit/miss rate
  - Storage growth
  - Request latency
  - Client geographic distribution

---

### E5.3: Implement GitLab CI Support
**Tasks**:
- Create `.gitlab-ci.yml` using same portable scripts
- Test on GitLab CI (work account)
- Document GitLab-specific configuration

---

### E5.4: Document Multi-Site Replication
**Tasks**:
- Write guide for adding new Attic replicas
- Document replication strategies (independent, one-way, bi-directional)
- Include troubleshooting for sync issues

---

## Appendix A: NixOS Configuration Example

### Minimal NixOS Configuration for Attic Server

```nix
# /etc/nixos/configuration.nix or flake-based config
{ config, pkgs, ... }:

{
  # Import Attic flake module
  imports = [
    # Add to flake inputs:
    # inputs.attic.nixosModules.atticd
  ];

  # Network configuration - dual NICs
  networking = {
    hostName = "attic-cache";
    interfaces = {
      # Management interface
      enp1s0 = {
        ipv4.addresses = [{
          address = "10.0.0.10";
          prefixLength = 24;
        }];
      };
      # Data interface (same IP, traffic isolation via routing/firewall)
      enp2s0 = {
        ipv4.addresses = [{
          address = "10.0.0.10";
          prefixLength = 24;
        }];
      };
    };
    defaultGateway = "10.0.0.1";
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 8080 ];  # SSH, Attic
    };
  };

  # Attic service configuration
  services.atticd = {
    enable = true;

    # Credentials file (RSA signing key)
    credentialsFile = "/var/lib/atticd/secrets/env";
    # Contents: ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=<base64-encoded RSA key>

    settings = {
      # Listen on all interfaces (dual NIC)
      listen = "0.0.0.0:8080";

      # API endpoint (for client config)
      api-endpoint = "http://10.0.0.10:8080/";

      # Database (SQLite for single-node)
      database.url = "sqlite:///var/lib/atticd/server.db?mode=rwc";

      # Local storage on ext4
      storage = {
        type = "local";
        path = "/var/lib/atticd/storage";
      };

      # Compression (zstd recommended)
      compression = {
        type = "zstd";
        level = 3;  # Balance speed vs compression ratio
      };

      # Garbage collection
      garbage-collection = {
        interval = "24 hours";
        default-retention-period = "90 days";
      };
    };
  };

  # Storage filesystem (ext4 dedicated partition)
  fileSystems."/var/lib/atticd/storage" = {
    device = "/dev/disk/by-label/attic-storage";  # Adjust for your setup
    fsType = "ext4";
    options = [ "defaults" "noatime" ];  # noatime improves performance
  };

  # System packages
  environment.systemPackages = with pkgs; [
    attic-client  # For atticd-atticadm commands
    sqlite        # For database maintenance
  ];

  # Security hardening
  security.sudo.wheelNeedsPassword = true;
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };
}
```

### Initial Setup Commands

```bash
# 1. Generate RSA signing key
sudo mkdir -p /var/lib/atticd/secrets
sudo openssl genrsa -traditional 4096 | sudo tee /var/lib/atticd/secrets/token-signing.key > /dev/null
sudo base64 -w0 /var/lib/atticd/secrets/token-signing.key | sudo tee /var/lib/atticd/secrets/token-signing.key.b64 > /dev/null

# 2. Create credentials file
echo "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=$(sudo cat /var/lib/atticd/secrets/token-signing.key.b64)" | sudo tee /var/lib/atticd/secrets/env > /dev/null
sudo chmod 600 /var/lib/atticd/secrets/env

# 3. Deploy configuration
sudo nixos-rebuild switch

# 4. Create n3x cache
sudo atticd-atticadm -f /var/lib/atticd/server.db make-cache --retention-period '90 days' n3x

# 5. Generate developer token
sudo atticd-atticadm -f /var/lib/atticd/server.db make-token \
  --sub developer \
  --validity '180d' \
  --pull 'n3x' \
  --push 'n3x'
# Save this token for developer laptop configuration!

# 6. Verify service
systemctl status atticd
curl http://10.0.0.10:8080/
```

### Storage Partition Setup (ext4)

```bash
# Option 1: Dedicated partition (recommended if NUC has 2 M.2 drives)
# Assuming /dev/nvme1n1 is second M.2 drive
sudo parted /dev/nvme1n1 mklabel gpt
sudo parted /dev/nvme1n1 mkpart primary ext4 0% 100%
sudo mkfs.ext4 -L attic-storage /dev/nvme1n1p1
sudo mkdir -p /var/lib/atticd/storage
sudo mount /dev/disk/by-label/attic-storage /var/lib/atticd/storage

# Option 2: Subdirectory on existing filesystem (simpler for Phase 1)
sudo mkdir -p /var/lib/atticd/storage
# Then configure fileSystems in NixOS config to bind-mount or just use the path directly
```

### Flake Integration (for n3x project)

```nix
# flake.nix - Add Attic as input
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    attic.url = "github:zhaofengli/attic";
    # ... other inputs
  };

  outputs = { self, nixpkgs, attic, ... }: {
    # NixOS configuration for Attic server
    nixosConfigurations.attic-cache = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        attic.nixosModules.atticd
        ./hosts/attic-cache/configuration.nix
      ];
    };

    # Cache configuration for developers
    nixConfig = {
      extra-substituters = [
        "http://10.0.0.10:8080/n3x"     # Office cache (LAN only)
        "https://cache.nixos.org"        # Upstream fallback
      ];
      extra-trusted-public-keys = [
        "n3x:PUBLIC_KEY_HERE"  # Replace with actual public key from token
      ];
    };
  };
}
```

---

## Appendix B: Client Configuration Examples

### Developer Laptop (nix.conf)
```nix
# ~/.config/nix/nix.conf
substituters = http://attic.local:8080/n3x https://cache.nixos.org
trusted-public-keys = n3x:PUBLIC_KEY_HERE cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
```

### Flake-based Project (flake.nix)
```nix
{
  description = "n3x with Attic cache";

  nixConfig = {
    extra-substituters = [
      "http://attic.local:8080/n3x"      # Office (LAN)
      "https://attic.company.com/n3x"    # AWS (fallback)
    ];
    extra-trusted-public-keys = [
      "n3x:PUBLIC_KEY_HERE"
    ];
  };

  inputs = { ... };
  outputs = { ... };
}
```

### CI (GitHub Actions)
```yaml
- name: Configure Nix cache
  run: |
    mkdir -p ~/.config/nix
    cat >> ~/.config/nix/nix.conf <<EOF
    extra-substituters = https://attic.company.com/n3x
    extra-trusted-public-keys = n3x:${{ secrets.ATTIC_PUBLIC_KEY }}
    EOF
```

---

## Appendix C: Troubleshooting Guide

### Cache Miss (Expected Hit)

**Symptom**: Build downloads/compiles instead of using cache

**Diagnosis**:
```bash
# Check substituters configured
nix show-config | grep substituters

# Check if path exists in cache
curl http://attic.local:8080/n3x/nix-cache-info

# Try explicit substituter
nix build --substituters http://attic.local:8080/n3x --print-build-logs
```

**Common causes**:
- Substituter not in nix.conf
- Public key mismatch
- Cache doesn't have that derivation yet (first build)
- Network connectivity (firewall blocking port 8080)

---

### Slow Cache Fetch

**Symptom**: Cache hit takes longer than expected

**Diagnosis**:
- Check network latency: `ping attic.local`
- Check server load: `docker stats attic-server`
- Check storage I/O: `iostat -x 1 10`

**Solutions**:
- Increase Attic server resources (CPU/RAM)
- Use faster storage (SSD instead of HDD)
- Enable compression (already in example config)

---

### Storage Growth

**Symptom**: Cache storage growing too fast

**Diagnosis**:
```bash
# Check storage size
docker exec attic-server du -sh /var/lib/attic/storage

# Check GC settings
docker exec attic-server cat /etc/attic/server.toml | grep -A5 garbage-collection
```

**Solutions**:
- Tune GC retention (reduce from 90 to 60 days)
- Run manual GC: `docker exec attic-server attic gc n3x`
- Check for large unreferenced paths

---

## Success Metrics

### Phase 1 Success Criteria
- [ ] Office Attic server running 24/7 with <1% downtime
- [ ] At least 2 developers successfully using office cache
- [ ] Build time reduction: 30-60 min → 5-15 min (with warm cache)
- [ ] Cache hit rate: >70% after 1 week of usage
- [ ] Storage growth predictable and within capacity

### Phase 3 Success Criteria
- [ ] AWS Attic deployed and healthy (health check passing)
- [ ] Accessible from developer laptop (outside office network)
- [ ] Same performance as office cache (latency acceptable)
- [ ] Cost within budget ($6-60/month)

### Phase 4 Success Criteria
- [ ] GitHub Actions using AWS cache successfully
- [ ] CI build time: 45 min → 5-10 min (67-78% reduction)
- [ ] CI cost reduction: $324/mo → $36/mo (89% reduction)
- [ ] Net savings: $228-282/month (even with Attic costs)

---

## Next Steps for First Session

**Recommended starting point**: L1.0 (Mikrotik Network Setup)

### Session 1 Tasks (L1.0 - L1.1)

1. **L1.0: Mikrotik Network Setup** (~1-2 hours)
   - Configure Mikrotik CRS326-24G-2S+ for 10.0.0.0/24 subnet
   - Set up DHCP or static IP assignment for 10.0.0.10 (NUC)
   - Connect NUC dual NICs to switch
   - Test connectivity from developer laptop
   - **Deliverable**: Isolated network operational, NUC reachable

2. **L1.1: Survey Office Infrastructure** (~30 min)
   - Document NUC specs (already known, just formalize)
   - Check NixOS installation status on NUC
   - Verify storage capacity, plan 500GB allocation
   - **Deliverable**: Infrastructure survey document

### Session 2 Tasks (L1.2 - L1.3)

3. **L1.2: Design NixOS Attic Deployment** (~1 hour)
   - Create NixOS configuration module for Attic
   - Plan ext4 storage layout (dedicated partition vs subdirectory)
   - Design dual NIC configuration in NixOS
   - **Deliverable**: Draft NixOS config (see Appendix A for template)

4. **L1.3: Deploy Attic via NixOS Module** (~1 hour)
   - Apply NixOS configuration with `nixos-rebuild switch`
   - Generate RSA signing keys
   - Verify service running
   - **Deliverable**: Attic service operational at http://10.0.0.10:8080

### Session 3 Tasks (L1.4 - L1.8)

5. **L1.4-L1.6: Database, Storage, Keys** (~1 hour)
   - Verify SQLite database initialized
   - Create n3x cache
   - Test push with simple derivation
   - Configure token signing

6. **L1.7: Test Developer Workflow** (~30 min)
   - Generate developer token
   - Configure laptop to use office cache
   - Measure build time improvement

7. **L1.8: Document Setup** (~1 hour)
   - Write `docs/ATTIC-OFFICE-SETUP.md`
   - Include network topology, NixOS config, troubleshooting
   - Share with team

**Estimated total time**: 6-8 hours across 3 sessions

---

## References

- **Technical Design**: `docs/plans/ATTIC-INFRASTRUCTURE-DESIGN.md`
- **Original CI Plan**: `docs/plans/CI-VALIDATION-PLAN.md`
- **Attic Documentation**: https://docs.attic.rs/
- **Attic GitHub**: https://github.com/zhaofengli/attic
- **Nix Binary Caches**: https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-help-stores.html

---

**Plan Status**: Ready for Phase 1 execution
**Next Session**: Start with L1.1 (Survey office infrastructure)
