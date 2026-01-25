# User-specific Claude Code Configuration for User's Anthropic MAX Account

## ⚠️ CRITICAL RULES ⚠️
- **MANDATORY RESPONSE ENDING**: EVERY response MUST end with a ready-to-paste prompt for the next session after context is cleared. NO EXCEPTIONS.
- NEVER clutter this user-global CLAUDE.md file with project- or session-specific content, e.g. tasks, status, etc
- **NEVER include AI attribution in commit messages** - NO "Generated with Claude Code", NO "Co-Authored-By: Claude", NO emoji robots, NO links to claude.com. Commit messages must appear entirely human-authored.
- **Commit messages focus on technical content** - describe what changed and why
- ALWAYS use the following date/time stamp format for time annotations: `date +%Y-%m-%d\ %H:%M:%S\ %Z`
- ALWAYS use rg and fd commands with Bash tool for file searching (never grep/find or Search/Find tools)
- ALWAYS ensure any generated shell commands support both bash AND zsh syntaxes
- ALWAYS properly escape or quote special shell characters when generating commands
- SCREENSHOTS folder is `/mnt/c/Users/tblack/OneDrive/Pictures/Screenshots 1`
- NEVER create files unless absolutely necessary
- ALWAYS prefer editing existing files to creating new ones
- ALWAYS add documentation to existing markdown files instead of creating new files 
- ALWAYS ASK where to add documentation if there is significant ambiguity or uncertainty
- **ALWAYS ASK FOR HELP WITH AUTHENTICATION ISSUES** - If encountering ANY auth issues (GitHub, GitLab, Bitwarden, SOPS, SSH, etc.), IMMEDIATELY ask the user for help rather than trying to work around them
- **ALWAYS single-quote Nix derivation references** - When running `nix build`, `nix flake check`, or similar commands with derivation paths like `.#thing`, ALWAYS use single quotes: `nix build '.#thing'`. Unquoted paths like `.#thing` fail in zsh due to glob expansion.
- **When working with nix or NixOS, use mcp-nixos MCP server tools** to research and verify packages and their options BEFORE making any configuration changes. Why this is critical:
  1. NixOS and Home Manager options change between versions
  2. Options can be deprecated, renamed, or removed (e.g., `programs.zsh.initExtra` → `programs.zsh.initContent`)
  3. Different modules may have different option names (e.g., bash uses `initExtra`, zsh uses `initContent`)
  4. Making assumptions leads to evaluation warnings and errors
- NEVER sudo long-running commands with timeout parameters (causes Claude Code crashes with EPERM errors and inability to cleanup).
  - This rule does NOT apply to non-sudo builds like kas-container, nix-build, etc.
  - ISAR/Yocto/BitBake builds: Incremental builds typically complete in 5-10 minutes due to sstate-cache. Full clean builds of Debian-based ISAR images are also fast (minimal compilation). Don't overestimate build times.
  - Only defer to user for truly unpredictable long-running sudo commands.
- **NEVER resolve merge conflicts automatically** - When encountering git merge conflicts, ALWAYS stop immediately and ask the user to review conflicts. Show conflicted files and let user make resolution decisions.
- **NEVER use `git add -f` or `--force`** - If `git add` fails because a file matches .gitignore, that's intentional. Do not bypass gitignore patterns. If you believe a file should be tracked, ask the user first.
- **Respect .gitignore** - Files matching gitignore patterns (like `.claude/`, `CLAUDE.md`) should NOT be committed. Plan files and session state work locally without git tracking.
- **ALL github.com/timblaktu repositories are USER-OWNED**
  - When encountering issues with timblaktu repos, **ALWAYS use fd to locate the local working tree (typically cloned at ~/src) and work there in an appropriate branch**, instead of changing flake inputs to avoid them.
