# General Bash Utility Library
#
# - To be sourced, not executed. No shebang. See BASH_SOURCE check below.
# - Let calling shell set options and decide whether to export vars/funcs to its env.
#   - Especially important we don't set -e, which can result in exiting the 
#     calling shell on err, which is not very nice.
# TODO: Make this shell-agnostic - refer to chksh.sh
# [[ "${0}" = "${BASH_SOURCE[0]}" ]] && printf "ERROR: ${BASH_SOURCE[0]} may not be executed!\n" && exit 1
# SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Source color functions from lib directory
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
if [[ -f "${SCRIPT_DIR}/color-utils.bash" ]]; then
    source "${SCRIPT_DIR}/color-utils.bash"
    # Initialize color support
    detect_color_support
fi

# Simple abort function for error handling
abort() {
    printf "$@" >&2
    echo >&2
    return 1
}

# Auto-export all functions and variables defined in this file
# Save current allexport state and enable it
if [[ $- == *a* ]]; then
    _allexport_was_set=true
else
    _allexport_was_set=false
fi
set -a

# Source required files
LOCAL_BIN_DIR=$HOME/bin
#source "${LOCAL_BIN_DIR}"/.env
source "${LOCAL_BIN_DIR}"/colorfuncs.sh

# Quiet impls of pushd/popd
pushdq() { command pushd "$@" >/dev/null ; }
popdq() { command popd "$@" >/dev/null ; }

function edit_my_systemd_files () {
  ( 
    cd "${HOME}"/.config/systemd/user
    nvim \
    && clear \
    && systemd-analyze --user verify *.service \
    && systemctl --user daemon-reload
  )
}
function modify_my_systemd_files() { edit_my_systemd_files; }

