# Plan 031b: Migrate nix-guarded from flock to systemd cgroup Memory Limits

Supersedes the flock implementation from Plan 031 (all tasks COMPLETE, mechanism deployed
but causing fd-leak problems documented in `docs/nix-guarded-fd-leak.md`).

## Problem Statement

The flock-based `nix-guarded.sh` wrapper serializes all nix commands system-wide via
`/tmp/nix-eval-guard.lock`. This prevents OOM from concurrent evaluations but has a
fundamental design flaw: Linux flock locks are tied to the open file description, and
`exec` preserves fds unless `FD_CLOEXEC` is set. Any long-lived process launched through
the guarded nix (mcp-nixos, apt-cacher-ng from devShells, etc.) inherits the lock fd and
holds it for its entire lifetime, blocking all subsequent nix invocations for up to 600s
(the flock timeout).

**Observed symptoms** (2026-04-06 through 2026-04-14):
- `nix run '.'` stalls at 0% CPU for 9+ minutes (waiting for flock held by mcp-nixos)
- apt-cacher-ng launched from `nix develop` holds lock fd 11 indefinitely
- Lock contention compounds as more long-lived processes accumulate leaked fds
- Workaround: `NIX_NO_GUARD=1` on every command, defeating the guard entirely

**Partial fix applied**: `NIX_NO_GUARD=1` added to mcp-nixos in
`modules/lib/shared/mcp-server-defs.nix`. Does not fix apt-cacher-ng or any future
long-lived process launched through guarded nix.

**Root cause is unfixable within the flock model**: The fd leak is inherent to
flock + exec. Closing the fd before exec releases the lock prematurely (defeats
serialization). Holding it in a sidecar can't distinguish "nix finished evaluating"
from "nix exec'd into a daemon". See `docs/nix-guarded-fd-leak.md` for full analysis.

## Research Findings

### Nix has NO built-in eval memory limits

- `max-jobs`, `cores`, `use-cgroups` control **builds** (sandbox phase), NOT evaluations
- `GC_INITIAL_HEAP_SIZE` env var controls Boehm GC initial heap but NOT max memory
- Upstream PR NixOS/nix#7388 (Oct 2022) proposes `memory-max`/`memory-high` nix.conf
  options — unmerged, build-only, would not help with eval OOM
- No nix-native solution exists or is close to landing

### systemd cgroup limits are the community-recommended approach

Three tiers of sophistication, all available on our system (systemd 256, cgroups v2):

1. **Static byte limits** (`MemoryMax=10G`): Simple, portable, but requires manual tuning
   per machine
2. **Percentage-of-RAM limits** (`MemoryMax=35%`): Supported natively since systemd v231.
   Percentages are relative to **total installed physical memory** (MemTotal), not
   available memory. No wrapper-script math needed — pass directly to `systemd-run -p`.
3. **Pressure-based adaptive limits** (systemd-oomd): Truly dynamic — monitors PSI
   (Pressure Stall Information) and kills processes only when they **actually cause**
   memory pressure. No hardcoded values. Requires systemd v247+ and
   `systemd-oomd.service`.

### System inventory

- **RAM**: 28 GB (MemTotal)
- **systemd**: v256 (NixOS 25.11)
- **cgroups**: v2 unified hierarchy, `memory` controller active
- **systemd-run --user**: functional (verified)
- **earlyoom**: available as `services.earlyoom` in NixOS

## Design

### Approach: Percentage limits + systemd-oomd (belt and suspenders)

Replace the flock wrapper with `systemd-run --user --scope` using **percentage-based
limits** for portability across machines, plus **systemd-oomd** on the shared slice for
truly adaptive pressure-based killing.

### Component 1: `nix-guarded.sh` → `nix-cgroup.sh`

Rename to reflect the new mechanism. The wrapper:

```bash
NIX_REAL="@@NIX_REAL@@"

if [[ "${NIX_NO_GUARD:-}" == "1" ]]; then
  exec "$NIX_REAL" "$@"
fi

# Short description for systemd journal
desc="nix${1:+ $1}"

# Try systemd-run with cgroup memory limits.
# Degrade gracefully if unavailable (containers, CI, no user session).
if command -v systemd-run >/dev/null 2>&1 && \
   systemd-run --user --scope --quiet -- true 2>/dev/null; then
  exec systemd-run --user --scope --quiet \
    --slice=nix-eval.slice \
    -p MemoryHigh="${NIX_GUARD_MEM_HIGH:-30%}" \
    -p MemoryMax="${NIX_GUARD_MEM_MAX:-35%}" \
    --description="$desc" \
    -- "$NIX_REAL" "$@"
fi

# Fallback: run unguarded
exec "$NIX_REAL" "$@"
```

**Key design decisions**:
- **Percentage defaults** (`30%`/`35%`): On a 28GB system, this is ~8.4G/~9.8G per eval.
  A single nixpkgs eval typically peaks at 4-6G. These defaults give headroom while
  preventing a single runaway eval from consuming the system.