- ALWAYS use `echo "$WSL_DISTRO_NAME"` to determine if you're running in WSL, and what WSL instance you and/or your MCP servers are running in.
- If running in WSL, you can access other WSL instances' rootfs mounted at `/mnt/wsl/$WSL_DISTRO_NAME/`
- **ONE TASK PER SESSION for multi-phase plans** - When executing a plan with multiple phases/tasks, complete ONE task per chat session, then stop and wait for next session. Do NOT proceed to the next task after completing one. This ensures:
  - Clean context for each task
  - Clear checkpoint/rollback points
  - User approval between phases
  - Proper documentation of each task's results
- **ALWAYS stage changes before nix commands** - Before running `nix build`, `nix flake check`, or any Nix command that evaluates the flake, ALWAYS `git add` any modified files that are part of the flake. Nix only sees staged/committed changes, not unstaged working tree changes.
- **Task summaries must be CONCISE and COMPREHENSIVE** - When summarizing completed work to the user:
  - Be explicit about SCOPE: If a task defined "implement X for machine A", say "implemented X for machine A" not just "implemented X" (which implies all machines)
  - List ALL artifacts created/modified with full paths
  - State what was NOT done if scope was limited (e.g., "Note: other machines like qemu-arm64 will be added in later tasks")
  - Include verification steps performed (e.g., "verified with `nix eval '.#lib.machines.machineNames'`")
  - This builds confidence that the right work was done before user approves and moves on

## CI/CD and Testing Philosophy

**CRITICAL PREFERENCE**: CI/CD is just orchestration - everything must be reproducible everywhere.
- Tests that "only run in CI" or "only run locally" indicate a design problem
- If something can run in CI, it should run identically on any developer machine with the same inputs/environment
- Use feature flags, environment detection, or pytest skip conditions based on available services
- Never create CI-specific test logic or separate test suites for CI vs local
- Example: E2E tests should check for required services (Typesense, VLM endpoints) and skip gracefully if unavailable, but the test code itself is identical everywhere