function edit_my_desktop_files () {
  ( 
    cd ${XDG_DATA_HOME}/applications
    nvim \
    && clear \
    && desktop-file-validate ${XDG_DATA_HOME}/applications/*.desktop \
    && update-desktop-database
  )
}
function modify_my_desktop_files() { edit_my_desktop_files; }

function stopwatch() {
  local start=$(date +%s%N)
  read -p "Stopwatch started! Hit <Enter> to end and print elapsed time.. "
  local end=$(date +%s%N)
  echo "Stopwatch stopped! Elapsed time: $(( $((end-start)) / 1000000000 )).$(( $((end-start)) % 1000000000 ))"
}

function devtestloop() {
  function usage() {
  cat << "EOF"
Iteratively run a test command when related file(s) are modified

Usage: devtestloop COMPOUND_COMMAND FILE [...]

Example: Run a script when it is modified 
  devtestloop ~/.local/bin/somescript.sh ~/.local/bin/somescript.sh

Example: Source files and run dependent compound command when either is modified
  f=~/.local/bin/{these,those}funcs.sh devtestloop "source $f && thisfunc && sleep 2 && thatfunc" "$f"
EOF
  }
  
  if [[ $# -lt 2 ]]; then
    echo "Error: devtestloop requires at least 2 args" >&2
    usage >&2
    return 1
  fi
  
  local compound_command="$1"
  shift # remaining args are files to watch
  local files=( "$@" )
  local TIMEFMT='%H:%M:%S'
  local inotifyevent="close_write,moved_to"
  
  # Check if inotifywait is available
  if ! command -v inotifywait >/dev/null 2>&1; then
    echo "Error: inotifywait not found. Please install inotify-tools." >&2
    echo "On NixOS: add 'inotify-tools' to your packages in configuration.nix or home.nix" >&2
    return 1
  fi
  
  # Validate that all files exist
  local file
  for file in "${files[@]}"; do
    if [[ ! -e "$file" ]]; then
      echo "Error: File '$file' does not exist" >&2
      return 1
    fi
  done
  
  # Save current job control state and disable it to suppress messages
  local monitor_was_set=false
  [[ $- == *m* ]] && monitor_was_set=true
  set +m
  
  # Create temporary directory for coordination
  local tmpdir
  tmpdir=$(mktemp -d)
  local trigger_fifo="$tmpdir/trigger"
  local event_file="$tmpdir/event_details"
  local cleanup_flag="$tmpdir/cleanup"
  
  # Initialize PID variables
  local inotify_pid=""
  local input_pid=""
  local timeout_pid=""
  
  # Cleanup function that will be called on exit
  cleanup_devtestloop() {
    # Signal cleanup to background processes
    touch "$cleanup_flag" 2>/dev/null
    
    # Kill all background processes
    [[ -n "$inotify_pid" ]] && kill "$inotify_pid" 2>/dev/null
    [[ -n "$input_pid" ]] && kill "$input_pid" 2>/dev/null
    [[ -n "$timeout_pid" ]] && kill "$timeout_pid" 2>/dev/null
    
    # Kill any remaining child processes
    jobs -p | xargs -r kill 2>/dev/null
    
    wait 2>/dev/null
    rm -rf "$tmpdir" 2>/dev/null
    $monitor_was_set && set -m
    
    # Exit the function
    return 0
  }
  
  # Set up trap for cleanup
  trap 'cleanup_devtestloop; return 130' INT
  trap 'cleanup_devtestloop' EXIT TERM
  
  # Create named pipe for event coordination
  mkfifo "$trigger_fifo"
  
  # Main event loop
  while [[ ! -f "$cleanup_flag" ]]; do
    echo "$(cf_cyan "Watching files for changes.") $(cf_yellow "Press ENTER to manually trigger build,") $(cf_red "Ctrl+C to exit.")"
    # Clear any previous event details
    rm -f "$event_file"
    
    # Start file monitoring in background (suppressing all job control output)
    (
      inotifywait -q -e "$inotifyevent" --format '%w%f %e %T' --timefmt '%H:%M:%S' "${files[@]}" >/dev/null 2>&1
      if [[ $? -eq 0 ]] && [[ ! -f "$cleanup_flag" ]]; then
        echo "file_change:$(date +"$TIMEFMT")" > "$trigger_fifo" 2>/dev/null
      fi
    ) 2>/dev/null &
    inotify_pid=$!
    
    # Start input monitoring in background (suppressing all job control output)
    (
      # Read with timeout to prevent hanging
      if IFS= read -r -t 3600; then  # 1 hour timeout
        # Check if cleanup is in progress
        [[ -f "$cleanup_flag" ]] && exit 1
        
        # Write manual trigger and signal
        echo "manual_trigger:$(date +"$TIMEFMT")" > "$trigger_fifo" 2>/dev/null
      fi
    ) 2>/dev/null &
    input_pid=$!
    
    # Wait for either trigger (blocking read that can be interrupted)
    local trigger_info=""
    
    # Use a timeout with the read from the fifo
    # This will block but can be interrupted by signals
    if ! read -t 300 trigger_info < "$trigger_fifo" 2>/dev/null; then
      # Timeout or interrupt - check if cleanup was requested
      if [[ -f "$cleanup_flag" ]]; then
        break
      fi
      # Timeout reached, kill background processes and restart
      kill "$inotify_pid" "$input_pid" 2>/dev/null
      wait "$inotify_pid" "$input_pid" 2>/dev/null
      unset inotify_pid input_pid
      continue
    fi
    
    # Check if cleanup was requested during the read
    if [[ -f "$cleanup_flag" ]]; then
      break
    fi
    
    # We got a trigger - kill background processes
    kill "$inotify_pid" "$input_pid" 2>/dev/null
    wait "$inotify_pid" "$input_pid" 2>/dev/null
    unset inotify_pid input_pid
    
    # Parse trigger information
    local trigger_type="${trigger_info%%:*}"
    local trigger_time="${trigger_info#*:}"
    
    # Handle the trigger and execute command - disable allexport to prevent variable display
    (
      set +a  # Disable allexport to prevent automatic variable display
      local event_description
      case "$trigger_type" in
        "file_change")
          event_description="FILE CHANGE DETECTED"
          echo "File modification detected" > "$event_file"
          ;;
        "manual_trigger")
          event_description="MANUAL BUILD TRIGGER"
          echo "Manual build trigger (ENTER pressed)" > "$event_file"
          ;;
        *)
          event_description="UNKNOWN TRIGGER"
          echo "Unknown trigger: $trigger_type" > "$event_file"
          ;;
      esac
      
      # Display the event information with proper formatting
      cat << EOF
$(cf_yellow "╔═══════") $(printf "%s%s%s" "${CF_BOLD}" "DEVTESTLOOP: ${event_description} AT ${trigger_time}" "${CF_RESET}") $(cf_yellow "════════╗")
$(cf_yellow "║")                                                                
$(cf_yellow "║") $(printf "%s%s%s" "${CF_BOLD}" "FILES WATCHED:" "${CF_RESET}") ${files[*]}
$(cf_yellow "║") $(printf "%s%s%s" "${CF_BOLD}" "EVENT DETAILS:" "${CF_RESET}") $(cat "$event_file" 2>/dev/null || echo "N/A")
$(cf_yellow "║") $(printf "%s%s%s" "${CF_BOLD}" "EXECUTING CMD:" "${CF_RESET}") $compound_command
$(cf_yellow "╙")                                               
EOF
    ) 2>/dev/null
    
    # Execute the command
    eval "$compound_command"
    
    # Brief pause before next iteration
    sleep 1
  done
  
  # Clean exit when loop ends
  cleanup_devtestloop
}

function contains_usage() {
    cat << "EOF"
NAME
contains()

SYNOPSIS
if contains STRING SUBSTRING; then
  echo "string '$STRING' contains '$SUBSTRING'"
fi

DESCRIPTION
Returns 0 if the specified string contains the specified substring,
otherwise returns 1.

OPTIONS
    -h  - show this (h)elp

EOF
}
function contains() {
  if [[ $# -ne 2 ]]; then
    echo "Error: ${FUNCNAME[0]} requires 2 args: STRING SUBSTRING" >&2
    contains_usage >&2
    return 1
  fi
  STRING="$1"
  SUBSTRING="$2"
  test "${STRING#*"$SUBSTRING"}" != "$STRING"
}

function recipeloglink() {
  if [[ $# -eq 0 ]]; then
    echo "Error: ${FUNCNAME[0]} requires at least one arg: TARGET" >&2
    return 1
  fi
  local TARGET="$1"	 
  # stdout IS the function's output
  printf "runrecipe-${TARGET:0:12}.log"  
}  
function runrecipe_usage() {
    cat << EOF
NAME
runrecipe()

SYNOPSIS
runrecipe TARGET [COMPOUND_COMMAND]

DESCRIPTION
    Wrapper for DRY running of make target recipes. Handles stdout/err in a concise 
    and consistent manner. Runs recipe in background, streaming its stdout/err to file.
    Updates a simple progress bar. Prints recipe elapsed run time upon completion.

  EXIT Trap / Handler
    runrecipe installs an EXIT trap / signal handler to cleanup after itself. If the recipe 
    is implemented as a single script, i.e. if COMPOUND_COMMAND is a single script 
    invocation (with or without args), the EXIT handler will call a function named
    custom_runrecipe_exit_handler() if it is defined inside that script and may be called 
    by executing the script with $1=${CUSTOM_RUNRECIPE_EXIT_HANDLER}. This allows 
    recipes implemented as a script to custom cleanup steps required by the recipe. 
    ${CUSTOM_RUNRECIPE_EXIT_HANDLER} will be passed $1=<final process exit status>.

OPTIONS
    -h  - show this (h)elp

EOF
}
function runrecipe() {
  if [[ $# -eq 0 ]]; then
    echo "Error: runrecipe requires at least one arg:" >&2
    runrecipe_usage >&2
    return 1
  fi
  local TARGET="$1"	 
  shift  # remaining args are the recipe command, which can be empty
  local PROGRESS_UPDATE_INTERVAL_SEC=5
  PROGRESS_UPDATE_PID=

  # Install EXIT signal handler (to clean up files, folders and processes) iff:
  #   - the first token in the recipe's COMPOUND_COMMAND (now held in $@) is the path to 
  #     an executable script, and
  #   - the function ${CUSTOM_RUNRECIPE_EXIT_HANDLER} is defined in that script
  #     and may be called by executing the script with $1="${CUSTOM_RUNRECIPE_EXIT_HANDLER}"
  [ -n "$1" ] && [ -x $1 ] && grep -q "${CUSTOM_RUNRECIPE_EXIT_HANDLER}" "$1" && SCRIPT_DEFINING_CUSTOM_RUNRECIPE_EXIT_HANDLER="$1"
  # Note \${PROGRESS_UPDATE_PID} is not evaluated until trap execution, bc we don't know this
  # until later in this function 
  trap "runrecipe_exit_handler ${TARGET} \${PROGRESS_UPDATE_PID} \
    ${SCRIPT_DEFINING_CUSTOM_RUNRECIPE_EXIT_HANDLER:-}" EXIT
  # Also handle SIGINT - just print and raise current process status
  trap 's=$?; echo "trapped SIGINT, exit status=\$s"; exit $s' INT

  # Print header indicating recipe is running and how/where to see more detail
  # This is a target- and recipe-specific log file in /tmp.
  _log="$(mktemp --tmpdir=/tmp runrecipe-$TARGET-XXXX.log)"
  # Prepend a header into the recipe log file (will show up in less --header 1)
  # local hdrline1="$(center "$(bluebold  "Target %b Recipe Log File" "$(yellowbold "$TARGET")")")"
  local hdrline1="$(bluebold  "Target %b Recipe Log File" "$(yellowbold "${TARGET:0:16}")")"
  echo -e "${hdrline1}\n\n" > "${_log}"

  # create a static per-target symlink for convenience, truncating long target names
  _loglink="$(recipeloglink "${TARGET}")"  
  ln -sf "${_log}" "${_loglink}"
  printf -v recipeline "%b" "$(blue "running recipe for") $(bluebold ${TARGET}) $(blue "target")"
  printf -v lognoteline "\tfor detailed stdout/err run %b" "$(yellow "tailrecipelog %s" "${TARGET}")"
  printf "%b\n%b\n" "${recipeline}" "${lognoteline}"
  
  # Indicate progress by appending . to first header line every ${PROGRESS_UPDATE_INTERVAL_SEC}
  # Calculate length of printable chars in recipeline, sans control chars
  #ascii_recipeline="${recipeline//$'\e'*([[0-9;\(B$'\e'])m/}"  # didn't work
  #recipeline_printable="${recipeline//!([:alnum:]|[:space:]|[:punct:])/}"  # didn't work
  recipeline_sans_cc="$(sed 's,\x1B\[[0-9;]*[a-zA-Z],,g'<<<"${recipeline}")"
  # See bash cursor movement docs: https://tldp.org/HOWTO/Bash-Prompt-HOWTO/x405.html
  tput cuu1; tput cuu1; tput cuf "${#recipeline_sans_cc}"  # move cursor to end of first header line
  while :; do blue '.'; sleep "$PROGRESS_UPDATE_INTERVAL_SEC"; done & PROGRESS_UPDATE_PID=$!
  
  # Redirect stdout/err to tmp file for remainder of recipe execution (to keep make shell concise)
  exec >> "${_log}"
  exec 2>&1
  # Run the recipe command, timing it with bash time builtin, and some shell magic
  # to store the elapsed time into a variable and ensure recipe stdout/err is unaltered.
  log "runrecipe: executing and timing COMPOUND_COMMAND='$@'.."
  exec 3>&1 4>&2
  local recipetime=$(TIMEFORMAT='%3lR'; { time "$@" 1>&3 2>&4; echo "$?">res; } 2>&1)
  local recipe_exit_status=$(<"res")
  rm res
  exec 3>&- 4>&-
  log "runrecipe: completed in %s with exit status %d" "${recipetime}" "${recipe_exit_status}"
  # Reset stdout/err back to this terminal (please be less verbose now)
  exec &>/dev/tty
  
  # Write status and elapsed time
  local C=green sstr=SUCCESS
  [[ $recipe_exit_status -ne 0 ]] && C=red && sstr="ERROR $recipe_exit_status"
  printf "%b  took %s\n" "$(${C} ${sstr})" "${recipetime}"
  tput cud1
  local newhdrline1="$(bluebold "%b Recipe Log: " "${TARGET:0:16}"; "${C}" "${sstr}"; printf " in %s" "${recipetime}")"
  sed -i "1s/.*/$newhdrline1/" "${_log}"
  # restore cursor to resume writing at the end of terminal output
  # tput ll  # didn't work: last line, first column
  exit $recipe_exit_status
}
function runrecipe_exit_handler() {
  local final_exit_status=$?
  # Reset stdout/err back to terminal
  exec &>/dev/tty
  local C=green
  [[ $final_exit_status -ne 0 ]] && C=red
  if [[ $# -eq 0 ]]; then
    echo "Error: runrecipe_exit_handler requires at least two args: \$1: TARGET, \$2: PID_TO_KILL" >&2
    return 1
  fi
  local TARGET="${1}"
  local PID_TO_KILL="${2}"
  local SCRIPT_DEFINING_CUSTOM_RUNRECIPE_EXIT_HANDLER="${3:-}"
  # log -r "runrecipe_exit_handler: final_exit_status=$final_exit_status TARGET=${TARGET} PID_TO_KILL=${PID_TO_KILL} SCRIPT_DEFINING_CUSTOM_RUNRECIPE_EXIT_HANDLER=${SCRIPT_DEFINING_CUSTOM_RUNRECIPE_EXIT_HANDLER}"
  if [ -n "$PID_TO_KILL" ] && [ "$PID_TO_KILL" -gt "1" ] 2>/dev/null; then
    kill "${PID_TO_KILL}"
  fi
  if [ -n "${SCRIPT_DEFINING_CUSTOM_RUNRECIPE_EXIT_HANDLER}" ]; then
    # colorize "${C}" "\nexecuting %s() in recipe script %s..\n" "${CUSTOM_RUNRECIPE_EXIT_HANDLER}" \
    #   "${SCRIPT_DEFINING_CUSTOM_RUNRECIPE_EXIT_HANDLER}"
    "${SCRIPT_DEFINING_CUSTOM_RUNRECIPE_EXIT_HANDLER}" "${CUSTOM_RUNRECIPE_EXIT_HANDLER}" "$final_exit_status"
  fi
  # SHOW_RECIPE_LOG_ON_ERROR=true
  if [ -v SHOW_RECIPE_LOG_ON_ERROR ] && [ $final_exit_status -ne 0 ]; then
    tailrecipelog "${TARGET}"
  fi
}

function nuke_domains() {
    if [[ "$#" -lt 1 ]]; then
        echo "Error: ${FUNCNAME[0]} requires at least one arg: DOMAIN [...]" >&2
        return 1
    fi
    local DOMAINS="$@"
    log "Cleaning up libvirt domains (${DOMAINS})..."
    (
      set -x
      parallel "virsh --quiet destroy  {} ${ERRSINK}" 														 ::: ${DOMAINS} 
      parallel "virsh --quiet undefine {} --nvram --remove-all-storage ${ERRSINK}" ::: ${DOMAINS} 
      virsh list --all --name
    )
}

function wait_for_virsh_domstate() {
  if [[ "$#" -lt 2 ]]; then
    echo "Error: ${FUNCNAME[0]} requires at least two args: \$1=VIRSH_DOMAIN \$2=DESIRED_STATE" >&2
    return 1
  fi
  local VIRSH_DOMAIN="$1"
  local DESIRED_STATE="$2"
  local TIMEOUT_SEC=30
  [[ "$#" -gt 2 ]] && TIMEOUT_SEC="$3"
  log -n "Waiting up to %dsec for %s guest domstate to be '%s'.." "${TIMEOUT_SEC}" "${VIRSH_DOMAIN}" "${DESIRED_STATE}"
  local DOMST=''
  until [ "${DOMST}" == "${DESIRED_STATE}" ] || [ $TIMEOUT_SEC -eq 0 ]; do
    sleep 1
    printf "."
    TIMEOUT_SEC=$(( TIMEOUT_SEC-1 ))
    DOMST="$(virsh domstate --domain ${VIRSH_DOMAIN})"
  done
  if [ "${DOMST}" != "${DESIRED_STATE}" ]; then
    fail "Timed out waiting for guest %s domstate to be '%s'" "${VIRSH_DOMAIN}" "${DESIRED_STATE}"
  fi
  colorize GREEN "Guest %s reached desired domstate '%s'\n" "${VIRSH_DOMAIN}" "${DESIRED_STATE}"
}

function check_required_binaries() {
  [[ "$#" -eq 0 ]] && return
  local OPTIND _cmd_output='' VERBOSE=false
  while getopts "hv" opt; do
      case "$opt" in
          h) check_required_binaries_usage ;;
          v) VERBOSE=true ;;
          *) echo "Unsupported option." && check_required_binaries_usage  ;;
      esac
  done
  shift $((OPTIND - 1))
  local _required_binaries=("${@}")
  if ! _cmd_output=$(parallel command -V ::: "${_required_binaries[@]}" 2>&1); then 
    err "ERROR: One of more required binaries are not on path:\n%s" "$(grep 'not found'<<<"${_cmd_output}")"
    [[ $- != *i* ]] && exit 1  # only exit if shell is interactive
  else
    if $VERBOSE; then log "All required binaries are on path:\n%s" "${_cmd_output}"; fi
  fi
}
function check_required_binaries_usage() {
    cat << EOF
NAME
    Exit shell if the specified list of binaries are NOT all on PATH.

SYNOPSIS
check_required_binaries bin1 [bin2 bin3 ...]

DESCRIPTION
    Validate that the specified list of binaries are on PATH. Exits with non-zero code if not.

OPTIONS
    -h  - show this (h)elp
    -v  - print binary details to stdout/err

EOF
}