- **Environment variable overrides** (`NIX_GUARD_MEM_HIGH`, `NIX_GUARD_MEM_MAX`): Allow
  per-machine or per-session tuning without wrapper changes. Accepts any value systemd
  accepts (bytes, percentages, `infinity`).
- **`NIX_NO_GUARD=1` bypass preserved**: For containers, CI runners, or when the user
  explicitly wants no guard.
- **Graceful fallback**: If `systemd-run --user` fails (no user session, inside a
  container), run nix unguarded. Same philosophy as the flock fallback.
- **No serialization**: Concurrent evals are allowed. The memory budget is the constraint,
  not a mutex. Two concurrent evals each get their own 30%/35% scope — if the system can
  handle it, they run in parallel. If not, the cgroup OOM killer handles it cleanly.

### Component 2: `nix-eval.slice` (systemd user unit)

Deployed via home-manager. Provides a shared memory ceiling for ALL concurrent nix
processes and integrates with systemd-oomd for adaptive pressure-based killing.

```ini
[Slice]
# Shared ceiling for all concurrent nix invocations.
# Percentage of total physical RAM (MemTotal).
MemoryHigh=60%
MemoryMax=75%

# systemd-oomd integration: kill the most memory-hungry nix scope
# when the slice experiences sustained memory pressure (PSI-based).
# This is the truly adaptive layer — no hardcoded thresholds needed
# because oomd reacts to actual pressure, not absolute values.
ManagedOOMMemoryPressure=kill
```

**Limit rationale** (28GB system as reference):

| Limit | Value | Effective (28GB) | Purpose |
|-------|-------|-------------------|---------|
| Per-scope MemoryHigh | 30% | ~8.4G | Soft: throttle a single eval that's getting large |
| Per-scope MemoryMax | 35% | ~9.8G | Hard: kill a single runaway eval |
| Slice MemoryHigh | 60% | ~16.8G | Soft: throttle when total nix memory is high |
| Slice MemoryMax | 75% | ~21G | Hard: kill when total nix memory is critical |
| System remainder | ≥25% | ≥7G | For Claude, tmux, browsers, apt-cacher-ng, etc. |

All percentages scale automatically to any machine's RAM. No per-machine tuning needed.

**oomd behavior**: When the slice's PSI `some` pressure exceeds the default threshold
(configured in `systemd-oomd.service`, typically 60% for 30s), oomd selects the
highest-memory descendant scope (i.e., the most expensive nix invocation) and SIGKILLs it.
This is the adaptive layer — it only fires when there's actual pressure, regardless of
absolute memory values.

### Component 3: systemd-oomd (NixOS service)

```nix
services.systemd.oomd.enable = true;
# or the simpler:
systemd.oomd.enable = true;
```

NixOS 25.11 has systemd-oomd support. It monitors PSI stats and acts as the truly
adaptive safety net. Combined with `ManagedOOMMemoryPressure=kill` on the slice, it
provides pressure-based killing without any hardcoded thresholds.

### Component 4: earlyoom (system-wide safety net)

```nix
services.earlyoom = {
  enable = true;
  freeMemThresholdPercent = 5;
  freeSwapThresholdPercent = 5;
};
```

Last line of defense. If systemd-oomd and cgroup limits both fail to prevent OOM (e.g.,
memory consumed by processes outside nix), earlyoom kills the most memory-hungry process
before the system locks up.

### Component 5: Cleanup

- Remove `NIX_NO_GUARD=1` from mcp-nixos in `mcp-server-defs.nix` (no longer needed —
  the cgroup scope doesn't leak fds, and long-lived daemons within their scope just have
  a memory cap, not a lock)
- Update `docs/nix-guarded-fd-leak.md` with resolution
- Update CLAUDE.md rules: remove flock-specific language, update `NIX_NO_GUARD`
  documentation to reference new mechanism
- Remove `/tmp/nix-eval-guard.lock` references

## Files to Change

| File | Change |
|------|--------|
| `claude-runtime/bin/nix-guarded.sh` | Replace flock logic with `systemd-run --scope` |
| `modules/lib/nix-guarded.nix` | Update `runtimeInputs` (systemd instead of util-linux), expose memory limit options, generate `nix-eval.slice` user unit |
| `modules/lib/shared/mcp-server-defs.nix` | Remove `NIX_NO_GUARD = "1"` from mcp-nixos env |
| `modules/programs/claude-code/_hm/lib.nix` | No change needed — already prepends `nixGuardedPkg` to PATH |
| `docs/nix-guarded-fd-leak.md` | Update with resolution section |
| NixOS system config (host module) | Enable `systemd.oomd` and `services.earlyoom` |
| CLAUDE.md (user-global) | Update nix serialization rules to reference cgroup guard |

## Tasks

