# nix-guarded flock leak via fd inheritance across exec

## TL;DR

`nix-guarded` (the flock-based serialization wrapper at
`claude-runtime/bin/nix-guarded.sh`) leaks its lock fd across `exec` into any
long-running process it wraps. The lock is held for the **entire lifetime** of
that process, not just the nix evaluation phase.

The most visible victim is **`mcp-nixos`**: launched once at Claude Code session
startup via the wrapped `nix`, it inherits fd 10 → `/tmp/nix-eval-guard.lock`
with the flock still held, and never releases it until the Claude session
exits. Every other nix invocation in any tmux pane then has to wait
`flock --timeout 600` (10 minutes) before the wrapper gives up and runs nix
anyway. As you accumulate concurrent nix work across panes, contention grows.

This was observed 2026-04-06 during an n3x ISAR rebuild. `nix run '.'` from one
shell sat at 0% CPU for 9+ minutes; `pstree` showed the only child was `flock`
waiting on fd 10; `fuser /tmp/nix-eval-guard.lock` named `mcp-nixos` (PID
2901350, child of the active claude session) as the lock holder; and
`/proc/2901350/fd/10` was a symlink to the lock file.

## Mechanism

Linux flock locks are owned by the kernel **open file description**
(struct file), not by the file descriptor or the process holding it.
Inheritance rules:

- `fork()` → child inherits the same struct file → child shares the lock.
- `exec()` → fd is preserved unless `FD_CLOEXEC` is set → exec'd process
  shares the lock.
- `close(fd)` from the last referencing process → struct file is freed → lock
  released.

The current `nix-guarded.sh` does:

```bash
exec {fd}>"$LOCK"                            # bash assigns fd, e.g. 10
flock --nonblock "$fd" || \
  flock --timeout 600 "$fd" || true          # acquire on the fd
exec "$NIX_REAL" "$@"                        # exec into nix; fd 10 inherited
```

There is no `FD_CLOEXEC` set on the lock fd. So when `nix-guarded` execs into
`nix`, the new `nix` process inherits fd 10 with the lock still held — which
is the *intended* behavior for short-lived nix invocations: the lock stays
held while nix runs, releasing automatically when nix exits and the kernel
reaps fd 10.

The bug surfaces only when the wrapped nix command is itself a launcher for a
**long-lived process**:

```
nix-guarded.sh
  → exec nix run nixpkgs#mcp-nixos --
      → nix builds/fetches mcp-nixos closure
      → exec'd into the python entrypoint of mcp-nixos
          → fd 10 still open, lock still held
          → server runs for the entire Claude session
```

`mcp-nixos` does not perform any nix evaluations after startup — it queries
the public NixOS search API over HTTP. It has no reason to hold a nix
serialization lock at all, yet it does, for the full session duration.

## Why contention grows over a tmux session

The wrapper's fallback path is "wait up to 600s, then proceed anyway":

```bash
if ! flock --nonblock "$fd"; then
  echo "[nix-guard] Waiting for lock..." >&2
  if ! flock --timeout 600 "$fd"; then
    echo "[nix-guard] Lock timeout after 600s, proceeding anyway" >&2
  fi
fi
exec "$NIX_REAL" "$@"
```

So once `mcp-nixos` is holding the lock forever, every subsequent nix
invocation in the same user session sits in `flock` for up to 600s before
proceeding. With one active mcp-nixos that's already a 10-minute floor on
each cold nix call. With multiple concurrent panes each hitting the same
ceiling, you observe the "happening more and more" behaviour: builds that
should start instantly stall for 10 minutes, then proceed normally.

There's also a secondary cascade: if a *second* long-lived service is spawned
through the wrapper (e.g. any nix-launched daemon), it too will inherit and
hold the lock. The leak compounds rather than self-heals.

## Fix options

### Option 1 — Bypass the guard for known long-running services (immediate)

Set `NIX_NO_GUARD=1` in the environment of any nix invocation that is just a
launcher for a long-running service. For mcp-nixos, edit the launch command in
`modules/programs/claude-code/_hm/mcp-servers.nix` (and the equivalent
`opencode` config) to either:

- Prefix the command with `env NIX_NO_GUARD=1`, or
- Use the unwrapped nix path directly (`${pkgs.nix}/bin/nix run ...`).

This is the smallest, safest change. Long-lived services don't need eval
serialization — they don't *do* evals after startup.

### Option 2 — Drop the lock fd before exec in the wrapper (general)

Change the wrapper to set `FD_CLOEXEC` on the lock fd before exec. Bash
doesn't have a direct syntax for this, but two workarounds exist:

```bash
# Workaround A: re-open via /proc to get a fresh fd, then close the original.
# Awkward and racy.

# Workaround B: spawn a subshell to hold the lock for the lifetime of nix,
# then drop the lock fd before exec.
( flock --nonblock "$fd" || flock --timeout 600 "$fd" || true
  exec "$NIX_REAL" "$@" {fd}>&-
)
```

Closing the lock fd before exec means the lock releases the moment nix's
process replaces the wrapper — which **defeats the entire purpose of
serialization**, because nix's eval phase then runs unguarded. This option
only works if you accept that the wrapper provides no real serialization.

### Option 3 — Hold the lock in a sidecar that watches the wrapped process (correct)