is_wsl() {
    if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ] || \
       [ -n "${WSL_DISTRO_NAME}" ] || \
       [ -n "${WSL_INTEROP}" ]; then
        return 0
    else
        return 1
    fi
}

copy_to_clipboard() {
  local input="$1"

  # Error handling function
  error_exit() {
    echo "Error: $1" >&2
    exit 1
  }

  if is_wsl; then
    if command -v powershell.exe &>/dev/null; then
      # Use PowerShell Set-Clipboard
      echo -n "$input" | powershell.exe -Command "Set-Clipboard -Value \$input" || error_exit "Failed to copy using PowerShell Set-Clipboard."
    elif command -v clip.exe &>/dev/null; then
      # Fallback to clip.exe
      echo -n "$input" | clip.exe || error_exit "Failed to copy using clip.exe."
    else
      error_exit "Neither PowerShell nor clip.exe found in WSL. Clipboard functionality unavailable."
    fi
  elif [[ "$(uname)" == "Darwin" ]]; then
    # macOS environment
    if command -v pbcopy &>/dev/null; then
      echo -n "$input" | pbcopy || error_exit "Failed to copy using pbcopy."
    else
      error_exit "pbcopy not found. Ensure it is installed on macOS."
    fi
  elif command -v xclip &>/dev/null; then
    # Linux with xclip installed
    echo -n "$input" | xclip -selection clipboard || error_exit "Failed to copy using xclip."
  elif command -v wl-copy &>/dev/null; then
    # Wayland-based Linux with wl-clipboard installed
    echo -n "$input" | wl-copy || error_exit "Failed to copy using wl-copy."
  else
    error_exit "No compatible clipboard tool found. Install xclip or wl-clipboard."
  fi
}

