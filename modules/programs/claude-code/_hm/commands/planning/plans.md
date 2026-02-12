Generate a high-level summary of all plans in this repository.

## Instructions

1. Find all plan files in `.claude/user-plans/` (exclude `archive/`) using: `fd -t f -e md . .claude/user-plans/ --max-depth 1`
   Also note the existence of archived plans: `fd -t f -e md . .claude/user-plans/archive/`

2. For each **active** plan file, extract:
   - Plan number/name (from filename)
   - Status: count `TASK:COMPLETE` vs total tasks from the progress table
   - Brief description (from title or first paragraph)
   - **Remaining tasks**: For each non-COMPLETE task, extract the task number, name, and status
     (`PENDING`, `IN_PROGRESS`, `BLOCKED`, `DEFERRED`) from the progress table

3. **Detect terminal width**: Run `echo "$CLAUDE_TERMINAL_WIDTH"` to get the width.
   This env var is set by the wrapper script from the real TTY before Claude launches.
   Do NOT use `$COLUMNS` or `tput cols` — these return wrong values in Claude's subprocess.
   Fallback: 120 if `CLAUDE_TERMINAL_WIDTH` is empty or 0.

4. Present active plans as a markdown table that **fills the available terminal width**:
   - Use abbreviated headers: `Plan | St | Description`
   - **Expand the Description column** to use all remaining horizontal space
   - If still too wide: drop Description column, list descriptions below table

5. **Under each active plan row**, add an indented bullet list of remaining tasks:
   - Format: `  - T{num}: {task name} [{status}] {blocker note if any}`
   - Only show non-COMPLETE tasks
   - Use short status tags: `[PEND]`, `[WIP]`, `[BLOCKED]`, `[DEFER]`

6. Use these status indicators for the plan-level St column:
   - All tasks complete → `Done`
   - Partial → `15/23` (complete/total)
   - `Planning`/`Design` → `Plan`

7. After active plans, show a single line: `Archived: {count} plans in archive/`

8. End with a brief note on:
   - Which plans are actively blocked or waiting
   - What specific blockers exist (hardware, credentials, etc.)

Keep the output concise - this is meant to be a strategic overview for planning decisions.