| ID | Task | Status | Depends |
|----|------|--------|---------|
| 1 | Rewrite `nix-guarded.sh` → systemd-run wrapper | TASK:COMPLETE | - |
| 2 | Update `nix-guarded.nix` module (runtimeInputs, options, slice unit) | TASK:COMPLETE | 1 |
| 3 | Add `nix-eval.slice` user unit via home-manager | TASK:COMPLETE | 2 |
| 4 | Enable systemd-oomd + earlyoom in NixOS host config | TASK:COMPLETE | - |
| 5 | Remove mcp-nixos `NIX_NO_GUARD` workaround | TASK:COMPLETE | 1 |
| 6 | Update docs and CLAUDE.md rules | TASK:COMPLETE | 1 |
| 7 | Test: concurrent evals stay within memory budget | TASK:COMPLETE | 3, 4 |
| 8 | Test: long-lived daemon (apt-cacher-ng) does NOT block nix | TASK:COMPLETE | 1 |
| 9 | Test: `NIX_NO_GUARD=1` bypass still works | TASK:COMPLETE | 1 |
| 10 | Test: graceful fallback in container/CI (no systemd-run) | TASK:COMPLETE | 1 |
| 11 | Clean up old flock lock file references | TASK:COMPLETE | 7, 8 |

## Task Details

### Task 1: Rewrite wrapper script

**DoD**: `claude-runtime/bin/nix-guarded.sh` replaced with systemd-run logic as specified
in Component 1 above. Template still uses `@@NIX_REAL@@` substitution. `NIX_NO_GUARD=1`
bypass preserved. Graceful fallback if systemd-run unavailable. Environment variable
overrides for memory limits (`NIX_GUARD_MEM_HIGH`, `NIX_GUARD_MEM_MAX`).

### Task 2: Update nix module

**DoD**: `modules/lib/nix-guarded.nix` updated:
- `runtimeInputs` changed from `[ pkgs.util-linux ]` to `[ pkgs.systemd ]`
- Script template updated
- Consider exposing memory limit defaults as module options for per-host tuning
- Consider renaming package from "nix-guarded" to "nix-cgroup" (but keep PATH shadow
  as `bin/nix`)

### Task 3: nix-eval.slice unit

**DoD**: Home-manager generates `~/.config/systemd/user/nix-eval.slice` with:
- `MemoryHigh=60%`, `MemoryMax=75%`
- `ManagedOOMMemoryPressure=kill`
- Unit enabled and started via home-manager activation

### Task 4: System services

**DoD**: NixOS host config enables:
- `systemd.oomd.enable = true` (monitors PSI, acts on `ManagedOOMMemoryPressure`)
- `services.earlyoom.enable = true` with 5% free thresholds
- Verify both services active after rebuild

### Task 5: Remove mcp-nixos workaround

**DoD**: Remove `NIX_NO_GUARD = "1"` and associated comment block from
`modules/lib/shared/mcp-server-defs.nix` (nixos.mkConfig.env). The cgroup-based guard
doesn't leak fds, so long-lived MCP servers no longer need to bypass it.

### Task 6: Documentation

**DoD**: Update `docs/nix-guarded-fd-leak.md` with a "Resolution" section documenting:
- The migration from flock to cgroup limits
- How the new mechanism works
- Environment variable overrides
- Diagnostic commands (`systemctl --user status nix-eval.slice`,
  `systemd-cgtop`, `journalctl --user -u nix-eval.slice`)

Update user-global CLAUDE.md: replace flock-specific serialization language with
cgroup-based guidance. Keep the "never run nix concurrently" rule as a soft guideline
(agents should still prefer sequential nix commands to avoid cgroup pressure, even
though the hard guard now allows concurrency within the memory budget).

### Tasks 7-10: Testing

**Task 7 DoD**: Run two concurrent `nix flake check --no-build` in separate terminals.
Both should start immediately (no flock wait). Monitor with `systemd-cgtop` — both
should be under their respective scope limits. Total slice memory should stay under 60%.

**Task 8 DoD**: Enter `nix develop` devShell, verify apt-cacher-ng starts. Run a
separate `nix build` command — it should start immediately with no delay. Verify
apt-cacher-ng does NOT hold any lock fd. Verify nix build runs in its own cgroup scope.

**Task 9 DoD**: `NIX_NO_GUARD=1 nix store ping` runs without systemd-run wrapping.

**Task 10 DoD**: Inside a container or with `systemd-run --user` disabled, nix commands
still work via the fallback path. Test by temporarily making the `systemd-run` probe
fail.

### Task 11: Cleanup

**DoD**: Remove `/tmp/nix-eval-guard.lock` if it exists. Remove any references to the
lock file path in code, docs, and CLAUDE.md. Keep `NIX_NO_GUARD` env var (still useful
for bypassing cgroup wrapping in edge cases).

## Risk Assessment

- **Low risk**: Wrapper fallback ensures nix always works even if systemd-run fails
- **Medium risk**: Per-scope `MemoryMax=35%` may be too tight for very large flake
  evaluations (e.g., full NixOS system build with many overlays). Mitigation:
  `NIX_GUARD_MEM_MAX=50%` override, or adjust defaults after testing.
- **Low risk**: systemd-oomd may be too aggressive on short pressure spikes. Mitigation:
  `ManagedOOMMemoryPressureDurationSec=20s` (systemd v257+) or rely on MemoryHigh
  throttling to smooth pressure before oomd acts.
- **No risk to CI**: CI runners don't have user systemd sessions — the wrapper falls
  back to unguarded nix, which is correct (CI runs one job at a time per runner).