exec_local_script_on_serial() {
    local local_script_path="$1"
    local local_script_output="${local_script_path%.*}.output.txt"
    local device=/dev/ttyUSB0
    local baud=115200

    if false; then
        # Claude suggested, but can't get SYSTEM: to run locally-defined script remotely
        socat \
          FILE:"${device}",raw,echo=0,icanon,ixon,ixoff,min=1,time=5,icrnl=0 \
          SYSTEM:"$(cat ${local_script_path})" \
          > "$local_script_output" 2>&1
    else
        # Send a command string over serial port session, which:
        #   1. dumps contents of local script into a tmp script file on serial target
        #   2. execute the script
        #   3. remove the script
        # All output from the serial session is read by socat and redirected to file.
        local remote_script_path=/tmp/remote_script.sh
        (
            echo "cat << EOFSCRIPT > $remote_script_path"
            cat "$local_script_path"
            echo EOFSCRIPT
            echo "chmod +x $remote_script_path"
            echo "$remote_script_path"
            # echo "rm $remote_script_path"  # Optional: clean up after execution
        ) | socat - \
            "$device",b"$baud",raw,echo=1,icanon,ixon,ixoff,min=1,time=5,icrnl=0 \
            > "$local_script_output" 2>&1
    fi

    echo
    echo "Executed $local_script_path in serial console session on $device."
    echo "All output has been written to $local_script_output:"
    sed 's/^/    /' "$local_script_output"
    
}