## Custom Memory Management Commands
- /nixmemory (alias: /usermemory, /globalmemory) - Opens user-global memory file in editor (like /memory but always user-scoped)
- `/nixremember <content>` (alias: /userremember, /globalremember) - Appends content to memory (like # command but for Nix-managed memory)

### Important Notes
- These commands write to `/home/tim/src/nixcfg/claude-runtime/.claude-max/CLAUDE.md` (this file)
- Changes auto-commit to git and rebuild to propagate to all accounts
- Built-in `/memory` and `#` commands will fail on read-only files - use the /nix* versions instead
- This file is the single source of truth for all Claude Code account configurations

## Plan File Conventions

**Canonical location for plan files**: `.claude/user-plans/` directory in each project

**Naming conventions**:
- Numbered prefix for sequenced plans: `001-name.md`, `002-name.md`, etc.
- Lower numbers execute first; higher numbers are deferred/later phases
- Use descriptive names: `001-isar-prototype.md`, `002-isar-ci-design.md`

**Plan file format** (for `run-tasks` compatibility):
- Progress Tracking table with `TASK:PENDING` / `TASK:COMPLETE` status tokens
- Clear Definition of Done for each task
- Execution Strategy diagrams for tasks with parallel subagents

**Task ID naming rules** (CRITICAL for `run-tasks` log file generation):
- Task IDs appear in first column of Progress Tracking table (e.g., `R0.1`, `D1`, `P2.3`)
- Task Names appear in second column - these are used for log filenames
- **AVOID these characters in Task Name column**: `/` `:` `\` `*` `?` `"` `<` `>` `|` (filesystem-unsafe)
- Good: `R0.2.01 | Terms_AMD_Platform-Users-Guide`
- Bad: `R0.2.01 | Terms: AMD/Platform-Users-Guide` (contains `:` and `/`)
- The script sanitizes names but descriptive safe names are preferred
- Use underscores `_` or hyphens `-` as separators instead of `/` or `:`

**Parallelism pattern** (Option C - recommended):
- Design tasks for internal parallelism via Claude Task tool
- Spawn parallel subagents within a single task
- Sequential prereqs → Parallel work → Synthesis
- See `nixcfg/.claude/user-plans/parallel-task-runner-enhancement.md` for details

**Interactive tasks**:
- Tasks requiring user decisions should be marked as "Interactive"
- Claude presents options, waits for explicit user approval
- Do NOT proceed without documented user decisions

**Task Reset Protocol**:
When a task fails, is rejected, or needs re-execution:
1. **Update Status**: Change `TASK:COMPLETE` back to `TASK:PENDING` in Progress Tracking table
2. **Clear Artifacts**: Delete or rename ALL artifacts listed in the task's "Definition of Done"
3. **Add Reset Note**: Document why the task was reset in the task section with date and reason

Why this matters: Stale artifacts from failed/incomplete runs cause subsequent runs to falsely detect completion. The model sees the artifact exists and may conclude work is done without verifying quality/completeness.

Example reset note format:
```
**Reset History**:
- 2026-01-13: Reset - previous run created doc but actual work not performed
  - Deleted: `path/to/artifact.md`
  - Reason: Task requires X, previous run only did Y
```

## Task Artifact Management

**Critical Rule**: When `/next-task` or any task runner finds a PENDING task:
- Check if artifacts from "Definition of Done" already exist
- If artifacts exist but task is PENDING, treat as **conflict**:
  - Artifacts may be stale from a failed previous run
  - Do NOT assume existing artifacts mean task is complete
  - Delete stale artifacts before proceeding, or ask user
- Never skip task execution just because an output file exists

**When resetting tasks**:
- ALL artifacts listed in "Definition of Done" MUST be deleted or renamed
- Document the reset with date and reason in the task section
- This prevents false completion detection on re-run

## Active Configuration

### Model
- Default: sonnet
- Debug mode: disabled

### Sub-Agents
- code-searcher

### Slash Commands
- /documentation generate-readme
    - /documentation api-docs
- /security audit
    - /security secrets-scan
- /refactor extract-function
    - /refactor rename-symbol
- /context cleanup
    - /context save
    - /context load

### Active Hooks
- Security checks: 
- Auto-formatting: 
- Linting: 
- Testing: 
- Git integration: 
- Logging: 
- Notifications: 

## Performance Tips

- Use sub-agents for specialized tasks to reduce token usage
- Leverage slash commands for common operations
- Enable caching where appropriate
- Use project overrides for context-specific settings

## Troubleshooting

- Check logs at: ~/.claude/logs/tool-usage.log
- Debug mode: Set `programs.claude-code.debug = true`
- MCP server issues: Check `/tmp/claude_desktop.log` and `~/AppData/Roaming/Claude/logs/`
- Hook failures: Review hook timeout settings
- MCP Documentation: See `home/modules/README-MCP.md` for detailed troubleshooting

## General Learnings

### ISAR Test Framework
- **Decision**: Use NixOS VM Test Driver (nixos-test-driver) with ISAR-built .wic images - NOT Avocado
- ISAR builds images (BitBake/kas produces .wic files), Nix provides test harness
- Tests run on host NixOS/Nix environment, not inside kas-container
- Test images need `nixos-test-backdoor` package - include via `kas/test-overlay.yml`
- Build test images: `kas-container --isar build kas/converix.yml:kas/machine/qemu-amd64.yml:kas/test-overlay.yml:kas/image/minimal-base.yml`
- VM script derivations must NOT use `run-<name>-vm` pattern in derivation name (conflicts with nixos-test-driver regex)
- nixos-test-driver backdoor protocol: service prints "Spawning backdoor root shell..." to /dev/hvc0 (virtconsole)
- Key doc: `isar/.research/CRITICAL-DECISION-SUMMARY.md`

### kas-container Build Process
- **Claude CAN and SHOULD run kas-container builds directly** - prefer using subagents to minimize context usage
- **Monitoring strategy**: Run builds in foreground, periodically check progress via `build/tmp/deploy/images/` or bitbake logs rather than reading all output
- **If a build gets stuck/killed**: Check for orphaned processes with `sudo podman ps -a` (kas runs privileged containers)
- **Cleanup orphaned containers**: `sudo podman rm -f <container_id>`
- **Cleanup orphaned processes**: Check `pgrep -a podman` and `pgrep -a conmon`
- **WSL cgroup issue**: Podman shows warnings about cgroupv2/systemd - containers run but `podman ps` as user may not see root containers
- **Build progress**: Check `build/tmp/deploy/images/` for output, not just console (build may be in WIC generation)

### WIC Generation Hang Issue (ROOT CAUSE IDENTIFIED - 2026-01-21)
- **Symptom**: Build hangs at 96% during `do_image_wic` task in WSL2
- **Root cause**: `sgdisk` (gptfdisk) calls global `sync()` in `DiskSync()` method
  - Source: [gptfdisk diskio-unix.cc](https://github.com/samangh/gptfdisk) `DiskIO::DiskSync()`
  - The `sync()` iterates ALL mounted filesystems including WSL2's 9p mounts (`/mnt/c`)
  - 9p filesystem sync hangs indefinitely, blocking the entire syscall
  - Process enters D-state (uninterruptible I/O sleep) - cannot be killed
- **The bug**: `sync()` is unnecessary - `fsync(fd)` on the specific disk is sufficient
- **Proper fix**: Patch gptfdisk to remove `sync()` call, keep only `fsync(fd)`
  - Create ISAR recipe patch for gptfdisk package
  - Or use `sfdisk` instead where possible (WIC already uses it for some operations)
- **Temporary workaround (VERIFIED 2026-01-21)**: Unmount ALL 9p filesystems before building:
  ```bash
  sudo umount -l /mnt/c /usr/lib/wsl/drivers
  ```
  - `/mnt/c` is the Windows drive mount
  - `/usr/lib/wsl/drivers` is another 9p mount that was causing hangs even when /mnt/c was unmounted
- **Kernel stack trace**: `super_lock → iterate_supers → ksys_sync → sync()`
- **Cleanup after hang** (requires WSL restart for D-state processes):
  ```bash
  # After wsl --shutdown from PowerShell:
  sudo rm -rf build/tmp/schroot-overlay/*/upper/tmp/*.wic/
  sudo podman rm -f $(sudo podman ps -aq) 2>/dev/null
  ```
- **TODO**: Create ISAR patch for gptfdisk to use syncfs(fd) or just fsync(fd) instead of sync()
- **kas-build remount fix (2026-01-22)**: The `kas-build` wrapper in ISAR flake.nix must remount 9p filesystems with `-o metadata,uid=$(id -u),gid=$(id -g)` options. Without these, WSL defaults to `fmask=111` which strips execute permissions, breaking `clip.exe`, `powershell.exe`, and neovim clipboard integration.

### ISAR Test Parity with n3x (Plan 005)
- **Approach**: Parameterized builder - ISAR machines consume test scripts from n3x
- **Test source of truth**: n3x repository exports `lib.testScripts`, ISAR imports via flake
- **Architecture**: n3x is primary project; ISAR is secondary POC. DRY principle - define tests once in n3x.
- **Sharing mechanism**:
  1. n3x exports `lib.testScripts` in flake.nix (raw Python strings)
  2. ISAR adds n3x as flake input
  3. ISAR uses `n3x.lib.testScripts.k3sCluster` in its `mkIsarTest` wrapper
  4. Test scripts are just strings - same API (wait_for_unit, succeed, etc.)
  5. Machine definitions differ per project; test logic is shared
- **k3s for ISAR**: Static binary (mimic NixOS) with dependencies: kmod, socat, iptables, nftables, iproute2, ipset, bridge-utils, ethtool, util-linux, conntrack-tools
- **Network config**: netplan + systemd-networkd (matches NixOS approach)
- **Plan file**: `.claude/user-plans/005-isar-test-parity-with-n3x.md`
- **Session 2 ready**: Extract Python testScript strings from n3x, create tests/lib/test-scripts.nix, export via lib.testScripts

### Claude Task Runner Artifacts
- `.claude-task-logs/` and `.claude-task-state` are local session state
- Should be gitignored explicitly (pattern `**/.claude` doesn't match `.claude-task-*` prefix)
- Generated by automated task runner scripts, not manually created
- ALWAYS stage local changes that are included in any flake-based nix build process before calling the nix commands yourself or instructing the user to.

### Jetson Orin Nano OTA Bring-up (Plan 006) - 2026-01-22
- **Fork**: `~/src/jetpack-nixos` branch `feature/pluggable-rootfs` adds external rootfs support
- **Key addition**: `lib.mkExternalRootfsConfig { som, carrierBoard, rootfsTarball }` helper function
- **Flash script**: Built with `--impure` nix build (rootfs path is local file, not in nix store)
- **L4T packages**: ISAR recipes `nvidia-l4t-core_36.4.4.bb` and `nvidia-l4t-tools_36.4.4.bb` download .deb from NVIDIA repo
- **Cross-build bypass**: `nvidia-l4t-cross-build.bbclass` creates marker file `/opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall` to skip preinst platform check
- **Jetson produces tar.gz not WIC**: `IMAGE_FSTYPES = "tar.gz"` - L4T flash tools handle partitioning
- **Output path ephemeral**: `/tmp/test-initrd-flash` is cleared on reboot; must rebuild flash script after WSL restart
- **12 cleanup tasks (C1-C12)**: Pre-hardware testing improvements identified in review session
- **Plan file**: `.claude/user-plans/006-jetson-orin-nano-ota-bringup.md`

### Nix-ISAR Integration Architecture (2026-01-23)
- **Reference doc**: `nix-isar-integration-guide-revised.md` (user's Downloads)
- **isar-k3s uses hybrid approach** combining both patterns from the guide:
  - **Approach 1 (Import Artifacts)**: Jetson flash script imports ISAR rootfs tarball; nix/tests/ consume .wic images
  - **Approach 2 (FHS Environment)**: kas-container provides containerized FHS-equivalent (battle-tested)
- **Pattern mapping**:
  - `mkJetsonFlashScript` = Guide's "Pattern 2: External Rootfs" (reversed: ISAR rootfs + Nix flash tooling)
  - `nix/tests/*.nix` = Guide's "Pattern 1: Import artifacts for testing"
- **Validated decisions**: Hybrid approach is legitimate; separation of build system (kas-container) vs test harness (Nix) is architecturally sound
- **Potential improvements**:
  - Artifact pinning with `requireFile`/`fetchurl` for reproducibility
  - CI artifact caching via `fetchurl` from CI storage
  - SDK export following Guide's "Pattern 3: Yocto SDK as Build Input"
- **Unique contribution**: WSL `kas-build` wrapper handling sgdisk sync() hang - not covered in guide, could contribute back
- **Key insight**: kas-container is functionally equivalent to guide's `buildFHSUserEnvBubblewrap` but containerized

### VDE Multi-VM Networking for NixOS Test Driver (2026-01-24)
- **Use case**: Multi-VM tests (e.g., SWUpdate network OTA) with VDE virtual ethernet
- **VDE switch initialization timing**:
  - VDE switch in `--hub` mode needs actual traffic to learn MAC addresses before forwarding works
  - Add 3s initial delay after VMs boot before attempting ping/connectivity tests
  - Use simple ping retries (5 attempts, 2s delay) instead of arping for Layer 2 discovery
- **socat vs python3 http.server**:
  - Use `socat TCP-LISTEN:8080,fork,reuseaddr EXEC:/tmp/http-handler.sh` for reliable HTTP serving in VMs
  - python3 http.server can have buffering issues in automated test contexts
- **pkill cleanup race conditions**:
  - Use `execute()` instead of `succeed()` for pkill commands - process may already be gone
  - `succeed()` fails the test if pkill returns non-zero (no matching process)
- **Test architecture pattern**:
  - Server VM: configure IP, start services, generate test artifacts (certs, bundles)
  - Target VM: configure IP, wait for connectivity, fetch and apply updates
  - Use VDE VLAN with static IPs (e.g., 192.168.1.1/192.168.1.2) for deterministic networking
- **Working SWUpdate test suite** (all pass as of 2026-01-24):
  - `test-swupdate-apply`: Apply .swu bundle to inactive partition
  - `test-swupdate-boot-switch`: Reboot between A/B partitions
  - `test-swupdate-bundle-validation`: Validate .swu structure and CMS signatures
  - `test-swupdate-network-ota`: Two-VM OTA with HTTP server

### Unified K3s Platform Architecture (Plan 010) - 2026-01-24
- **Decision**: Merge n3x and isar-k3s into single repo with pluggable backends
- **Supersedes**: Plan 009 Q1 (Federation approach rejected)
- **Rationale**: Both repos do the SAME THING conceptually - only difference is rootfs/kernel generation
- **Architecture**:
  - `lib/` = SINGLE SOURCE OF TRUTH (Nix abstractions for machines, k3s, network, images, tests)
  - `backends/nixos/` = NixOS implementation (consumes lib/*, produces NixOS config)
  - `backends/isar/` = ISAR implementation (generates kas config from lib/*, BitBake reads Nix vars)
- **Key pattern**: Nix injects configuration into BitBake via kas `local_conf_header`:
  ```nix
  kasOverride.local_conf_header.k3s-config = ''
    K3S_ROLE = "${k3sConfig.role}"
    K3S_CLUSTER_CIDR = "${k3sConfig.clusterCidr}"
  '';
  ```
- **BitBake recipes become thin** - just read ${K3S_*}, ${NETWORK_*}, ${MACHINE_*} variables
- **What gets unified**:
  - Machine definitions (n3x hosts/ + isar-k3s kas/machine/ → lib/machines/)
  - K3s configuration (modules/roles/ + recipes-core/k3s/ → lib/k3s/)
  - Network profiles (modules/network/ + kas/network/ → lib/network/)
  - Test scenarios (tests/lib/ + nix/tests/ → lib/tests/)
- **Migration phases** (preserve passing tests at each step):
  - Phase 0: Baseline documentation, create branch
  - Phase 1: Extract lib/ abstractions from n3x
  - Phase 2: Create NixOS backend consuming lib/
  - Phase 3: Import ISAR as backend, wire to lib/
  - Phase 4: Unify test suite across backends
  - Phase 5: Cleanup, documentation
- **Target repo**: ~/src/n3x becomes unified repo (feature/unified-platform branch)
- **Plan file**: `.claude/user-plans/010-unified-k3s-platform.md`
- **Git Worktrees** (created 2026-01-24, ACTIVELY USE THROUGHOUT):
  ```
  ~/src/n3x/                 # feature/unified-platform (active development)
  ~/src/n3x-baseline/        # main branch (reference for comparison)
  ~/src/isar-k3s/            # feature/jetson-orin-nano-ota (active development)
  ~/src/isar-k3s-baseline/   # main branch (reference for comparison)
  ```
  - **Use worktrees proactively**: Check baseline before/after changes, run parallel tests, diff against main
  - **ISAR cache sharing**: `isar-k3s-baseline/build/{sstate-cache,downloads}` are symlinks to main repo
  - **See plan file "Worktree Usage Throughout Plan 010" section** for detailed workflow patterns per phase