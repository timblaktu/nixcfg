---
name: ci-pipeline-monitoring
description: Monitor a CI/CD pipeline by PROGRESS (not poll-for-completion) - event-driven watcher that wakes on stage transitions and failures, gives heartbeat updates during long jobs, and validates artifacts as it goes. Use when watching/babysitting a GitLab or GitHub Actions pipeline, waiting on a build/deploy/test job, or reporting CI progress to the user.
---

# CI Pipeline Progress Monitoring Skill

**Version**: 1.0.0
**Last Updated**: 2026-07-22
**Default backend**: GitLab (`glab`); adaptable to GitHub Actions (`gh`) - see "GitHub" below.

## The core idea

Do NOT fire-and-forget a poller that only reports when the whole pipeline finishes. Monitor
PROGRESS and validate as you go. A background task only surfaces to you (the agent) when it
EXITS, so "monitor progress" means: run a background watcher that **returns early on the next
meaningful event**, then you wake, inspect, report to the user, and **re-arm** for the next event.

This encodes six rules (also captured in the `feedback-pipeline-progress-monitoring` memory):

1. **Event-driven, not completion-driven** - exit on the next transition / failure / target-terminal.
2. **Catch errors when they happen** - on a failure, pull that job's trace immediately and diagnose.
3. **Regular, context-variable feedback** - milestone updates + a heartbeat during long single jobs
   (interval scaled to the job: ~10min for a 40min deploy).
4. **Validate results, not just green/red** - a green job != success; download artifacts and inspect
   the ACTUAL outcome (STATUS files, logs, metrics) against what the change was supposed to do.
5. **Harden** - per-call `timeout` on every fetch; tolerate transient API/403; never `pkill -f <pat>`
   where `<pat>` matches the killing command's own args.
6. **Scope awareness** - track only the jobs whose transitions matter; ignore (but note) out-of-scope.

## Usage

`scripts/pipeline-watch.sh` has two phases. Launch it as a background task; when it exits, read its
output, act, and re-launch for the next phase/event.

### Phase 1 - `jobs` (build/publish/fan-out stage)
Watch the whole job set; exit on the next in-scope transition, any in-scope failure, or the target
job reaching a terminal state.

```
scripts/pipeline-watch.sh jobs \
  --project 27148 \
  --pipeline 3309912 \
  --scope 'baseline|^eval$|format|version|package-parity' \
  --target bench-run-baseline
```

### Phase 2 - `job` (one long-running deploy/test job)
Tail a single job's live log; exit on terminal, on a detected error signature, or after a heartbeat
interval (whichever first) - returning the log tail so progress is visible along the way.

```
scripts/pipeline-watch.sh job \
  --project 27148 \
  --job 15949353 \
  --heartbeat-min 10
```

## The wake loop (how the agent drives it)

1. Launch phase 1 (`jobs`) as a background task.
2. On wake: read output. If an in-scope job FAILED -> `glab api projects/<P>/jobs/<id>/trace` and
   diagnose NOW; report to user. Else report the milestone; if the target job is now `running`,
   switch to phase 2 (`job`). Re-launch the appropriate watcher.
3. Phase 2 wakes on heartbeat (report progress + log tail), error signature (diagnose), or terminal.
4. On target-terminal: **validate** - download the artifact
   (`glab api projects/<P>/jobs/<id>/artifacts > art.zip`), inspect the real STATUS/logs/metrics
   against the goal, and report the actual finding (not "the job passed").

## Error signatures scanned (phase 2)

`FATAL`, `ERROR:`, `panic`, `failed to`, `cannot `, `timed out`, `rc=124`, `STATUS=fail`,
`no matches for kind` (extend per domain). Download-progress noise lines are filtered out.

## GitHub Actions adaptation

Swap `glab api projects/<P>/pipelines/<id>/jobs` for
`gh run view <run-id> --json jobs` and `glab api .../jobs/<id>/trace` for
`gh run view --log --job <id>`; the phase/exit logic is identical.

## Notes

- Requires `glab` authenticated and (for private GitLab) network egress up. If a fetch returns HTTP
  403 or hangs, the watcher tolerates it (logs `API-ERR`, continues) - a stalled VPN won't wedge it.
- Keep concurrent watchers to one per pipeline; re-arm rather than stacking.