print_subscript() {
  local num=$1
  
  # Current implementation - Unicode Mathematical Subscripts
  local subscripts=(₀ ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉)
  
  # Alternative 1: Enclosed/Circled Numbers (Most Readable)
  # local subscripts=(⓪ ① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨)
  
  # Alternative 2: Double Circled Numbers
  # local subscripts=(⓿ ❶ ❷ ❸ ❹ ❺ ❻ ❼ ❽ ❾)
  
  # Alternative 3: Parenthesized Numbers (note: ⑴-⑼ are 1-9, no 0)
  # local subscripts=("⑴" "⑵" "⑶" "⑷" "⑸" "⑹" "⑺" "⑻" "⑼")  # Missing 0
  
  # Alternative 4: Bracketed with subscript parentheses
  # local subscripts=("₍₀₎" "₍₁₎" "₍₂₎" "₍₃₎" "₍₄₎" "₍₅₎" "₍₆₎" "₍₇₎" "₍₈₎" "₍₉₎")
  
  # Alternative 5: ASCII-style (highly readable)
  # local subscripts=("[0]" "[1]" "[2]" "[3]" "[4]" "[5]" "[6]" "[7]" "[8]" "[9]")
  
  # Alternative 6: Underscore prefix (simple fallback)
  # local subscripts=("_0" "_1" "_2" "_3" "_4" "_5" "_6" "_7" "_8" "_9")
  
  # Alternative 7: Negative Circled Numbers (white on black)
  # local subscripts=(⓿ ❶ ❷ ❸ ❹ ❺ ❻ ❼ ❽ ❾)  # Note: same as Alternative 2
  
  # Alternative 8: Squared Numbers (CJK enclosed)
  # local subscripts=(🄀 🄁 🄂 🄃 🄄 🄅 🄆 🄇 🄈 🄉)  # May not display in all terminals

  if [[ $num =~ ^[0-9]$ ]]; then
    printf "%b" "${subscripts[num]}"
  else
    echo "Error: Input must be a single digit 0-9" >&2
    return 1
  fi
}

