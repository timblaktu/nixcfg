---
description: Session close-out - verify (don't assert) that work claimed done is actually done and continuity is intact before ending
---

You are closing out this session. Do NOT simply assert that things are done - VERIFY each point against live evidence, then report. Be skeptical of your own earlier claims: a confident "done" can hide a SKIPped check, a stale assumption, or an external thread left open.

Work through these and report each with concrete evidence. Investigate now (run the commands, re-fetch the live state) rather than answering from memory.

1. **DoD honesty.** For every task or goal you treated as COMPLETE this session, name the concrete proof - a command that exited zero, a file you actually inspected, a test that PASSED (not "should pass"). Flag anything resting on "should work" and downgrade it to unfinished.

2. **Claims vs. live state.** List each factual claim you made about anything external (CI pipeline, MR/PR, review thread, published version, remote file, deployed resource). For each, confirm you verified it against the live source THIS session, not from memory or an earlier turn. Re-check anything stale right now and correct the record if it moved.

3. **Loose ends outside the repo.** For every MR/PR, review thread, pipeline, or external job you touched or created, report its CURRENT live state (open/merged, resolved/unresolved, green/red/SKIPped) and exactly what it is waiting on and from whom. Call out anything a reader would assume is finished but is not.

4. **Continuity artifacts.** If this session advanced tracked work: confirm the plan/tracker status cursor, any handoff/active-pointer files, and memory reflect REALITY, and that a fresh session with no chat history could resume from them alone. Update whichever are stale now. If there is no tracked work, say so explicitly.

5. **The one next step.** State the single most-actionable next step, who or what it is blocked on, and whether resuming (e.g. `/next-task`) would advance the work or immediately need a human decision.

Finish with a one-line verdict: **clear to end here, or something is unfinished** - and if unfinished, name exactly what and who owns it.
