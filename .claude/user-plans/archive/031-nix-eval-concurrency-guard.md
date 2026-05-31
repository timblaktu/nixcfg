# Plan 031: Nix Evaluation Concurrency Guard for Multi-Session Agents

## Motivation

Concurrent nix evaluations (`nix flake check`, `nix build`, `nix run`) from multiple agent
sessions (Claude Code, OpenCode) frequently cause OOM kills on the development workstation.
Each nix evaluation loads the full flake into memory; two concurrent evaluations can exceed
available RAM. This happened on 2026-04-06 when a single Claude session ran `nix flake check`
as a background task while simultaneously running `nix run '.#collect-image-stats'`.

The problem is worse with multiple concurrent sessions across different worktrees — each
session independently decides to run nix commands without awareness of other sessions'
resource usage.

**Current state**: No automatic guards exist. Concurrency is managed by manual discipline
documented in CLAUDE.md rules. The claudemax/claudepro wrappers detect other instances
(PID check) but do not enforce resource limits. Nix daemon's `max-jobs = 2` limits
concurrent derivation builds but not concurrent evaluations.

## Scope

Cross-project infrastructure in `~/src/nixcfg/claude-runtime/` that protects all worktrees.
Must work for both Claude Code and OpenCode agent sessions.

## Design Constraints

- Must not require changes to nix itself (no patches, no custom daemon config)
- Must work transparently — agents invoke nix normally, guard is automatic
- Must handle both eval-heavy commands (flake check) and build commands (nix build)
- Must work across worktrees (n3x, n3x-infra, n3x-origin, nixcfg, etc.)
- Must be fast when no contention (< 100ms overhead)
- Must degrade gracefully — if guard mechanism fails, nix commands still run
- Guard should queue (block and wait), not reject

## Architecture

### Layer 1: flock-based nix wrapper

A thin wrapper script (`nix-guarded`) that wraps nix commands with `flock`:

```bash
#!/usr/bin/env bash
LOCK_FILE="/tmp/nix-eval-guard.lock"
exec flock --timeout 600 "$LOCK_FILE" nix "$@"
```

This serializes all nix evaluations system-wide. The 600s timeout prevents permanent
deadlocks if a nix process hangs.

**Tradeoff**: This serializes ALL nix commands, including fast ones like `nix store ping`.
Acceptable because the OOM risk is severe and nix commands are rarely sub-second anyway.

**Alternative**: Separate locks for eval vs build (more complex, may not be needed).

### Layer 2: Agent context rules

Add rules to CLAUDE.md and OpenCode agent configs that:
1. NEVER run nix commands as background tasks
2. NEVER run multiple nix commands in parallel (no concurrent Bash tool calls with nix)
3. When needing both `nix flake check` and another nix command, run sequentially

### Layer 3: Wrapper integration

Modify claudemax/claudepro/opencode wrappers to set `PATH` so `nix-guarded` shadows
the real `nix` binary. This makes the guard transparent to all agent sessions.

**Alternative**: Use shell aliases or functions (less reliable across subshells).

## Tasks

| ID | Task | Status | Depends |
|----|------|--------|---------|
| 1 | Create `nix-guarded` wrapper script with flock | TASK:COMPLETE | - |
| 2 | Add wrapper to nixcfg nix package/overlay | TASK:COMPLETE | 1 |
| 3 | Integrate into claudemax/claudepro PATH | TASK:COMPLETE | 2 |
| 4 | Add agent rules to user-global CLAUDE.md | TASK:COMPLETE | - |
| 5 | Add equivalent rules to OpenCode agent configs | TASK:COMPLETE | - |
| 6 | Test: concurrent nix eval from two terminals | TASK:COMPLETE | 3 |
| 7 | Test: agent session respects serialization | TASK:COMPLETE | 3, 4 |
| 8 | Document in nixcfg README or operator notes | TASK:COMPLETE | 6, 7 |

## Task Details

### Task 1: Create nix-guarded wrapper

**DoD**: Shell script at `claude-runtime/bin/nix-guarded` that:
- Acquires flock on `/tmp/nix-eval-guard.lock` with 600s timeout
- Passes all arguments to real nix binary
- Preserves exit code
- Logs contention events to stderr (when lock is contested, not when acquired immediately)
- Handles SIGTERM/SIGINT gracefully (flock auto-releases)

**Considerations**:
- Must find the REAL nix binary (not itself) — use `command -v` or hardcoded path
- Lock file must be world-writable (multiple users) or user-specific
- Consider separate locks for different nix subcommands (eval vs build vs run)
  but start simple with one lock

### Task 2: Nix package/overlay

**DoD**: Nix derivation that builds `nix-guarded` and makes it available as a package.
Could be a `writeShellApplication` in the nixcfg flake or a home-manager module.

### Task 3: PATH integration

**DoD**: claudemax/claudepro wrappers prepend `nix-guarded` directory to PATH so that
`nix` resolves to the wrapper. The wrapper then calls the real nix.

**Risk**: Infinite recursion if wrapper calls `nix` which resolves to itself.
**Mitigation**: Wrapper stores real nix path at setup time, not at invocation time.

### Task 4: Agent rules (CLAUDE.md)

**DoD**: Add to user-global CLAUDE.md:
```
- **NEVER run nix commands concurrently** — do not use background tasks for nix commands,
  do not issue multiple Bash calls with nix in the same response. Always serialize.
  Concurrent nix evaluations cause OOM kills. The flock-based nix-guarded wrapper
  provides automatic serialization, but agents should not rely on it for correctness.
```

### Task 5: OpenCode agent rules

**DoD**: Equivalent rules in `.opencode/rules/` or `.opencode/agents/` configs.

### Tasks 6-7: Testing

**DoD**: Demonstrate that:
- Two concurrent `nix flake check --no-build` from different terminals serialize
- An agent session that tries to run concurrent nix commands is blocked (not OOM'd)
- Lock contention is logged so users can diagnose slow commands
- Timeout (600s) fires and unblocks if a nix process hangs

### Task 8: Documentation

**DoD**: Brief section in nixcfg describing the guard mechanism, how to disable it
(set `NIX_NO_GUARD=1` or similar), and troubleshooting lock contention.

## Future Considerations

- **Per-worktree locks**: If serializing ALL nix commands is too aggressive, could use
  per-worktree locks (hash of working directory as lock file name). This allows concurrent
  nix evals on different projects but prevents concurrent evals on the same project.
- **Memory-aware scheduling**: Instead of simple serialization, check available RAM before
  allowing a nix command. More complex but more efficient.
- **Integration with Plan 030 (tmux monitoring)**: Lock contention events could be surfaced
  in the monitoring dashboard.
- **ISAR build lock**: Separate flock for `kas-build` / `nix run '.'` that prevents
  concurrent ISAR builds (different from nix eval lock).