Spawn a small holder process that:
1. Acquires the lock.
2. Spawns the real nix as a child via `posix_spawn` with `FD_CLOEXEC` set on
   the lock fd (so nix doesn't inherit it).
3. `wait()`s on the child.
4. Releases the lock when the child exits.

But the holder must distinguish "nix has finished evaluating" from "nix has
exec'd into a long-running daemon that we want to stop tracking". Without nix
integration, the holder cannot tell the difference. So this still over-holds
on `nix run <daemon>`.

The only fully-correct solution requires nix to release the lock itself when
its eval phase ends, which would need a patch to nix or a wrapper that hooks
into nix's lifecycle (e.g. parsing structured logs for "evaluation finished"
events). Not worth it for the threat model.

### Recommendation

**Apply Option 1 immediately for mcp-nixos and any other known long-lived
nix-launched service.** Document the pattern in `nixcfg/CLAUDE.md` so that
new MCP servers or daemons added in the future know to set `NIX_NO_GUARD=1`.

Option 2/3 are not worth pursuing — the wrapper is fundamentally a
short-lived-eval serializer and trying to make it correct for long-lived
children leads to either losing serialization entirely or to half-measures.

## Diagnostic commands

```bash
# Who holds the lock?
fuser /tmp/nix-eval-guard.lock

# Confirm the holder has fd → lock file
ls -l /proc/<PID>/fd | grep nix-eval-guard

# See if nix is stuck waiting on the lock
pstree -p <nix-pid>            # should show: nix(...)---flock(...)

# Verify the holder is your own session (CLAUDE.md process provenance rule)
ps -o ppid= -p <holder-pid>
# walk up the parent chain to the owning claude/opencode process
ls -l /proc/<claude-pid>/cwd

# Workaround until fixed: bypass the guard for one command
NIX_NO_GUARD=1 nix run '.'
```

## Workaround for active sessions

If you hit the leak mid-session and need to unblock:

1. **Bypass for the specific command** (preferred — doesn't break anything):
   `NIX_NO_GUARD=1 nix run '.'`
2. **Restart the Claude session** — kills mcp-nixos (and its leaked fd),
   releasing the lock.
3. **Do not** kill mcp-nixos directly without first verifying it belongs to
   *your* session via the parent-chain walk in `CLAUDE.md` — multiple
   concurrent sessions are common.

## Resolution: Migration to systemd cgroup memory limits (2026-04-14)

The flock-based serialization mechanism was replaced entirely with systemd
cgroup memory limits. This eliminates the fd-leak problem because there is
no lock fd to leak — memory pressure is managed by the kernel cgroup
controller, which is scoped to the process tree and released automatically
when the scope exits.

### New mechanism

The `nix-guarded.sh` wrapper now uses `systemd-run --user --scope` instead
of `flock`:

```bash
exec systemd-run --user --scope --quiet \
  --slice=nix-eval.slice \
  -p MemoryHigh="${NIX_GUARD_MEM_HIGH:-65%}" \
  -p MemoryMax="${NIX_GUARD_MEM_MAX:-75%}" \
  --description="nix $1" \
  -- "$NIX_REAL" "$@"
```

Each nix invocation runs in its own systemd scope with per-process memory
limits (MemoryHigh=65% soft throttle, MemoryMax=75% hard OOM-kill). A shared
`nix-eval.slice` provides an aggregate ceiling (MemoryHigh=80%, MemoryMax=90%)
and integrates with systemd-oomd for pressure-based adaptive killing
(`ManagedOOMMemoryPressure=kill`, 60s duration before action).

### Why this fixes the fd-leak

- **No lock fd**: The cgroup scope is kernel-managed, not fd-based. There
  is no file descriptor for child processes to inherit.
- **Long-lived daemons are safe**: A process launched via `nix run` that
  exec-chains into a daemon (e.g., mcp-nixos) simply inherits the cgroup
  scope's memory limit. It does not block any other nix invocation.
- **Concurrent nix is allowed**: Multiple nix evaluations each get their
  own scope within the shared slice. The memory budget is the constraint,
  not a mutex.

### Environment variable overrides

- `NIX_NO_GUARD=1` — bypass the guard entirely (unchanged from flock era)
- `NIX_GUARD_MEM_HIGH=50%` — override per-scope soft limit
- `NIX_GUARD_MEM_MAX=60%` — override per-scope hard limit

### Diagnostic commands

```bash
# View nix-eval slice status and member scopes
systemctl --user status nix-eval.slice

# Monitor cgroup memory usage in real time
systemd-cgtop

# Journal entries for nix scopes
journalctl --user -u nix-eval.slice

# Check systemd-oomd status (system service)
systemctl status systemd-oomd

# Check earlyoom status (system service)
systemctl status earlyoom
```

### Cleanup performed

- `NIX_NO_GUARD=1` workaround removed from mcp-nixos in
  `modules/lib/shared/mcp-server-defs.nix` (no longer needed)
- `/tmp/nix-eval-guard.lock` is no longer created or referenced
- `util-linux` (flock provider) replaced by `systemd` in wrapper
  runtimeInputs

## References

- `claude-runtime/bin/nix-guarded.sh` — the wrapper template (rewritten for systemd-run)
- `modules/lib/nix-guarded.nix` — Nix package builder
- `modules/programs/claude-code/_hm/lib.nix` — where the wrapper is
  prepended to PATH
- `modules/programs/claude-code/_hm/claude-code.nix` — where nix-eval.slice
  is deployed via home-manager
- `modules/system/types/2-default/default.nix` — systemd-oomd + earlyoom
  NixOS configuration
- Linux cgroups v2 documentation, `memory.high` / `memory.max` controllers
- `systemd-run(1)`, `systemd.slice(5)`, `oomd.conf(5)` man pages