print_superscript() {
  local num=$1
  
  # Current implementation - Unicode Mathematical Superscripts
  local superscripts=(⁰ ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹)
  
  # Alternative 1: Enclosed/Circled Numbers (Most Readable)
  # local superscripts=(⓪ ① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨)
  
  # Alternative 2: Double Circled Numbers  
  # local superscripts=(⓿ ❶ ❷ ❸ ❹ ❺ ❻ ❼ ❽ ❾)
  
  # Alternative 3: Parenthesized Numbers (note: ⑴-⑼ are 1-9, no 0)
  # local superscripts=("⑴" "⑵" "⑶" "⑷" "⑸" "⑹" "⑺" "⑻" "⑼")  # Missing 0
  
  # Alternative 4: Superscript parentheses (combining characters)
  # local superscripts=("⁽⁰⁾" "⁽¹⁾" "⁽²⁾" "⁽³⁾" "⁽⁴⁾" "⁽⁵⁾" "⁽⁶⁾" "⁽⁷⁾" "⁽⁸⁾" "⁽⁹⁾")
  
  # Alternative 5: ASCII-style (highly readable)
  # local superscripts=("^0" "^1" "^2" "^3" "^4" "^5" "^6" "^7" "^8" "^9")
  
  # Alternative 6: Caret notation (mathematical convention)
  # local superscripts=("⁰" "¹" "²" "³" "⁴" "⁵" "⁶" "⁷" "⁸" "⁹")  # Same as current
  
  # Alternative 7: Modifier Letter Small Numbers (rare but available)
  # local superscripts=("₀" "₁" "₂" "₃" "₄" "₅" "₆" "₇" "₈" "₉")  # These are subscripts, not superscripts
  
  # Alternative 8: Full-width Circled Numbers (may be too large)
  # local superscripts=(⓪ ①② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨)  # Same as Alternative 1
  
  # Alternative 9: Negative Circled Numbers (inverted)
  # local superscripts=(🅿 ❶ ❷ ❸ ❹ ❺ ❻ ❼ ❽ ❾)  # Note: 🅿 is not 0
  
  # Alternative 10: Squared Numbers (CJK enclosed, may not display in all terminals)
  # local superscripts=(🄀 🄁 🄂 🄃 🄄 🄅 🄆 🄇 🄈 🄉)

  local index=$(( num % 10 ))
  printf "%b" "${superscripts[$index]}"
}

grepfunc() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: grepfunc <function_name> <script_file>"
    return 1
  fi

  local funcname="$1"
  local script="$2"

  rg --pcre2 -U "(^|\n)\s*(function\s+)?${funcname}\s*(\(\))?\s*\{(?:[^{}]*|(?R))*\}" "$script"
}

# Export functions for bash (zsh doesn't support export -f)
if [[ -n "$BASH_VERSION" ]]; then
    export -f edit_my_systemd_files modify_my_systemd_files edit_my_desktop_files modify_my_desktop_files 2>/dev/null || true
    export -f stopwatch devtestloop contains recipeloglink runrecipe runrecipe_exit_handler 2>/dev/null || true
    export -f nuke_domains wait_for_virsh_domstate check_required_binaries check_required_binaries_usage 2>/dev/null || true
    export -f is_wsl copy_to_clipboard exec_local_script_on_serial print_subscript print_superscript grepfunc 2>/dev/null || true
fi

# Restore original allexport behavior
if [[ $_allexport_was_set == false ]]; then
    set +a
fi
unset _allexport_was_set
