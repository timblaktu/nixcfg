Generate a high-level summary of all plans in this repository.

## Instructions

1. Find all plan files in `.claude/user-plans/` using: `fd -t f -e md . .claude/user-plans/`

2. For each plan file, extract:
   - Plan number/name (from filename)
   - Status (look for `**Status**:` line)
   - Brief description (from title or first paragraph)

3. Present as a concise markdown table with columns:
   | Plan | Status | Description |

4. Use these status indicators:
   - `Planning` or `Design` → show as-is
   - `COMPLETE` or `TASK:COMPLETE` → show as "Complete"
   - `PENDING` → show as "Pending"
   - Partial completion → note which tasks done (e.g., "Tasks 1-2 done")

5. After the table, briefly note:
   - Which plans are actively blocked or waiting
   - Any plans with remaining tasks that could be worked on

Keep the output concise - this is meant to be a quick overview, not detailed analysis.
