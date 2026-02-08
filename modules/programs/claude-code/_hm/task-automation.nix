{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.claude-code;
  taskCfg = cfg.taskAutomation;

  # Slash command for interactive task execution
  nextTaskMd = ''
    Read the plan file specified below (or auto-detect from CLAUDE.md if not specified),
    find the first task with status "TASK:PENDING" in the Progress Tracking table,
    execute it following the task definition in that file,
    document findings in the corresponding section,
    change status from "TASK:PENDING" to "TASK:COMPLETE" and add today's date,
    and report what you completed and what's next.
    Commit your changes when done.

    Plan file: $ARGUMENTS

    If no plan file argument is provided:
    1. Check the project's CLAUDE.md for a "Primary File" or "Plan File" reference
    2. Look for files matching `*-research.md`, `*-plan.md`, or `*-tasks.md` in docs/
    3. Ask the user which file to use

    IMPORTANT: If you determine the task cannot be executed on the current host
    (e.g., requires Nix but running on Termux, or requires specific tools not available),
    output on its own line: ENVIRONMENT_NOT_CAPABLE
    Then explain briefly. Do NOT mark the task complete - leave it PENDING for another host.

    IMPORTANT: If the task is marked as "Interactive" in the plan file, or requires user
    decisions/choices before proceeding, output on its own line: USER_INPUT_REQUIRED
    Then present the questions/options clearly. Do NOT mark the task complete - leave it
    PENDING so the user can complete it in an interactive session using /next-task.

    CRITICAL: Do NOT invent "alternative approaches" or workarounds to tasks.
    If a task has prerequisites that aren't met (e.g., "test the Nix-generated package"
    but the package hasn't been built), that task is ENVIRONMENT_NOT_CAPABLE.
    Complete the task as defined or mark it not capable - no workarounds.

    After completing the task, provide a summary:

    ## Task Completed
    - **Task ID**: [task number/name]
    - **Status**: Complete
    - **Summary**: [1-2 sentence summary]

    ## Next Pending Task
    - **Task ID**: [next task number/name]
    - **Description**: [brief description]

    If no pending tasks remain, output on its own line: ALL_TASKS_DONE

    IMPORTANT: Do not include ready-to-paste prompts or continuation templates in your response
  '';

  # Generate zsh completion for run-tasks-<account>
  mkZshCompletion = { accountName }:
    pkgs.writeText "_run-tasks-${accountName}" ''
      #compdef run-tasks-${accountName}

      _run_tasks_${lib.replaceStrings ["-"] ["_"] accountName}() {
        local curcontext="$curcontext" state line
        typeset -A opt_args

        _arguments -C \
          '-n[Run N tasks]:number of tasks:' \
          '-a[Run all pending tasks]' \
          '--all[Run all pending tasks]' \
          '-c[Run continuously]' \
          '--continuous[Run continuously]' \
          '-d[Seconds between tasks]:delay seconds:' \
          '--delay[Seconds between tasks]:delay seconds:' \
          '--model[Override model]:model:(opus sonnet haiku qwen-a3b)' \
          '--task[Run specific task by ID]:task ID:->tasks' \
          '--list[Show all tasks with status]' \
          '--dry-run[Show what would execute without running]' \
          '-h[Show help]' \
          '--help[Show help]' \
          '1:plan file:_files -g "*.md"' \
          && return 0

        case $state in
          tasks)
            # Extract task IDs from the plan file if available
            local plan_file
            plan_file="''${words[(r)*.md]}"
            if [[ -n "$plan_file" && -f "$plan_file" ]]; then
              local -a task_ids
              task_ids=($(${pkgs.ripgrep}/bin/rg '\|\s*TASK:(PENDING|COMPLETE)\s*\|' "$plan_file" 2>/dev/null | \
                ${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*|[[:space:]]*\([A-Za-z0-9_-]\+\)[[:space:]]*|.*/\1/p' | \
                ${pkgs.coreutils}/bin/tr '\n' ' '))
              if [[ ''${#task_ids[@]} -gt 0 ]]; then
                _values 'task ID' "''${task_ids[@]}"
              fi
            fi
            ;;
        esac
      }

      _run_tasks_${lib.replaceStrings ["-"] ["_"] accountName} "$@"
    '';

  # Generate bash completion for run-tasks-<account>
  mkBashCompletion = { accountName }:
    pkgs.writeText "run-tasks-${accountName}.bash" ''
      # Bash completion for run-tasks-${accountName}
      _run_tasks_${lib.replaceStrings ["-"] ["_"] accountName}() {
        local cur prev words cword
        COMPREPLY=()
        cur="''${COMP_WORDS[COMP_CWORD]}"
        prev="''${COMP_WORDS[COMP_CWORD-1]}"

        # Options that take values
        case "$prev" in
          -n|-d|--delay)
            # Numeric value expected
            return 0
            ;;
          --model)
            COMPREPLY=( $(compgen -W "opus sonnet haiku qwen-a3b" -- "$cur") )
            return 0
            ;;
          --task)
            # Try to extract task IDs from plan file
            local plan_file=""
            for word in "''${COMP_WORDS[@]}"; do
              if [[ "$word" == *.md ]]; then
                plan_file="$word"
                break
              fi
            done
            if [[ -n "$plan_file" && -f "$plan_file" ]]; then
              local task_ids
              task_ids=$(${pkgs.ripgrep}/bin/rg '\|\s*TASK:(PENDING|COMPLETE)\s*\|' "$plan_file" 2>/dev/null | \
                ${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*|[[:space:]]*\([A-Za-z0-9_-]\+\)[[:space:]]*|.*/\1/p' | \
                ${pkgs.coreutils}/bin/tr '\n' ' ')
              COMPREPLY=( $(compgen -W "$task_ids" -- "$cur") )
            fi
            return 0
            ;;
        esac

        # Complete options
        if [[ "$cur" == -* ]]; then
          COMPREPLY=( $(compgen -W "-n -a --all -c --continuous -d --delay --model --task --list --dry-run -h --help" -- "$cur") )
          return 0
        fi

        # Complete markdown files
        COMPREPLY=( $(compgen -f -X '!*.md' -- "$cur") )
      }
      complete -F _run_tasks_${lib.replaceStrings ["-"] ["_"] accountName} run-tasks-${accountName}
    '';

  # Generate a run-tasks script for a specific account
  # This creates run-tasks-<account> scripts (e.g., run-tasks-max, run-tasks-pro, run-tasks-work)
  mkRunTasksScript = { accountName, displayName, claudeWrapper }:
    pkgs.writeShellScriptBin "run-tasks-${accountName}" ''
      #!/usr/bin/env bash
      #
      # run-tasks-${accountName} - Claude Code unattended task runner for ${displayName}
      # Generated by: home/modules/claude-code/task-automation.nix
      #
      # Usage: run-tasks-${accountName} <plan-file> [options]
      #
      # Runs ${claudeWrapper} -p to execute tasks defined in a markdown plan file.
      # The plan file must have a Progress Tracking table with "TASK:PENDING" status markers.

      set -euo pipefail

      # Account configuration (baked in at build time)
      ACCOUNT="${accountName}"
      ACCOUNT_DISPLAY="${displayName}"
      CLAUDE_CMD="${claudeWrapper}"

      # Colors
      RED='\033[0;31m'
      GREEN='\033[0;32m'
      YELLOW='\033[1;33m'
      BLUE='\033[0;34m'
      CYAN='\033[0;36m'
      NC='\033[0m'

      # Configurable defaults (from Nix options)
      LOG_DIR="${taskCfg.logDirectory}"
      STATE_FILE="${taskCfg.stateFile}"
      DELAY_BETWEEN_TASKS=${toString taskCfg.safetyLimits.delayBetweenTasks}
      RATE_LIMIT_WAIT=${toString taskCfg.safetyLimits.rateLimitWaitSeconds}
      MAX_RETRIES=${toString taskCfg.safetyLimits.maxRetries}
      MAX_ITERATIONS=${toString taskCfg.safetyLimits.maxIterations}
      MAX_RUNTIME_HOURS=${toString taskCfg.safetyLimits.maxRuntimeHours}
      MAX_CONSECUTIVE_RATE_LIMITS=${toString taskCfg.safetyLimits.maxConsecutiveRateLimits}
      START_TIME=$(date +%s)

      # Parse arguments
      PLAN_FILE=""
      MODE="single"
      COUNT=1
      DRY_RUN=false
      MODEL_OVERRIDE=""
      TASK_ID=""
      LIST_TASKS=false

      usage() {
          cat << 'EOF'
      run-tasks-${accountName} - Claude Code unattended task runner

      Account: ${displayName} (${claudeWrapper})

      Usage: run-tasks-${accountName} <plan-file> [options]

      Arguments:
        <plan-file>       Path to markdown file with Progress Tracking table

      Options:
        -n N              Run N tasks (default: 1)
        -a, --all         Run all pending tasks
        -c, --continuous  Run continuously (survives rate limits)
        -d, --delay N     Seconds between tasks (default: ${toString taskCfg.safetyLimits.delayBetweenTasks})
        --model MODEL     Override model (alias or full name, e.g., opus, qwen-a3b)
        --dry-run         Show what would execute without running
        -h, --help        Show this help

      Task Selection:
        --task ID         Run specific task by ID (e.g., --task F1)
                          Can combine with -n: --task F1 -n 3 (run F1, then next 2)
        --list            Show all tasks with status, select with fzf if interactive

      Plan File Format:
        The plan file must contain a Progress Tracking table with unique status tokens:

        | Task | Name | Status | Date | Model |
        |------|------|--------|------|-------|
        | 1    | ...  | TASK:COMPLETE | 2026-01-10 |     |
        | 2    | ...  | TASK:PENDING  |      | qwen |

        Status tokens: TASK:PENDING, TASK:COMPLETE (unique to avoid false matches)
        Model column: Optional, specifies model for this task (alias or full name)
        Model priority: --model CLI flag > Model column > account default

      Safety Limits (configurable via Nix):
        Max iterations:  ${toString taskCfg.safetyLimits.maxIterations}
        Max runtime:     ${toString taskCfg.safetyLimits.maxRuntimeHours} hours
        Rate limit wait: ${toString taskCfg.safetyLimits.rateLimitWaitSeconds} seconds

      Examples:
        run-tasks-${accountName} docs/plan.md               # Run next pending task
        run-tasks-${accountName} docs/plan.md -n 5          # Run 5 tasks sequentially
        run-tasks-${accountName} docs/plan.md --task F1     # Run task F1 specifically
        run-tasks-${accountName} docs/plan.md --task F1 -n 3 # Run F1, then next 2 pending
        run-tasks-${accountName} docs/plan.md --list        # Show task status, select with fzf
        run-tasks-${accountName} docs/plan.md --dry-run     # Preview what would execute
      EOF
          exit 0
      }

      # Parse positional and optional args
      while [[ $# -gt 0 ]]; do
          case $1 in
              -n) COUNT="$2"; MODE="count"; shift 2 ;;
              -a|--all) MODE="all"; shift ;;
              -c|--continuous) MODE="continuous"; shift ;;
              -d|--delay) DELAY_BETWEEN_TASKS="$2"; shift 2 ;;
              --model) MODEL_OVERRIDE="$2"; shift 2 ;;
              --task) TASK_ID="$2"; shift 2 ;;
              --list) LIST_TASKS=true; shift ;;
              --dry-run) DRY_RUN=true; shift ;;
              -h|--help) usage ;;
              -*)
                  echo -e "''${RED}Unknown option: $1''${NC}"
                  echo "Use -h for help"
                  exit 1
                  ;;
              *)
                  if [[ -z "$PLAN_FILE" ]]; then
                      PLAN_FILE="$1"
                  else
                      echo -e "''${RED}Unexpected argument: $1''${NC}"
                      exit 1
                  fi
                  shift
                  ;;
          esac
      done

      # Verify the claude wrapper exists
      if ! command -v "$CLAUDE_CMD" &>/dev/null; then
          echo -e "''${RED}Error: Claude wrapper '$CLAUDE_CMD' not found in PATH''${NC}"
          echo "Make sure home-manager has been activated with the account configured."
          exit 1
      fi

      # Validate plan file
      if [[ -z "$PLAN_FILE" ]]; then
          echo -e "''${RED}Error: Plan file required''${NC}"
          echo "Usage: run-tasks <plan-file> [options]"
          echo "Use -h for help"
          exit 1
      fi

      if [[ ! -f "$PLAN_FILE" ]]; then
          echo -e "''${RED}Error: Plan file not found: $PLAN_FILE''${NC}"
          exit 1
      fi

      # Resolve to absolute path
      PLAN_FILE_ABS=$(realpath "$PLAN_FILE")

      # Create log directory
      mkdir -p "$LOG_DIR"

      # Build the prompt
      # NOTE: Sentinel tokens (ALL_TASKS_DONE, ENVIRONMENT_NOT_CAPABLE) must appear on their own line
      # for reliable detection - the script uses ^TOKEN anchored patterns to avoid false positives
      PROMPT="Read ''${PLAN_FILE_ABS}, find the first task with status \"TASK:PENDING\" in the Progress Tracking table. Execute it following the task definition in that file. Document findings in the corresponding section. Change status from \"TASK:PENDING\" to \"TASK:COMPLETE\" and add today's date. Report what you completed and what's next. Commit your changes when done. If no TASK:PENDING found, output on its own line: ALL_TASKS_DONE. IMPORTANT: If you determine the task cannot be executed on the current host (e.g., requires Nix but running on Termux, or requires specific tools not available), output on its own line: ENVIRONMENT_NOT_CAPABLE followed by a brief explanation. Do NOT mark the task complete - leave it PENDING for another host to pick up. IMPORTANT: If the task is marked as 'Interactive' in the plan file, or requires user decisions/choices before proceeding, output on its own line: USER_INPUT_REQUIRED followed by the questions/options. Do NOT mark it complete - leave PENDING for interactive session via /next-task. CRITICAL: Do NOT invent 'alternative approaches' or workarounds to tasks. If a task has prerequisites that aren't met (e.g., 'test the Nix-generated package' but the package hasn't been built), that task is ENVIRONMENT_NOT_CAPABLE. Complete the task as defined or mark it not capable - no workarounds. IMPORTANT: Do not include ready-to-paste prompts or continuation templates in your response."

      # Functions
      pending_count() {
          ${pkgs.ripgrep}/bin/rg -c '\|\s*TASK:PENDING\s*\|' "$PLAN_FILE" 2>/dev/null || echo "0"
      }

      # Extract task ID/name from the first TASK:PENDING row in the plan file
      # Looks for patterns like "| R1 |" or "| I7 |" in the row with TASK:PENDING
      # Returns a sanitized name safe for use in filenames (no /, :, or spaces)
      get_next_task_name() {
          local line
          line=$(${pkgs.ripgrep}/bin/rg -m1 '\|\s*TASK:PENDING\s*\|' "$PLAN_FILE" 2>/dev/null) || { echo "unknown"; return; }
          # Extract task ID from first or second column (handles both "| Task | Name |" and "| R1 | Name |" formats)
          local task_id
          task_id=$(echo "$line" | ${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*|[[:space:]]*\([A-Za-z0-9_-]\+\)[[:space:]]*|.*/\1/p')
          if [[ -n "$task_id" && "$task_id" != "Task" ]]; then
              # Sanitize for filename: replace / and : with _, remove other unsafe chars
              echo "$task_id" | ${pkgs.coreutils}/bin/tr '/:' '__' | ${pkgs.coreutils}/bin/tr -cd 'A-Za-z0-9._-'
          else
              # Try second column
              task_id=$(echo "$line" | ${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*|[^|]*|[[:space:]]*\([^|]*\)[[:space:]]*|.*/\1/p' | ${pkgs.coreutils}/bin/tr -d ' ')
              if [[ -n "$task_id" ]]; then
                  # Sanitize for filename: replace / and : with _, remove other unsafe chars
                  echo "$task_id" | ${pkgs.coreutils}/bin/tr '/:' '__' | ${pkgs.coreutils}/bin/tr -cd 'A-Za-z0-9._-'
              else
                  echo "unknown"
              fi
          fi
      }

      # Extract model specification from the first TASK:PENDING row in the plan file
      # Looks for a Model column (5th column typically: Task | Name | Status | Date | Model)
      # Returns the model name if specified, empty string if not
      get_next_task_model() {
          local line
          line=$(${pkgs.ripgrep}/bin/rg -m1 '\|\s*TASK:PENDING\s*\|' "$PLAN_FILE" 2>/dev/null) || { echo ""; return; }
          # Count pipe characters to determine column count
          local col_count
          col_count=$(echo "$line" | ${pkgs.coreutils}/bin/tr -cd '|' | ${pkgs.coreutils}/bin/wc -c)

          # If we have 6+ pipes (5+ columns), try to extract the 5th column (Model)
          # Format: | Task | Name | Status | Date | Model |
          if [[ $col_count -ge 6 ]]; then
              local model
              model=$(echo "$line" | ${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*|[^|]*|[^|]*|[^|]*|[^|]*|[[:space:]]*\([^|]*\)[[:space:]]*|.*/\1/p' | ${pkgs.coreutils}/bin/tr -d ' ')
              echo "$model"
          else
              echo ""
          fi
      }

      save_state() {
          local tasks_run=$1
          local status=$2
          local pending_now=''${3:-$(pending_count)}
          local runtime=$(($(date +%s) - START_TIME))
          cat > "$STATE_FILE" << EOF
      LAST_RUN=$(date -Iseconds)
      TASKS_RUN=$tasks_run
      STATUS=$status
      PENDING_NOW=$pending_now
      RUNTIME_SECONDS=$runtime
      PLAN_FILE=$PLAN_FILE_ABS
      EOF
      }

      format_runtime() {
          local seconds=$1
          local hours=$((seconds / 3600))
          local minutes=$(((seconds % 3600) / 60))
          local secs=$((seconds % 60))
          if [[ $hours -gt 0 ]]; then
              echo "''${hours}h ''${minutes}m"
          elif [[ $minutes -gt 0 ]]; then
              echo "''${minutes}m ''${secs}s"
          else
              echo "''${secs}s"
          fi
      }

      print_exit_summary() {
          local reason=$1
          local tasks_run=$2
          local pending=$3
          local runtime=$(($(date +%s) - START_TIME))
          local runtime_fmt=$(format_runtime $runtime)

          echo ""
          echo -e "''${CYAN}===============================================''${NC}"
          echo -e "''${CYAN}  Session Summary''${NC}"
          echo -e "''${CYAN}===============================================''${NC}"
          echo -e "  Reason:    ''${reason}"
          echo -e "  Tasks:     ''${tasks_run} completed, ''${pending} pending"
          echo -e "  Runtime:   ''${runtime_fmt}"
          echo -e "  Logs:      ''${LOG_DIR}/"
          echo -e "''${CYAN}===============================================''${NC}"
      }

      # Parse JSON output from Claude CLI
      # Returns: sets global variables json_type, json_subtype, json_is_error, json_result
      parse_claude_json() {
          local json_output="$1"

          # Extract key fields using jq
          json_type=$(echo "$json_output" | ${pkgs.jq}/bin/jq -r '.type // "unknown"' 2>/dev/null) || json_type="parse_error"
          json_subtype=$(echo "$json_output" | ${pkgs.jq}/bin/jq -r '.subtype // "unknown"' 2>/dev/null) || json_subtype="unknown"
          json_is_error=$(echo "$json_output" | ${pkgs.jq}/bin/jq -r '.is_error // false' 2>/dev/null) || json_is_error="true"
          json_result=$(echo "$json_output" | ${pkgs.jq}/bin/jq -r '.result // ""' 2>/dev/null) || json_result=""
      }

      # Detect rate limiting from JSON output or error text
      # Uses structured JSON fields when available, falls back to text patterns with word boundaries
      is_rate_limited() {
          local json_output="$1"
          local raw_stderr="$2"

          # Check JSON subtype first (most reliable)
          local subtype
          subtype=$(echo "$json_output" | ${pkgs.jq}/bin/jq -r '.subtype // ""' 2>/dev/null) || subtype=""
          if [[ "$subtype" == "rate_limited" || "$subtype" == "rate_limit" ]]; then
              return 0
          fi

          # Check for rate limit in result message
          local result
          result=$(echo "$json_output" | ${pkgs.jq}/bin/jq -r '.result // ""' 2>/dev/null) || result=""
          if echo "$result" | ${pkgs.ripgrep}/bin/rg -qi '\brate.?limit|too many requests|\b429\b|hit your.*limit'; then
              return 0
          fi

          # Check raw stderr for API errors (word boundaries to avoid false positives like line numbers)
          if echo "$raw_stderr" | ${pkgs.ripgrep}/bin/rg -qi '\b429\b|rate.?limit.*error|error.*rate.?limit|too many requests'; then
              return 0
          fi

          return 1
      }

      # List all tasks with their status
      # Output: Task ID | Name | Status | Date | Model (tab-separated for fzf)
      list_all_tasks() {
          # Find all table rows with TASK: status markers
          ${pkgs.ripgrep}/bin/rg '\|\s*TASK:(PENDING|COMPLETE)\s*\|' "$PLAN_FILE" 2>/dev/null | while read -r line; do
              # Extract columns: | Task | Name | Status | Date | Model |
              local task_id name status date model
              task_id=$(echo "$line" | ${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*|[[:space:]]*\([^|]*\)[[:space:]]*|.*/\1/p' | ${pkgs.coreutils}/bin/tr -d ' ')
              name=$(echo "$line" | ${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*|[^|]*|[[:space:]]*\([^|]*\)[[:space:]]*|.*/\1/p' | ${pkgs.coreutils}/bin/tr -d ' ')
              status=$(echo "$line" | ${pkgs.gnused}/bin/sed -n 's/.*|\s*\(TASK:[A-Z]*\)\s*|.*/\1/p')
              date=$(echo "$line" | ${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*|[^|]*|[^|]*|[^|]*|[[:space:]]*\([^|]*\)[[:space:]]*|.*/\1/p' | ${pkgs.coreutils}/bin/tr -d ' ')

              # Try to extract model from 5th column
              local col_count
              col_count=$(echo "$line" | ${pkgs.coreutils}/bin/tr -cd '|' | ${pkgs.coreutils}/bin/wc -c)
              if [[ $col_count -ge 6 ]]; then
                  model=$(echo "$line" | ${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*|[^|]*|[^|]*|[^|]*|[^|]*|[[:space:]]*\([^|]*\)[[:space:]]*|.*/\1/p' | ${pkgs.coreutils}/bin/tr -d ' ')
              else
                  model=""
              fi

              # Output tab-separated for easy parsing
              printf "%s\t%s\t%s\t%s\t%s\n" "$task_id" "$name" "$status" "''${date:--}" "''${model:--}"
          done
      }

      # Display formatted task list with status highlighting
      show_task_list() {
          local pending_count=0
          local complete_count=0
          local next_pending=""

          echo -e "''${CYAN}Tasks in: $PLAN_FILE_ABS''${NC}"
          echo ""
          printf "''${BLUE}%-8s %-30s %-15s %-12s %-10s''${NC}\n" "ID" "Name" "Status" "Date" "Model"
          echo "-------- ------------------------------ --------------- ------------ ----------"

          list_all_tasks | while IFS=$'\t' read -r task_id name status date model; do
              local status_color=""
              local marker=""
              case "$status" in
                  TASK:PENDING)
                      status_color="''${YELLOW}"
                      pending_count=$((pending_count + 1))
                      if [[ -z "$next_pending" ]]; then
                          next_pending="$task_id"
                          marker="→"
                      fi
                      ;;
                  TASK:COMPLETE)
                      status_color="''${GREEN}"
                      complete_count=$((complete_count + 1))
                      ;;
                  *)
                      status_color="''${NC}"
                      ;;
              esac
              printf "%-1s ''${CYAN}%-7s''${NC} %-30s ''${status_color}%-15s''${NC} %-12s %-10s\n" \
                  "$marker" "$task_id" "''${name:0:30}" "$status" "$date" "$model"
          done

          echo ""
          # Re-count since subshell vars don't persist
          local p=$(${pkgs.ripgrep}/bin/rg -c '\|\s*TASK:PENDING\s*\|' "$PLAN_FILE" 2>/dev/null || echo "0")
          local c=$(${pkgs.ripgrep}/bin/rg -c '\|\s*TASK:COMPLETE\s*\|' "$PLAN_FILE" 2>/dev/null || echo "0")
          echo -e "''${GREEN}Complete: $c''${NC}  ''${YELLOW}Pending: $p''${NC}"
      }

      # Interactive task selection with fzf
      select_task_with_fzf() {
          if ! command -v ${pkgs.fzf}/bin/fzf &>/dev/null; then
              echo -e "''${RED}fzf not available for interactive selection''${NC}" >&2
              return 1
          fi

          local selected
          selected=$(list_all_tasks | ${pkgs.fzf}/bin/fzf \
              --header="Select task (TAB to multi-select, ENTER to confirm)" \
              --preview="echo 'Task: {1}  Status: {3}'" \
              --preview-window=up:1 \
              --delimiter=$'\t' \
              --with-nth=1,2,3 \
              --ansi \
              --height=50% \
              --reverse \
              --prompt="Task> " \
              --bind="ctrl-a:select-all" \
              | ${pkgs.coreutils}/bin/cut -f1)

          if [[ -n "$selected" ]]; then
              echo "$selected"
          else
              return 1
          fi
      }

      # Get task line by ID, returns empty if not found
      get_task_line_by_id() {
          local target_id="$1"
          ${pkgs.ripgrep}/bin/rg "\|\s*$target_id\s*\|" "$PLAN_FILE" 2>/dev/null | ${pkgs.ripgrep}/bin/rg '\|\s*TASK:(PENDING|COMPLETE)\s*\|' | head -1
      }

      # Check if a task ID exists and is PENDING
      is_task_pending() {
          local target_id="$1"
          local line
          line=$(get_task_line_by_id "$target_id")
          [[ -n "$line" ]] && echo "$line" | ${pkgs.ripgrep}/bin/rg -q '\|\s*TASK:PENDING\s*\|'
      }

      # Get model for specific task by ID
      get_task_model_by_id() {
          local target_id="$1"
          local line
          line=$(get_task_line_by_id "$target_id")
          if [[ -z "$line" ]]; then
              echo ""
              return
          fi

          local col_count
          col_count=$(echo "$line" | ${pkgs.coreutils}/bin/tr -cd '|' | ${pkgs.coreutils}/bin/wc -c)
          if [[ $col_count -ge 6 ]]; then
              echo "$line" | ${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*|[^|]*|[^|]*|[^|]*|[^|]*|[[:space:]]*\([^|]*\)[[:space:]]*|.*/\1/p' | ${pkgs.coreutils}/bin/tr -d ' '
          else
              echo ""
          fi
      }

      run_task() {
          local iteration=$1
          local rate_limit_count=''${2:-0}
          local target_task_id="''${3:-}"  # Optional: specific task ID to run
          local pending_before=$(pending_count)

          # Determine task name and model based on whether we have a specific task ID
          local task_name task_model
          if [[ -n "$target_task_id" ]]; then
              task_name="$target_task_id"
              task_model=$(get_task_model_by_id "$target_task_id")
          else
              task_name=$(get_next_task_name)
              task_model=$(get_next_task_model)
          fi

          local timestamp=$(date +"%Y%m%d_%H%M%S")
          # Log file naming: LOG_DIR/YYYYMMDD_HHMMSS_TASKNAME.{log,json}
          # User can tail LOG_DIR/*.log for live output
          local log_base="''${LOG_DIR}/''${timestamp}_''${task_name}"

          # Determine which model to use: CLI override > Model column > account default
          local model_to_use=""
          if [[ -n "$MODEL_OVERRIDE" ]]; then
              model_to_use="$MODEL_OVERRIDE"
          elif [[ -n "$task_model" ]]; then
              model_to_use="$task_model"
          fi

          # Build model flag for claude command
          local model_flag=""
          if [[ -n "$model_to_use" ]]; then
              model_flag="--model $model_to_use"
          fi

          # Single-line compact header: [N/total] TASK @ TIME (logs: basename)
          if [[ -n "$model_to_use" ]]; then
              echo -e "''${GREEN}[''${iteration}] ''${CYAN}''${task_name}''${NC} @ $(date '+%H:%M:%S') ''${YELLOW}(''${pending_before} pending)''${NC} ''${BLUE}→ ''${log_base##*/}.*''${NC} ''${YELLOW}[model: ''${model_to_use}]''${NC}"
          else
              echo -e "''${GREEN}[''${iteration}] ''${CYAN}''${task_name}''${NC} @ $(date '+%H:%M:%S') ''${YELLOW}(''${pending_before} pending)''${NC} ''${BLUE}→ ''${log_base##*/}.*''${NC}"
          fi

          if [[ "$DRY_RUN" == true ]]; then
              echo -e "  ''${YELLOW}[DRY RUN] Would execute: $CLAUDE_CMD -p $model_flag ...''${NC}"
              return 0
          fi

          # Build prompt - either for specific task or first pending
          local task_prompt
          if [[ -n "$target_task_id" ]]; then
              task_prompt="Read ''${PLAN_FILE_ABS}, find the task with ID \"$target_task_id\" in the Progress Tracking table. Execute it following the task definition in that file. Document findings in the corresponding section. Change status from \"TASK:PENDING\" to \"TASK:COMPLETE\" and add today's date. Report what you completed and what's next. Commit your changes when done. If the task is already TASK:COMPLETE, output on its own line: TASK_ALREADY_COMPLETE. If no such task ID found, output on its own line: TASK_NOT_FOUND. IMPORTANT: If you determine the task cannot be executed on the current host (e.g., requires Nix but running on Termux, or requires specific tools not available), output on its own line: ENVIRONMENT_NOT_CAPABLE followed by a brief explanation. Do NOT mark the task complete - leave it PENDING for another host to pick up. IMPORTANT: If the task is marked as 'Interactive' in the plan file, or requires user decisions/choices before proceeding, output on its own line: USER_INPUT_REQUIRED followed by the questions/options. Do NOT mark it complete - leave PENDING for interactive session via /next-task. CRITICAL: Do NOT invent 'alternative approaches' or workarounds to tasks. If a task has prerequisites that aren't met, that task is ENVIRONMENT_NOT_CAPABLE. Complete the task as defined or mark it not capable - no workarounds. IMPORTANT: Do not include ready-to-paste prompts or continuation templates in your response."
          else
              task_prompt="$PROMPT"
          fi

          local json_output
          local raw_stderr
          local exit_code=0

          # Capture JSON output to stdout, stderr separately for error analysis
          # Using --output-format json for structured response parsing
          {
              json_output=$($CLAUDE_CMD -p $model_flag --output-format json --permission-mode bypassPermissions "$task_prompt" 2>"''${log_base}.stderr")
              exit_code=$?
          } || exit_code=$?

          raw_stderr=$(cat "''${log_base}.stderr" 2>/dev/null || echo "")

          # Save JSON output
          echo "$json_output" > "''${log_base}.json"

          # Create human-readable log with result text
          {
              echo "=== ''${task_name} - $(date '+%Y-%m-%d %H:%M:%S') ==="
              echo "Exit code: $exit_code"
              echo ""
              if [[ -n "$json_output" ]]; then
                  echo "=== Claude Response ==="
                  echo "$json_output" | ${pkgs.jq}/bin/jq -r '.result // "No result field"' 2>/dev/null || echo "$json_output"
              fi
              if [[ -n "$raw_stderr" ]]; then
                  echo ""
                  echo "=== Stderr ==="
                  echo "$raw_stderr"
              fi
          } > "''${log_base}.log"

          # Parse JSON response
          parse_claude_json "$json_output"

          # PRIORITY 1: Check for startup/configuration errors (non-zero exit before JSON)
          # These indicate Claude couldn't even start properly
          if [[ $exit_code -ne 0 && "$json_type" == "parse_error" ]]; then
              echo -e "  ''${RED}✗ ''${task_name}: Claude failed to start (exit: $exit_code)''${NC}"
              if [[ -n "$raw_stderr" ]]; then
                  echo -e "    ''${RED}$(echo "$raw_stderr" | head -1)''${NC}"
              fi

              # Check if it's a rate limit at the API level
              if is_rate_limited "$json_output" "$raw_stderr"; then
                  local next_attempt=$((rate_limit_count + 1))
                  echo -e "  ''${YELLOW}⏳ Rate limited (''${next_attempt}/''${MAX_CONSECUTIVE_RATE_LIMITS}), waiting ''${RATE_LIMIT_WAIT}s...''${NC}"
                  save_state "$iteration" "rate_limited" "$pending_before"
                  sleep $RATE_LIMIT_WAIT
                  return 2
              fi

              save_state "$iteration" "startup_error" "$pending_before"
              return 1
          fi

          # PRIORITY 2: Check JSON is_error field (most reliable for API errors)
          if [[ "$json_is_error" == "true" ]]; then
              echo -e "  ''${RED}✗ ''${task_name}: API error ($json_subtype)''${NC}"

              # Check for rate limiting via structured fields
              if is_rate_limited "$json_output" "$raw_stderr"; then
                  local next_attempt=$((rate_limit_count + 1))
                  echo -e "  ''${YELLOW}⏳ Rate limited (''${next_attempt}/''${MAX_CONSECUTIVE_RATE_LIMITS}), waiting ''${RATE_LIMIT_WAIT}s...''${NC}"
                  save_state "$iteration" "rate_limited" "$pending_before"
                  sleep $RATE_LIMIT_WAIT
                  return 2
              fi

              save_state "$iteration" "api_error_$json_subtype" "$pending_before"
              return 1
          fi

          # PRIORITY 3: Check protocol sentinels in result text (defined in our prompt)
          # IMPORTANT: Match only at line start to avoid false positives from code blocks,
          # ready-to-paste prompts, or quoted instructions that mention these tokens

          # Environment not capable - skip this task, leave PENDING for another host
          if echo "$json_result" | ${pkgs.ripgrep}/bin/rg -q '^ENVIRONMENT_NOT_CAPABLE'; then
              echo -e "  ''${YELLOW}⊘ ''${task_name}: requires different host''${NC}"
              save_state "$iteration" "environment_not_capable" "$pending_before"
              return 5
          fi

          # User input required - interactive task, needs manual completion via /next-task
          if echo "$json_result" | ${pkgs.ripgrep}/bin/rg -q '^USER_INPUT_REQUIRED'; then
              echo -e "  ''${YELLOW}⌨ ''${task_name}: requires user input (use /next-task interactively)''${NC}"
              save_state "$iteration" "user_input_required" "$pending_before"
              return 6
          fi

          # All tasks done
          if echo "$json_result" | ${pkgs.ripgrep}/bin/rg -q '^ALL_TASKS_DONE'; then
              local pending_after=$(pending_count)
              if [[ "$pending_after" == "0" ]]; then
                  echo -e "  ''${GREEN}✓ All tasks complete''${NC}"
                  save_state "$iteration" "all_complete" "$pending_after"
                  return 3
              fi
          fi

          # Task already complete (--task specific)
          if echo "$json_result" | ${pkgs.ripgrep}/bin/rg -q '^TASK_ALREADY_COMPLETE'; then
              echo -e "  ''${YELLOW}⊘ ''${task_name}: already complete''${NC}"
              save_state "$iteration" "task_already_complete" "$pending_before"
              return 7
          fi

          # Task not found (--task specific)
          if echo "$json_result" | ${pkgs.ripgrep}/bin/rg -q '^TASK_NOT_FOUND'; then
              echo -e "  ''${RED}✗ ''${task_name}: not found in plan file''${NC}"
              save_state "$iteration" "task_not_found" "$pending_before"
              return 8
          fi

          # PRIORITY 4: Success path - exit code 0 and type is "result" with subtype "success"
          if [[ $exit_code -eq 0 && "$json_type" == "result" && "$json_subtype" == "success" ]]; then
              local pending_after=$(pending_count)
              echo -e "  ''${GREEN}✓ ''${task_name} complete''${NC} (''${pending_before} → ''${pending_after} pending)"
              save_state "$iteration" "complete" "$pending_after"
              return 0
          fi

          # PRIORITY 5: Non-zero exit code with valid JSON (task execution failed)
          if [[ $exit_code -ne 0 ]]; then
              echo -e "  ''${RED}✗ ''${task_name} failed''${NC} (exit: $exit_code)"
              save_state "$iteration" "failed" "$pending_before"
              return 1
          fi

          # FALLBACK: Unexpected state - treat as success if we got here with exit 0
          local pending_after=$(pending_count)
          echo -e "  ''${YELLOW}? ''${task_name} completed (unexpected format)''${NC}"
          save_state "$iteration" "complete_unexpected" "$pending_after"
          return 0
      }

      # Handle --list mode: show task status and optionally select with fzf
      if [[ "$LIST_TASKS" == true ]]; then
          show_task_list
          echo ""

          # If interactive terminal, offer fzf selection
          if [[ -t 0 && -t 1 ]]; then
              echo -e "''${BLUE}Press Enter to select a task with fzf, or Ctrl+C to exit...''${NC}"
              read -r
              selected=$(select_task_with_fzf) || exit 0
              if [[ -n "$selected" ]]; then
                  TASK_ID="$selected"
                  echo -e "''${GREEN}Selected: $TASK_ID''${NC}"
              fi
          fi

          # If no task selected (non-interactive or user cancelled), just exit
          if [[ -z "$TASK_ID" ]]; then
              exit 0
          fi
      fi

      # Header
      echo -e "''${GREEN}"
      cat << 'BANNER'
      ╔═══════════════════════════════════════════════════════╗
      ║       Claude Code Task Runner                         ║
      ║       Ctrl+C to gracefully stop                       ║
      ╚═══════════════════════════════════════════════════════╝
      BANNER
      echo -e "''${NC}"

      echo "Plan file: $PLAN_FILE_ABS"
      echo "Account: $ACCOUNT_DISPLAY ($CLAUDE_CMD)"

      # Display mode with task ID if specified
      if [[ -n "$TASK_ID" ]]; then
          echo "Mode: $MODE (starting with task: $TASK_ID)"
      else
          echo "Mode: $MODE $([ "$MODE" = "count" ] && echo "($COUNT)")"
      fi

      INITIAL_PENDING=$(pending_count)
      echo "Pending tasks: $INITIAL_PENDING"
      echo "Delay: ''${DELAY_BETWEEN_TASKS}s"
      echo "Safety limits: ''${MAX_ITERATIONS} iterations, ''${MAX_RUNTIME_HOURS}h runtime"
      echo ""

      # Validate --task ID if specified
      if [[ -n "$TASK_ID" ]]; then
          if ! get_task_line_by_id "$TASK_ID" &>/dev/null || [[ -z "$(get_task_line_by_id "$TASK_ID")" ]]; then
              echo -e "''${RED}Error: Task '$TASK_ID' not found in plan file''${NC}"
              echo "Use --list to see available tasks"
              exit 1
          fi
          if ! is_task_pending "$TASK_ID"; then
              echo -e "''${YELLOW}Warning: Task '$TASK_ID' is not PENDING (may already be complete)''${NC}"
          fi
      fi

      # Pre-flight validation
      if [[ "$INITIAL_PENDING" == "0" ]]; then
          echo -e "''${GREEN}No pending tasks found. Nothing to do.''${NC}"
          save_state "0" "no_pending" "0"
          exit 0
      fi

      # Validate plan file format
      if ! ${pkgs.ripgrep}/bin/rg -q '^\|\s*(Task|#)\s*\|' "$PLAN_FILE"; then
          echo -e "''${YELLOW}Warning: Plan file may not have standard Progress Tracking table''${NC}"
      fi

      if ${pkgs.ripgrep}/bin/rg -q '\|\s*Pending\s*\|' "$PLAN_FILE" && ! ${pkgs.ripgrep}/bin/rg -q '\|\s*TASK:PENDING\s*\|' "$PLAN_FILE"; then
          echo -e "''${YELLOW}Warning: Plan file uses 'Pending' instead of 'TASK:PENDING'''''${NC}"
          echo -e "''${YELLOW}Please update status tokens for reliable matching''${NC}"
      fi

      # Enhanced dry-run: show detailed execution preview
      if [[ "$DRY_RUN" == true ]]; then
          echo -e "''${YELLOW}=== DRY RUN MODE ===''${NC}"
          echo ""

          # Determine which task would run (no 'local' - we're at script top level)
          preview_task_id=""
          preview_task_model=""
          preview_model_source=""
          preview_effective_model=""

          if [[ -n "$TASK_ID" ]]; then
              preview_task_id="$TASK_ID"
              preview_task_model=$(get_task_model_by_id "$TASK_ID")
          else
              preview_task_id=$(get_next_task_name)
              preview_task_model=$(get_next_task_model)
          fi

          # Determine effective model
          if [[ -n "$MODEL_OVERRIDE" ]]; then
              preview_model_source="CLI --model flag"
              preview_effective_model="$MODEL_OVERRIDE"
          elif [[ -n "$preview_task_model" ]]; then
              preview_model_source="Plan file Model column"
              preview_effective_model="$preview_task_model"
          else
              preview_model_source="Account default"
              preview_effective_model="(default)"
          fi

          echo -e "''${CYAN}Execution Preview:''${NC}"
          echo "  Task ID:     $preview_task_id"
          echo "  Model:       $preview_effective_model ($preview_model_source)"
          echo "  Claude cmd:  $CLAUDE_CMD"
          echo ""
          echo -e "''${CYAN}Would execute:''${NC}"
          if [[ "$preview_effective_model" != "(default)" ]]; then
              echo "  $CLAUDE_CMD -p --model $preview_effective_model --output-format json --permission-mode bypassPermissions <prompt>"
          else
              echo "  $CLAUDE_CMD -p --output-format json --permission-mode bypassPermissions <prompt>"
          fi
          echo ""
          echo -e "''${CYAN}Prompt (truncated):''${NC}"
          echo "  ''${PROMPT:0:200}..."
          exit 0
      fi

      # Trap Ctrl+C
      trap 'pending_now=$(pending_count); print_exit_summary "Interrupted by user (Ctrl+C)" "$task_counter" "$pending_now"; save_state "$task_counter" "interrupted"; exit 130' INT

      # Main loop
      task_counter=0
      retries=0
      consecutive_rate_limits=0
      specific_task_done=false  # Track if we've run the --task specified task

      while true; do
          pending=$(pending_count)

          # Check: all complete
          if [[ "$pending" == "0" ]]; then
              print_exit_summary "All tasks completed successfully" "$task_counter" "0"
              save_state "$task_counter" "all_complete"
              exit 0
          fi

          # Check: max iterations
          if [[ $task_counter -ge $MAX_ITERATIONS ]]; then
              print_exit_summary "Iteration limit reached (''${MAX_ITERATIONS} tasks)" "$task_counter" "$pending"
              save_state "$task_counter" "max_iterations"
              exit 1
          fi

          # Check: max runtime
          runtime=$(($(date +%s) - START_TIME))
          max_runtime_seconds=$((MAX_RUNTIME_HOURS * 3600))
          if [[ $runtime -ge $max_runtime_seconds ]]; then
              print_exit_summary "Runtime limit reached (''${MAX_RUNTIME_HOURS} hours)" "$task_counter" "$pending"
              save_state "$task_counter" "max_runtime"
              exit 1
          fi

          # Check: mode limits
          if [[ "$MODE" == "single" && $task_counter -ge 1 ]]; then
              break
          fi

          if [[ "$MODE" == "count" && $task_counter -ge $COUNT ]]; then
              break
          fi

          task_counter=$((task_counter + 1))

          # Determine which task to run:
          # - First iteration with --task: run the specific task
          # - Subsequent iterations: run next pending task
          current_task_id=""
          if [[ -n "$TASK_ID" && "$specific_task_done" == false ]]; then
              current_task_id="$TASK_ID"
              specific_task_done=true
          fi

          run_task $task_counter $consecutive_rate_limits "$current_task_id"
          result=$?

          case $result in
              0)  # Success
                  retries=0
                  consecutive_rate_limits=0
                  ;;
              2)  # Rate limited
                  task_counter=$((task_counter - 1))
                  retries=$((retries + 1))
                  consecutive_rate_limits=$((consecutive_rate_limits + 1))

                  # Circuit breaker
                  if [[ $consecutive_rate_limits -ge $MAX_CONSECUTIVE_RATE_LIMITS ]]; then
                      pending_now=$(pending_count)
                      print_exit_summary "Rate limit circuit breaker (''${MAX_CONSECUTIVE_RATE_LIMITS} consecutive)" "$task_counter" "$pending_now"
                      save_state "$task_counter" "rate_limit_circuit_breaker"
                      exit 1
                  fi

                  if [[ $retries -ge $MAX_RETRIES ]]; then
                      pending_now=$(pending_count)
                      print_exit_summary "Retry limit reached (''${MAX_RETRIES} attempts)" "$task_counter" "$pending_now"
                      save_state "$task_counter" "max_retries"
                      exit 1
                  fi
                  continue
                  ;;
              3)  # All complete
                  print_exit_summary "All tasks completed (confirmed by Claude)" "$task_counter" "0"
                  exit 0
                  ;;
              4)  # Permission required - user interaction needed
                  task_counter=$((task_counter - 1))  # Don't count as attempt
                  pending_now=$(pending_count)
                  print_exit_summary "Stopped: Claude requires write permission" "$task_counter" "$pending_now"
                  save_state "$task_counter" "permission_required"
                  exit 1
                  ;;
              5)  # Environment not capable - task requires different host
                  task_counter=$((task_counter - 1))  # Don't count as attempt
                  pending_now=$(pending_count)
                  print_exit_summary "Task requires different host (ENVIRONMENT_NOT_CAPABLE)" "$task_counter" "$pending_now"
                  save_state "$task_counter" "environment_not_capable"
                  exit 0  # Exit cleanly - user should run on appropriate host
                  ;;
              6)  # User input required - interactive task
                  task_counter=$((task_counter - 1))  # Don't count as attempt
                  pending_now=$(pending_count)
                  print_exit_summary "Task requires user input - run /next-task interactively" "$task_counter" "$pending_now"
                  save_state "$task_counter" "user_input_required"
                  exit 0  # Exit cleanly - user should run /next-task manually
                  ;;
              7)  # Task already complete (--task specific)
                  task_counter=$((task_counter - 1))  # Don't count as attempt
                  pending_now=$(pending_count)
                  print_exit_summary "Specified task already complete" "$task_counter" "$pending_now"
                  save_state "$task_counter" "task_already_complete"
                  exit 0  # Exit cleanly - task was already done
                  ;;
              8)  # Task not found (--task specific)
                  task_counter=$((task_counter - 1))  # Don't count as attempt
                  pending_now=$(pending_count)
                  print_exit_summary "Specified task not found in plan file" "$task_counter" "$pending_now"
                  save_state "$task_counter" "task_not_found"
                  exit 1  # Exit with error - task ID was invalid
                  ;;
              *)  # Failure
                  retries=0
                  consecutive_rate_limits=0
                  echo -e "''${YELLOW}Continuing despite failure...''${NC}"
                  ;;
          esac

          # Delay before next
          if [[ "$DRY_RUN" == true ]]; then
              break
          fi

          if [[ "$MODE" != "single" ]]; then
              remaining=$(pending_count)
              if [[ $remaining -gt 0 ]]; then
                  echo -e "''${BLUE}Next task in ''${DELAY_BETWEEN_TASKS}s... ($remaining pending)''${NC}"
                  sleep $DELAY_BETWEEN_TASKS
              fi
          fi
      done

      # Normal exit
      remaining=$(pending_count)
      print_exit_summary "Requested tasks completed" "$task_counter" "$remaining"
    '';

in
{
  options.programs.claude-code.taskAutomation = {
    enable = mkEnableOption "Claude Code task automation (run-tasks script and /next-task command)";

    safetyLimits = {
      maxIterations = mkOption {
        type = types.int;
        default = 100;
        description = "Maximum number of task iterations before stopping";
      };

      maxRuntimeHours = mkOption {
        type = types.int;
        default = 8;
        description = "Maximum total runtime in hours";
      };

      maxConsecutiveRateLimits = mkOption {
        type = types.int;
        default = 5;
        description = "Circuit breaker threshold for consecutive rate limits";
      };

      rateLimitWaitSeconds = mkOption {
        type = types.int;
        default = 300;
        description = "Seconds to wait after hitting a rate limit";
      };

      maxRetries = mkOption {
        type = types.int;
        default = 3;
        description = "Maximum retries for a single task after rate limits";
      };

      delayBetweenTasks = mkOption {
        type = types.int;
        default = 10;
        description = "Seconds to wait between tasks";
      };
    };

    logDirectory = mkOption {
      type = types.str;
      default = ".claude-task-logs";
      description = "Directory for task execution logs (relative to current working directory)";
    };

    stateFile = mkOption {
      type = types.str;
      default = ".claude-task-state";
      description = "File for persisting task runner state (relative to current working directory)";
    };
  };

  config = mkIf (cfg.enable && taskCfg.enable) {
    # Generate run-tasks-<account> scripts for each enabled account
    # e.g., run-tasks-max, run-tasks-pro, run-tasks-work
    home.packages = mapAttrsToList
      (accountName: account:
        mkRunTasksScript {
          inherit accountName;
          displayName = account.displayName or "Claude ${accountName}";
          claudeWrapper = "claude${accountName}";
        }
      )
      (filterAttrs (_: account: account.enable) cfg.accounts);

    # Deploy /next-task slash command to each enabled account's commands/ directory
    # Use cfg.nixcfgPath for consistency with memory-commands.nix (fixes symlink creation)
    home.file = mkMerge (
      # Slash commands
      (mapAttrsToList
        (accountName: account:
          if account.enable then {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${accountName}/commands/next-task.md" = {
              text = nextTaskMd;
            };
          } else { }
        )
        cfg.accounts)
      ++
      # Zsh completions
      (mapAttrsToList
        (accountName: account:
          if account.enable then {
            ".local/share/zsh/site-functions/_run-tasks-${accountName}" = {
              source = mkZshCompletion { inherit accountName; };
            };
          } else { }
        )
        cfg.accounts)
      ++
      # Bash completions
      (mapAttrsToList
        (accountName: account:
          if account.enable then {
            ".local/share/bash-completion/completions/run-tasks-${accountName}" = {
              source = mkBashCompletion { inherit accountName; };
            };
          } else { }
        )
        cfg.accounts)
    );
  };
}
