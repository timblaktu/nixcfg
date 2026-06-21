# Claude Code SessionStart plan-rehydration hook (nixcfg plan 044 T3).
#
# Surfaces a lean, FACTUAL resume payload as hookSpecificOutput.additionalContext
# so a fresh/resumed/compacted session re-acquires "what plan, which task, next
# step" with zero clipboard paste. This is the PUSH half of a dual-channel design
# (CC #10373: SessionStart stdout can silently fail to inject) — the readable
# .claude/active-plan + .claude/HANDOFF.md files and the next-task skill are the
# PULL backstop, so this hook is never load-bearing alone.
#
# Precedence: B (.claude/active-plan -> next task) -> A (.claude/HANDOFF.md)
#             -> C (latest OTHER per-cwd transcript's last assistant text).
# Always exits 0. Tolerant of missing files. Emits ONLY the JSON payload — no
# stray plain stdout (T1: plain stdout ALSO enters model context). Payload is
# LEAN: plan pointer + next task only; native auto-memory already re-injects
# memory facts every session, so we never duplicate them here.
#
# PATH for jq/fd/coreutils/gawk is injected by the Nix writeShellScript wrapper.

set -u

stdin_json="$(cat)"

# Plan 045 T5/D7: no-op under the headless unattended burndown driver.
# `run-tasks-<account>` drives each task via its own `claude -p "<prompt>"`, and a
# fresh `-p` session fires SessionStart with source=startup (empirically verified
# 2026-06-21) — which this hook's matcher (startup|resume|compact) also matches.
# Without this guard the hook would re-inject the active-plan task block on top of
# the driver's own task prompt (double-drive). The driver exports CLAUDE_BURNDOWN=1,
# which propagates to this hook subprocess; honor it by emitting nothing.
if [ "${CLAUDE_BURNDOWN:-}" = "1" ]; then
  exit 0
fi

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
claude_dir="$proj/.claude"

# Emit the additionalContext payload as SessionStart hook JSON, then exit 0.
emit() {
  jq -n --arg ctx "$1" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
  exit 0
}

# --- Source B: explicit plan pointer (highest precedence) ---
active_plan_file="$claude_dir/active-plan"
if [ -f "$active_plan_file" ]; then
  plan_rel="$(head -n1 "$active_plan_file" 2>/dev/null | tr -d '[:space:]')"
  if [ -n "$plan_rel" ]; then
    case "$plan_rel" in
      /*) plan_path="$plan_rel" ;;
      *)  plan_path="$proj/$plan_rel" ;;
    esac
    if [ -f "$plan_path" ]; then
      # First "### ...TASK:(IN_PROGRESS|PENDING)" heading through to the next "### ".
      task_block="$(awk '
        !found {
          if ($0 ~ /^### / && $0 ~ /TASK:(IN_PROGRESS|PENDING)/) { found=1; print }
          next
        }
        /^### / { exit }
        { print }
      ' "$plan_path" 2>/dev/null)"
      if [ -n "$task_block" ]; then
        emit "The active plan for this worktree is ${plan_rel} (resolved path: ${plan_path}). The current task is the first IN_PROGRESS or PENDING task in that plan, reproduced below as rehydrated session context. The plan file is the source of truth for task status; the next-task skill acts on it.

${task_block}"
      fi
    fi
  fi
fi

# --- Source A: distilled handoff ---
handoff="$claude_dir/HANDOFF.md"
if [ -f "$handoff" ] && [ -s "$handoff" ]; then
  emit "A distilled handoff exists for this worktree at .claude/HANDOFF.md. Its contents follow as rehydrated session context:

$(cat "$handoff" 2>/dev/null)"
fi

# --- Source C: latest OTHER per-cwd transcript's last assistant message (fallback) ---
cur_transcript="$(printf '%s' "$stdin_json" | jq -r '.transcript_path // empty' 2>/dev/null)"
if [ -n "$cur_transcript" ]; then
  tdir="$(dirname "$cur_transcript")"
  if [ -d "$tdir" ]; then
    latest="$(fd -I -e jsonl . "$tdir" -d 1 --exec stat --printf '%Y %n\n' 2>/dev/null \
      | grep -v -F "$cur_transcript" \
      | sort -rn | head -n1 | cut -d' ' -f2-)"
    if [ -n "$latest" ] && [ -f "$latest" ]; then
      last_text="$(jq -R 'fromjson? // empty' "$latest" 2>/dev/null \
        | jq -rs '[ .[] | select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text ] | last // empty' 2>/dev/null)"
      if [ -n "$last_text" ]; then
        emit "No .claude/active-plan pointer or .claude/HANDOFF.md was found for this worktree. The most recent prior session in this directory ended with the following assistant message, surfaced as a fallback (it may be stale):

${last_text}"
      fi
    fi
  fi
fi

# Nothing to rehydrate — emit nothing, exit cleanly.
exit 0
