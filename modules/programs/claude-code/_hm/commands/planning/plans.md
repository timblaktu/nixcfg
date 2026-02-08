Generate a high-level summary of all plans in this repository.

## Instructions

1. Find all plan files in `.claude/user-plans/` using: `fd -t f -e md . .claude/user-plans/`

2. For each plan file, extract:
   - Plan number/name (from filename)
   - Status (look for `**Status**:` line)
   - Brief description (from title or first paragraph)

3. **Detect terminal width**: `${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}`

4. Present as a markdown table that fits within the detected terminal width:
   - Use abbreviated headers: `Plan | St | Desc`
   - Truncate descriptions to fit (use `...`)
   - If still too wide: drop Desc column, list descriptions below table

5. Use these status indicators (abbreviated):
   - `Planning`/`Design` → `Plan`
   - `COMPLETE`/`TASK:COMPLETE` → `Done`
   - `PENDING` → `Pend`
   - Partial → `1-2/5` (tasks done/total)

6. After the table, briefly note:
   - Which plans are actively blocked or waiting
   - Any plans with remaining tasks that could be worked on

Keep the output concise - this is meant to be a quick overview, not detailed analysis.
