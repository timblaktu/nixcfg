# Parallel Task Runner Enhancement

**Goal**: Evaluate and implement parallel execution support for `run-tasks`.

**Context**: Current `run-tasks` script executes tasks sequentially from a single plan file. Users want parallel work streams.

**Location**: `home/modules/claude-code/task-automation.nix`

---

## Progress Tracking

| Task | Name | Status | Date |
|------|------|--------|------|
| R1 | Analyze current run-tasks architecture | TASK:PENDING | |
| R2 | Evaluate parallelism options | TASK:COMPLETE | 2026-01-12 |
| R3 | Document recommended pattern | TASK:COMPLETE | 2026-01-12 |
| I1 | (Optional) Implement stream support if needed | TASK:PENDING | |

---

## Current Behavior

The `run-tasks` script in `task-automation.nix`:
1. Finds first `TASK:PENDING` row in Progress Tracking table
2. Sends prompt to Claude: execute task, mark complete
3. Waits for completion
4. Repeats for next `TASK:PENDING`

**Limitation**: Cannot execute multiple tasks concurrently at the `run-tasks` level.

---

## Task R2: Evaluate Parallelism Options

**Status**: TASK:COMPLETE

**Date**: 2026-01-12

### Option A: Multiple Plan Files

**Approach**: Keep run-tasks simple, use multiple plan files for parallel streams.

**Usage**:
```bash
# Terminal 1
run-tasks-max plan-stream-A.md -a

# Terminal 2
run-tasks-max plan-stream-B.md -a
```

**Pros**: No code changes, simple mental model
**Cons**: Requires splitting plans, harder to track overall progress, no coordination

### Option B: Stream Tags in Plan Files

**Approach**: Add stream identifier column to Progress Tracking table.

**Plan Format**:
```markdown
| Task | Stream | Name | Status | Date |
|------|--------|------|--------|------|
| F3   | AMD    | Build QEMU amd64 | TASK:PENDING | |
| F4   | Jetson | Build QEMU arm64 | TASK:PENDING | |
```

**Pros**: Single plan file, clear dependencies visible
**Cons**: Complex implementation, coordination overhead

### Option C: Task-Level Parallelism via Claude (RECOMMENDED)

**Approach**: Design tasks so Claude uses Task tool internally for parallelism.

**Example Task**:
```markdown
### Task F1: Foundation Build (Parallel Subagents)

**Execution Strategy**:
- Sequential: Create structure, configure kas
- Parallel: Spawn subagent for QEMU amd64, spawn subagent for QEMU arm64
- Wait for both subagents to complete
```

**Pros**:
- No run-tasks changes required
- Leverages existing Claude capabilities
- Better context sharing between parallel work
- Intelligent coordination and error handling
- Single quota/session for related work

**Cons**:
- Single run-tasks invocation (can't distribute across API quotas)
- Task complexity increases

---

## Task R3: Document Recommended Pattern

**Status**: TASK:COMPLETE

**Date**: 2026-01-12

### Recommendation: Option C (Task-Level Parallelism)

**Decision**: Use Option C for most use cases. The Isar prototype project (`converix-hsw/.claude/user-plans/001-isar-prototype.md`) demonstrates this pattern.

### When to Use Each Option

| Scenario | Recommended Option |
|----------|-------------------|
| Related parallel work in same project | **Option C** (subagents) |
| Unrelated parallel work, same quota | **Option A** (multiple plan files) |
| Maximize throughput across quotas | **Option A** (multiple terminals) |
| Complex dependencies between streams | **Option C** (subagents) |

### Pattern: Designing Tasks for Internal Parallelism

**Structure**:
```markdown
## Task X: [Name] (Parallel Subagents)

**Status**: TASK:PENDING

**Purpose**: [Goal of this task]

**Execution Strategy**:
```
Claude receives this task
    │
    │ Sequential Phase (if needed):
    ├──► Step 1: [prerequisite work]
    ├──► Step 2: [more prereqs]
    │
    │ Parallel Phase:
    ├──► Subagent A: [track A work]
    │    - Substep A.1
    │    - Substep A.2
    │
    └──► Subagent B: [track B work]
         - Substep B.1
         - Substep B.2

         ▼
    Synthesize/validate results
```

**Subagent A Details**:
[Detailed instructions]

**Subagent B Details**:
[Detailed instructions]

**Definition of Done**:
- [ ] Subagent A complete
- [ ] Subagent B complete
- [ ] Results validated
```

**Key Principles**:

1. **Front-load research** - Parallel research subagents gather information, then synthesize
2. **Sequential prerequisites** - Do setup work before spawning parallel subagents
3. **Independent tracks** - Each subagent track should be self-contained
4. **Explicit subagent types** - Specify `Explore`, `general-purpose`, etc.
5. **Synthesis step** - After parallel work, combine and validate results

### Example: Isar Prototype Plan

The `001-isar-prototype.md` demonstrates this pattern:

| Task | Parallelism | Description |
|------|------------|-------------|
| R1 | 4 parallel subagents | Research existing work, kernel options, NVIDIA repos |
| D1 | None (interactive) | Present findings, get user decisions |
| F1 | 2 parallel subagents | Build QEMU amd64 and arm64 images |
| P1 | 2 parallel subagents | AMD track and Jetson track to hardware boot |

**Result**: 4 tasks instead of 14, with maximum parallelism where beneficial.

---

## Task I1: (Optional) Implement Stream Support

**Status**: TASK:PENDING

**Rationale**: Option C covers most use cases well. Stream support (Option B) may be valuable for:
- Distributing work across multiple API quotas
- Very long-running parallel tracks
- Teams with multiple Claude accounts

**Implementation** (if needed):
1. Add `--stream STREAM_NAME` flag to filter tasks
2. Add `--parallel-streams` flag to spawn multiple processes
3. Update plan file format to include Stream column

**Deferred until**: Clear use case emerges that Option C doesn't handle well.

---

## References

- Current implementation: `home/modules/claude-code/task-automation.nix`
- Example plan using Option C: `converix-hsw/.claude/user-plans/001-isar-prototype.md`
- Claude Task tool documentation
