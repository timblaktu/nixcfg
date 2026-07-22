#!/usr/bin/env bash
# pipeline-watch.sh - event-driven CI pipeline watcher (GitLab / glab).
#
# Monitors PROGRESS, not completion: returns EARLY on the next meaningful event so the
# calling agent wakes, inspects, reports, and re-arms. Two phases:
#
#   jobs  --project P --pipeline PID --scope REGEX --target JOBNAME
#         Watch the job set; exit on the next in-scope status change, any in-scope
#         failure, or the target job reaching a terminal state.
#
#   job   --project P --job JID [--heartbeat-min N]
#         Tail one long-running job's live trace; exit on terminal, a detected error
#         signature, or after ~N min heartbeat (default 10) - printing the trace tail.
#
# Hardening: every glab call is wrapped in `timeout` so a VPN/network stall can't wedge
# the watcher; transient API/403 errors are tolerated (logged as API-ERR, loop continues).
# Do NOT `pkill -f pipeline-watch` (the pattern matches the killing shell's own args);
# kill by PID from `pgrep -af pipeline-watch.sh`.
set -uo pipefail

FETCH_TIMEOUT=30
POLL_SECS=60

die() { echo "pipeline-watch: $*" >&2; exit 2; }
now() { date -u '+%H:%M:%S'; }
api() { timeout "$FETCH_TIMEOUT" glab api "$1" 2>/dev/null; }
# Strip artifact/layer download-progress spam from a job trace.
denoise() { grep -aviE 'Completed [0-9].*(GiB|MiB).*remaining|[0-9]+\.[0-9]+ (MiB|GiB)/s'; }

ERR_RE='FATAL|ERROR:|panic|failed to|cannot |timed out|rc=124|STATUS=fail|no matches for kind'
TERMINAL_RE='^(success|failed|canceled|skipped)$'

phase="${1:-}"; shift || true
PROJECT=""; PIPELINE=""; JOB=""; SCOPE=""; TARGET=""; HEARTBEAT_MIN=10
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2;;
    --pipeline) PIPELINE="$2"; shift 2;;
    --job) JOB="$2"; shift 2;;
    --scope) SCOPE="$2"; shift 2;;
    --target) TARGET="$2"; shift 2;;
    --heartbeat-min) HEARTBEAT_MIN="$2"; shift 2;;
    *) die "unknown arg: $1";;
  esac
done
[ -n "$PROJECT" ] || die "--project required"

watch_jobs() {
  [ -n "$PIPELINE" ] || die "jobs: --pipeline required"
  [ -n "$SCOPE" ] || die "jobs: --scope required"
  [ -n "$TARGET" ] || die "jobs: --target required"
  local sel="select(.name|test(\"$SCOPE\"))"
  local keyq="[.[]|$sel|\"\(.name)=\(.status)\"]|sort|join(\";\")"
  local j base key run fails
  j=$(api "projects/$PROJECT/pipelines/$PIPELINE/jobs?per_page=100")
  base=$(echo "$j" | jq -r "$keyq" 2>/dev/null); [ -z "$base" ] && base="INIT"
  local i
  for i in $(seq 1 240); do
    sleep "$POLL_SECS"
    j=$(api "projects/$PROJECT/pipelines/$PIPELINE/jobs?per_page=100")
    [ -z "$j" ] && { echo "[$(now)] iter=$i API-ERR (tolerated)"; continue; }
    key=$(echo "$j" | jq -r "$keyq" 2>/dev/null)
    run=$(echo "$j" | jq -r ".[]|select(.name==\"$TARGET\")|.status" 2>/dev/null | head -1)
    fails=$(echo "$j" | jq -r "[.[]|$sel|select(.status==\"failed\")|.name]|join(\", \")" 2>/dev/null)
    local ev=""
    if [ -n "$fails" ]; then ev="IN-SCOPE-FAILURE: $fails"
    elif echo "$run" | grep -qE "$TERMINAL_RE"; then ev="TARGET-TERMINAL: $TARGET=$run"
    elif [ "$key" != "$base" ]; then ev="MILESTONE-CHANGE"
    else continue
    fi
    echo "==== EVENT ($ev) at $(now), iter=$i ===="
    echo "$j" | jq -r ".[]|$sel|\"\(.status)\t\(.name)\"" 2>/dev/null | sort
    echo "$TARGET job_id=$(echo "$j" | jq -r ".[]|select(.name==\"$TARGET\")|.id" 2>/dev/null | head -1)"
    return 0
  done
  echo "WATCH-TIMEOUT (jobs) after ~$((240*POLL_SECS/60))m"
}

watch_job() {
  [ -n "$JOB" ] || die "job: --job required"
  local beats="$HEARTBEAT_MIN" st err
  local outer inner
  for outer in $(seq 1 60); do
    for inner in $(seq 1 "$beats"); do
      sleep "$POLL_SECS"
      st=$(api "projects/$PROJECT/jobs/$JOB" | jq -r '.status' 2>/dev/null)
      if echo "$st" | grep -qE "$TERMINAL_RE"; then
        echo "==== JOB $JOB TERMINAL=$st at $(now) ===="
        api "projects/$PROJECT/jobs/$JOB/trace" | denoise | tail -25
        return 0
      fi
      err=$(api "projects/$PROJECT/jobs/$JOB/trace" | denoise | tail -40 | grep -aiE "$ERR_RE" | tail -3)
      if [ -n "$err" ]; then
        echo "==== POSSIBLE ERROR in job $JOB (status=${st:-?}) at $(now) ===="
        echo "$err"
        echo "--- context ---"; api "projects/$PROJECT/jobs/$JOB/trace" | denoise | tail -15
        return 0
      fi
    done
    echo "==== HEARTBEAT $outer (status=${st:-?}) at $(now) ===="
    api "projects/$PROJECT/jobs/$JOB/trace" | denoise | tail -12
    return 0
  done
}

case "$phase" in
  jobs) watch_jobs;;
  job)  watch_job;;
  *) die "usage: pipeline-watch.sh {jobs|job} --project P ... (see SKILL.md)";;
esac
