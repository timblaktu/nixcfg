# Claude Code Statusline Integration
# Implements 5 statusline styles using pkgs.writers with proper CLI tool dependencies
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.claude-code.statusline;
  writers = pkgs.writers;

  # CLI tool dependencies - leverage the rich nixcfg environment
  commonDeps = with pkgs; [
    jq # JSON parsing (required for all statuslines)
    coreutils # Basic utilities (date, basename, etc.)
    gnugrep # Pattern matching and text processing
    gnused # Stream editing
    gawk # Text processing
  ];

  gitDeps = with pkgs; [
    git # Git operations
  ] ++ commonDeps;

  hashingDeps = with pkgs; [
    coreutils # Contains sha256sum, md5sum
  ] ++ commonDeps;

  advancedDeps = with pkgs; [
    bc # Floating point calculations
    python3 # Advanced hashing and calculations
    findutils # find command for caching
  ] ++ gitDeps ++ hashingDeps;

  # Create statusline scripts using pkgs.writers
  mkStatuslineScript = { name, style, deps ? commonDeps, optimized ? false }:
    let
      scriptText =
        if style == "powerline" then powerlineScriptText
        else if style == "minimal" then minimalScriptText
        else if style == "context" then contextAwareScriptText
        else if style == "box" then boxDrawingScriptText
        else if style == "fast" then performanceOptimizedScriptText
        else throw "Unknown statusline style: ${style}";
    in
    writers.writeBashBin name ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      ${scriptText}
    '';

  # 1. Powerline Style - Segment-based with powerline separators
  powerlineScriptText = /* bash */ ''
    # Read JSON input from Claude Code
    JSON_INPUT=$(cat)
    
    # Extract account by inspecting configuration directory context
    RAW_ACCOUNT=""
    
    # Try to detect account from CLAUDE_CONFIG_DIR environment variable
    if [[ -n "''${CLAUDE_CONFIG_DIR:-}" ]]; then
      RAW_ACCOUNT=$(basename "$CLAUDE_CONFIG_DIR" | sed 's/^\.claude-//')
    fi
    
    # Fallback: inspect current working directory and parent directories for .claude-* pattern
    if [[ -z "$RAW_ACCOUNT" ]]; then
      # Look in current directory and parent directories for .claude-* directories
      DIR_TO_CHECK="$(pwd)"
      while [[ "$DIR_TO_CHECK" != "/" ]]; do
        for config_dir in "$DIR_TO_CHECK"/.claude-*; do
          if [[ -d "$config_dir" ]]; then
            RAW_ACCOUNT=$(basename "$config_dir" | sed 's/^\.claude-//')
            break 2
          fi
        done
        DIR_TO_CHECK="$(dirname "$DIR_TO_CHECK")"
      done
    fi
    
    # Final fallback
    if [[ -z "$RAW_ACCOUNT" ]]; then
      RAW_ACCOUNT="claude"
    fi
    
    # Create user-friendly account name
    if [[ "$RAW_ACCOUNT" == "max" ]]; then
      ACCOUNT="MAX"
    elif [[ "$RAW_ACCOUNT" == "pro" ]]; then
      ACCOUNT="PRO"
    elif [[ "$RAW_ACCOUNT" =~ @.*\. ]]; then
      # If it looks like an email, extract the username part
      ACCOUNT=$(echo "$RAW_ACCOUNT" | cut -d'@' -f1 | tr '[:lower:]' '[:upper:]')
    else
      ACCOUNT=$(echo "$RAW_ACCOUNT" | tr '[:lower:]' '[:upper:]')
    fi
    
    MODEL=$(echo "$JSON_INPUT" | jq -r '.model.display_name // "Claude"')
    DIR=$(echo "$JSON_INPUT" | jq -r '.workspace.current_dir // "~"')
    COST=$(echo "$JSON_INPUT" | jq -r '.cost.total_cost_usd // 0')
    
    # Generate consistent color from account name using sha256sum
    ACCT_HASH=$(echo -n "$ACCOUNT" | sha256sum | cut -c1-8)
    COLOR_NUM=$((0x''${ACCT_HASH:0:2} % 6 + 1))
    
    # Define powerline colors
    case $COLOR_NUM in
      1) ACCT_COLOR="38;5;33"  ;;  # Blue
      2) ACCT_COLOR="38;5;40"  ;;  # Green
      3) ACCT_COLOR="38;5;208" ;;  # Orange
      4) ACCT_COLOR="38;5;201" ;;  # Magenta
      5) ACCT_COLOR="38;5;226" ;;  # Yellow
      6) ACCT_COLOR="38;5;51"  ;;  # Cyan
    esac
    
    # Powerline symbols
    SEP=""
    
    # ANSI colors
    BG_ACCT="\033[48;5;''${ACCT_COLOR#*;}m"
    FG_ACCT="\033[''${ACCT_COLOR}m"
    BG_DIR="\033[48;5;238m"
    FG_DIR="\033[38;5;255m"
    BG_GIT="\033[48;5;236m"
    FG_GIT="\033[38;5;220m"
    BG_MODEL="\033[48;5;234m"
    FG_MODEL="\033[38;5;45m"
    BG_COST="\033[48;5;232m"
    FG_COST="\033[38;5;82m"
    RESET="\033[0m"
    
    # Abbreviate directory
    if [[ "$DIR" == "$HOME" ]]; then
      DIR_ABBR="~"
    elif [[ "$DIR" == "$HOME"/* ]]; then
      REL_PATH="''${DIR#$HOME/}"
      IFS='/' read -ra PARTS <<< "$REL_PATH"
      if [[ ''${#PARTS[@]} -gt 3 ]]; then
        DIR_ABBR="~/''${PARTS[0]:0:1}/…/''${PARTS[-1]}"
      else
        DIR_ABBR="~/$REL_PATH"
      fi
    else
      DIR_ABBR="''${DIR##*/}"
    fi
    
    # Git branch detection using git
    cd "$DIR" 2>/dev/null || true
    GIT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || git describe --tags --always 2>/dev/null || echo "")"
    if [[ -n "$GIT_BRANCH" ]]; then
      GIT_BRANCH="''${GIT_BRANCH:0:15}"
      # Check for dirty state
      if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
        GIT_STATUS="*"
      else
        GIT_STATUS=""
      fi
      GIT_SEGMENT="''${BG_GIT}''${FG_GIT}  ''${GIT_BRANCH}''${GIT_STATUS} ''${RESET}''${BG_MODEL}\033[38;5;236m''${SEP}''${RESET}"
    else
      GIT_SEGMENT=""
    fi
    
    # Model abbreviation using sed
    MODEL_ABBR=$(echo "$MODEL" | sed -E 's/Claude 3\.5 Sonnet/C3.5-S/; s/Claude 3 Opus/C3-O/; s/Claude 3 Haiku/C3-H/; s/Claude Opus 4\.1/C4.1-O/; s/Claude Opus 4/C4-O/; s/Claude Sonnet 4/C4-S/')
    
    # Format cost
    COST_FMT=$(printf "%.3f" "$COST")
    
    # Build statusline - make account name bold and prominent
    echo -en "''${BG_ACCT}\033[38;5;0m\033[1m ● ''${ACCOUNT} ''${RESET}''${FG_ACCT}''${BG_DIR}''${SEP}''${RESET}"
    echo -en "''${BG_DIR}''${FG_DIR}  ''${DIR_ABBR} ''${RESET}"
    [[ -n "$GIT_BRANCH" ]] && echo -en "''${BG_GIT}\033[38;5;238m''${SEP}''${RESET}''${GIT_SEGMENT}"
    echo -en "''${BG_MODEL}''${FG_MODEL} 🤖 ''${MODEL_ABBR} ''${RESET}''${BG_COST}\033[38;5;234m''${SEP}''${RESET}"
    echo -e "''${BG_COST}''${FG_COST} \$''${COST_FMT} ''${RESET}\033[38;5;232m''${SEP}''${RESET}"
  '';

  # 2. Minimal Style - Clean single-line with smart abbreviations (plain text for Claude Code compatibility)
  minimalScriptText = /* bash */ ''
    # Parse JSON input
    JSON=$(cat)
    
    # Extract account by inspecting configuration directory context
    RAW_ACCOUNT=""
    
    # Try to detect account from CLAUDE_CONFIG_DIR environment variable
    if [[ -n "''${CLAUDE_CONFIG_DIR:-}" ]]; then
      RAW_ACCOUNT=$(basename "$CLAUDE_CONFIG_DIR" | sed 's/^\.claude-//')
    fi
    
    # Fallback: inspect current working directory and parent directories for .claude-* pattern
    if [[ -z "$RAW_ACCOUNT" ]]; then
      # Look in current directory and parent directories for .claude-* directories
      DIR_TO_CHECK="$(pwd)"
      while [[ "$DIR_TO_CHECK" != "/" ]]; do
        for config_dir in "$DIR_TO_CHECK"/.claude-*; do
          if [[ -d "$config_dir" ]]; then
            RAW_ACCOUNT=$(basename "$config_dir" | sed 's/^\.claude-//')
            break 2
          fi
        done
        DIR_TO_CHECK="$(dirname "$DIR_TO_CHECK")"
      done
    fi
    
    # Final fallback
    if [[ -z "$RAW_ACCOUNT" ]]; then
      RAW_ACCOUNT="claude"
    fi
    
    # Create user-friendly account name
    if [[ "$RAW_ACCOUNT" == "max" ]]; then
      ACCOUNT="MAX"
    elif [[ "$RAW_ACCOUNT" == "pro" ]]; then
      ACCOUNT="PRO"
    elif [[ "$RAW_ACCOUNT" =~ @.*\. ]]; then
      ACCOUNT=$(echo "$RAW_ACCOUNT" | cut -d'@' -f1 | tr '[:lower:]' '[:upper:]')
    else
      ACCOUNT=$(echo "$RAW_ACCOUNT" | tr '[:lower:]' '[:upper:]')
    fi
    
    MODEL=$(echo "$JSON" | jq -r '.model.display_name // "Claude"')
    DIR=$(echo "$JSON" | jq -r '.workspace.current_dir // "~"')
    COST=$(echo "$JSON" | jq -r '.cost.total_cost_usd // 0')
    
    # Smart directory abbreviation
    DIR_BASE=$(basename "$DIR")
    if [[ "$DIR" == "$HOME" ]]; then
      DIR_DISPLAY="~"
    elif [[ "$DIR" == "$HOME"/* ]]; then
      DIR_PARENT=$(dirname "''${DIR#$HOME/}" | head -c 1)
      [[ "$DIR_PARENT" == "/" || "$DIR_PARENT" == "." ]] && DIR_DISPLAY="~/$DIR_BASE" || DIR_DISPLAY="~/$DIR_PARENT…/$DIR_BASE"
    else
      DIR_DISPLAY="/$DIR_BASE"
    fi
    
    # Git branch/worktree detection
    cd "$DIR" 2>/dev/null || true
    if git rev-parse --git-dir >/dev/null 2>&1; then
      if [[ -f .git ]]; then
        # Worktree
        BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD)
        GIT_ICON="⚡"
      else
        # Regular repo
        BRANCH=$(git branch --show-current 2>/dev/null || git describe --tags 2>/dev/null || echo "")
        GIT_ICON="⎇"
      fi
      [[ -n "$BRANCH" ]] && GIT=" | $GIT_ICON $BRANCH"
    else
      GIT=""
    fi
    
    # Model shortening
    MODEL_SHORT=$(echo "$MODEL" | sed -E 's/Claude Opus 4\.1/4.1-O/; s/Claude Opus 4/4-O/; s/Claude Sonnet 4/4-S/; s/Claude 3\.5 Sonnet/3.5-S/; s/Claude 3 Opus/3-O/; s/Claude 3 Haiku/3-H/; s/Claude //g')
    
    # Output (plain text, no ANSI colors) - make account name more prominent
    printf "● %s ❯ %s%s | %s | \$%.2f\n" \
      "$ACCOUNT" "$DIR_DISPLAY" "$GIT" "$MODEL_SHORT" "$COST"
  '';

  # 3. Context-Aware Style - Information-dense with truecolor
  contextAwareScriptText = /* bash */ ''
    # Read and parse JSON
    JSON_INPUT=$(cat)
    
    # Extract account by inspecting configuration directory context
    RAW_ACCOUNT=""
    
    # Try to detect account from CLAUDE_CONFIG_DIR environment variable
    if [[ -n "''${CLAUDE_CONFIG_DIR:-}" ]]; then
      RAW_ACCOUNT=$(basename "$CLAUDE_CONFIG_DIR" | sed 's/^\.claude-//')
    fi
    
    # Fallback: inspect current working directory and parent directories for .claude-* pattern
    if [[ -z "$RAW_ACCOUNT" ]]; then
      # Look in current directory and parent directories for .claude-* directories
      DIR_TO_CHECK="$(pwd)"
      while [[ "$DIR_TO_CHECK" != "/" ]]; do
        for config_dir in "$DIR_TO_CHECK"/.claude-*; do
          if [[ -d "$config_dir" ]]; then
            RAW_ACCOUNT=$(basename "$config_dir" | sed 's/^\.claude-//')
            break 2
          fi
        done
        DIR_TO_CHECK="$(dirname "$DIR_TO_CHECK")"
      done
    fi
    
    # Final fallback
    if [[ -z "$RAW_ACCOUNT" ]]; then
      RAW_ACCOUNT="claude"
    fi
    
    # Create user-friendly account name
    if [[ "$RAW_ACCOUNT" == "max" ]]; then
      ACCOUNT="MAX"
    elif [[ "$RAW_ACCOUNT" == "pro" ]]; then
      ACCOUNT="PRO"
    elif [[ "$RAW_ACCOUNT" =~ @.*\. ]]; then
      ACCOUNT=$(echo "$RAW_ACCOUNT" | cut -d'@' -f1 | tr '[:lower:]' '[:upper:]')
    else
      ACCOUNT=$(echo "$RAW_ACCOUNT" | tr '[:lower:]' '[:upper:]')
    fi
    
    MODEL=$(echo "$JSON_INPUT" | jq -r '.model.display_name // "Claude"')
    DIR=$(echo "$JSON_INPUT" | jq -r '.workspace.current_dir // "~"')
    COST=$(echo "$JSON_INPUT" | jq -r '.cost.total_cost_usd // 0')
    SESSION_ID=$(echo "$JSON_INPUT" | jq -r '.session_id // ""')
    DURATION=$(echo "$JSON_INPUT" | jq -r '.cost.total_duration_ms // 0')
    
    # Account color generation using SHA1
    ACCT_HASH=$(echo -n "$ACCOUNT" | sha1sum | cut -c1-6)
    HUE=$((0x''${ACCT_HASH:0:2} * 360 / 255))
    
    # Simple RGB approximation
    R=$((128 + (HUE % 128)))
    G=$((128 + ((HUE * 2) % 128)))
    B=$((128 + ((HUE * 3) % 128)))
    
    COLOR="\033[38;2;''${R};''${G};''${B}m"
    RESET='\033[0m'
    DIM='\033[2m'
    BOLD='\033[1m'
    
    # Directory with breadcrumb
    if [[ "$DIR" == "$HOME" ]]; then
      DIR_DISPLAY="~"
    elif [[ "$DIR" == "$HOME"/* ]]; then
      REL="''${DIR#$HOME/}"
      IFS='/' read -ra PARTS <<< "$REL"
      if [[ ''${#PARTS[@]} -gt 2 ]]; then
        DIR_DISPLAY="~"
        for ((i=0; i<''${#PARTS[@]}-1; i++)); do
          DIR_DISPLAY+="/''${PARTS[$i]:0:1}"
        done
        DIR_DISPLAY+="/''${PARTS[-1]}"
      else
        DIR_DISPLAY="~/$REL"
      fi
    else
      DIR_DISPLAY="''${DIR}"
    fi
    
    # Enhanced git info
    cd "$DIR" 2>/dev/null || true
    GIT_INFO=""
    if git rev-parse --git-dir >/dev/null 2>&1; then
      BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || git describe --always 2>/dev/null)
      BRANCH="''${BRANCH:0:15}"
      
      # Git stats
      STAGED=$(git diff --cached --numstat 2>/dev/null | wc -l)
      UNSTAGED=$(git diff --numstat 2>/dev/null | wc -l)
      UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
      
      GIT_STATS=""
      [[ $STAGED -gt 0 ]] && GIT_STATS+="+$STAGED"
      [[ $UNSTAGED -gt 0 ]] && GIT_STATS+="~$UNSTAGED"
      [[ $UNTRACKED -gt 0 ]] && GIT_STATS+="?$UNTRACKED"
      
      GIT_INFO=" ''${DIM}git:''${RESET}''${COLOR}$BRANCH''${RESET}"
      [[ -n "$GIT_STATS" ]] && GIT_INFO+="''${DIM}($GIT_STATS)''${RESET}"
    fi
    
    # Model emoji and shortening
    case "$MODEL" in
      *"Opus"*) MODEL_ICON="🧠" ;;
      *"Sonnet"*) MODEL_ICON="🎵" ;;
      *"Haiku"*) MODEL_ICON="⚡" ;;
      *) MODEL_ICON="🤖" ;;
    esac
    
    MODEL_SHORT=$(echo "$MODEL" | sed -E 's/Claude //; s/Opus 4\.1/O4.1/; s/Opus 4/O4/; s/Sonnet 4/S4/; s/3\.5 Sonnet/3.5S/; s/3 Opus/3O/; s/3 Haiku/3H/')
    
    # Session time formatting
    if [[ $DURATION -gt 0 ]]; then
      MINS=$((DURATION / 60000))
      SECS=$(( (DURATION % 60000) / 1000 ))
      SESSION_TIME=" ''${DIM}⏱''${RESET} ''${MINS}m''${SECS}s"
    else
      SESSION_TIME=""
    fi
    
    # Build statusline
    echo -en "''${BOLD}''${COLOR}▶ $ACCOUNT''${RESET} "
    echo -en "''${DIM}│''${RESET} 📂 $DIR_DISPLAY$GIT_INFO "
    echo -en "''${DIM}│''${RESET} $MODEL_ICON $MODEL_SHORT "
    echo -en "''${DIM}│''${RESET} ''${COLOR}\$''${RESET}$(printf "%.2f" "$COST")"
    echo -e "$SESSION_TIME"
  '';

  # 4. Box Drawing Style - Multi-line with Unicode box characters
  boxDrawingScriptText = /* bash */ ''
    # Parse JSON
    JSON=$(cat)
    ACCOUNT=$(echo "$JSON" | jq -r '.account // "user"')
    MODEL=$(echo "$JSON" | jq -r '.model.display_name // "Claude"')
    DIR=$(echo "$JSON" | jq -r '.workspace.current_dir // "~"')
    COST=$(echo "$JSON" | jq -r '.cost.total_cost_usd // 0')
    LINES_ADDED=$(echo "$JSON" | jq -r '.cost.total_lines_added // 0')
    LINES_REMOVED=$(echo "$JSON" | jq -r '.cost.total_lines_removed // 0')
    
    # Account color from checksum (using cksum as fallback to python3)
    if command -v python3 >/dev/null 2>&1; then
      COLOR_CODE=$(python3 -c "import binascii; print(binascii.crc32(b'$ACCOUNT') % 6 + 31)")
    else
      COLOR_CODE=$(($(echo -n "$ACCOUNT" | cksum | cut -d' ' -f1) % 6 + 31))
    fi
    
    COLOR="\033[1;''${COLOR_CODE}m"
    RESET='\033[0m'
    DIM='\033[2m'
    BOLD='\033[1m'
    
    # Directory
    DIR_NAME=$(basename "$DIR")
    DIR_PARENT=$(dirname "$DIR")
    [[ "$DIR_PARENT" == "$HOME" ]] && DIR_PARENT="~"
    [[ "$DIR_PARENT" == "/" ]] && DIR_PARENT=""
    
    # Git info with ahead/behind indicators
    cd "$DIR" 2>/dev/null || true
    GIT_LINE=""
    if git rev-parse --git-dir >/dev/null 2>&1; then
      BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
      REMOTE=$(git config --get "branch.$BRANCH.remote" 2>/dev/null || echo "")
      AHEAD_BEHIND=""
      
      if [[ -n "$REMOTE" ]] && [[ "$BRANCH" != "detached" ]]; then
        AHEAD=$(git rev-list --count HEAD..."$REMOTE/$BRANCH" 2>/dev/null || echo 0)
        BEHIND=$(git rev-list --count "$REMOTE/$BRANCH"...HEAD 2>/dev/null || echo 0)
        [[ $AHEAD -gt 0 ]] && AHEAD_BEHIND+=" ↑$AHEAD"
        [[ $BEHIND -gt 0 ]] && AHEAD_BEHIND+=" ↓$BEHIND"
      fi
      
      GIT_LINE="''${DIM}├─''${RESET} ''${COLOR}⎇''${RESET} $BRANCH$AHEAD_BEHIND"
    fi
    
    # Model display
    MODEL_DISPLAY=$(echo "$MODEL" | sed -E 's/Claude //; s/Opus 4\.1/Opus-4.1/; s/Opus 4/Opus-4/; s/Sonnet 4/Sonnet-4/')
    
    # Format cost with color using bc
    COST_COLOR=""
    if command -v bc >/dev/null 2>&1; then
      if (( $(echo "$COST > 1" | bc -l) )); then
        COST_COLOR="\033[38;5;196m"  # Red for high cost
      elif (( $(echo "$COST > 0.5" | bc -l) )); then
        COST_COLOR="\033[38;5;214m"  # Orange for medium
      else
        COST_COLOR="\033[38;5;82m"   # Green for low
      fi
    else
      # Fallback without bc
      COST_COLOR="\033[38;5;82m"   # Default green
    fi
    
    # Lines changed
    LINES_INFO=""
    if [[ $LINES_ADDED -gt 0 ]] || [[ $LINES_REMOVED -gt 0 ]]; then
      LINES_INFO=" ''${DIM}(+''${LINES_ADDED}/-''${LINES_REMOVED})''${RESET}"
    fi
    
    # Build multi-line display
    echo -e "''${DIM}╭──''${RESET} ''${BOLD}''${COLOR}$ACCOUNT''${RESET} ''${DIM}──────────────╮''${RESET}"
    echo -e "''${DIM}├─''${RESET} 📍 ''${DIR_PARENT:+$DIR_PARENT/}''${BOLD}$DIR_NAME''${RESET}"
    [[ -n "$GIT_LINE" ]] && echo -e "$GIT_LINE"
    echo -e "''${DIM}├─''${RESET} 🤖 $MODEL_DISPLAY"
    echo -e "''${DIM}╰─''${RESET} ''${COST_COLOR}\$$(printf "%.3f" "$COST")''${RESET}$LINES_INFO ''${DIM}──────────────╯''${RESET}"
  '';

  # 5. Performance-Optimized Style - Fast with caching
  performanceOptimizedScriptText = /* bash */ ''
    # Cache directory for expensive operations
    CACHE_DIR="/tmp/claude-statusline-cache"
    mkdir -p "$CACHE_DIR"
    
    # Read JSON once
    JSON=$(cat)
    ACCOUNT=$(echo "$JSON" | jq -r '.account // "user"')
    MODEL=$(echo "$JSON" | jq -r '.model.display_name // "Claude"')
    DIR=$(echo "$JSON" | jq -r '.workspace.current_dir // "~"')
    COST=$(echo "$JSON" | jq -r '.cost.total_cost_usd // 0')
    
    # Fast hash-based color (no external commands)
    HASH=0
    for ((i=0; i<''${#ACCOUNT}; i++)); do
      HASH=$(( (HASH * 31 + $(printf "%d" "'''${ACCOUNT:$i:1}")) % 256 ))
    done
    COLOR_INDEX=$((HASH % 6))
    
    # Pre-computed ANSI colors
    COLORS=('\033[38;5;39m' '\033[38;5;42m' '\033[38;5;208m' '\033[38;5;201m' '\033[38;5;226m' '\033[38;5;51m')
    COLOR="''${COLORS[$COLOR_INDEX]}"
    RESET='\033[0m'
    
    # Fast directory abbreviation (no subshells)
    case "$DIR" in
      "$HOME") DIR_DISPLAY="~" ;;
      "$HOME"/*) 
        REL="''${DIR#$HOME/}"
        DIR_DISPLAY="~/''${REL##*/}"
        ;;
      *) DIR_DISPLAY="''${DIR##*/}" ;;
    esac
    
    # Cached git info (updates every 5 seconds)
    GIT_CACHE="$CACHE_DIR/git-$(echo -n "$DIR" | md5sum | cut -c1-8)"
    GIT_INFO=""
    
    if [[ ! -f "$GIT_CACHE" ]] || [[ $(find "$GIT_CACHE" -mmin +0.083 2>/dev/null) ]]; then
      # Update cache
      if cd "$DIR" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
        BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "HEAD")
        echo "$BRANCH" > "$GIT_CACHE"
        GIT_INFO=" | $BRANCH"
      else
        echo "" > "$GIT_CACHE"
      fi
    elif [[ -s "$GIT_CACHE" ]]; then
      # Use cache
      GIT_INFO=" | $(cat "$GIT_CACHE")"
    fi
    
    # Model abbreviation (optimized)
    case "$MODEL" in
      *"Opus 4.1"*) M="O4.1" ;;
      *"Opus 4"*) M="O4" ;;
      *"Sonnet 4"*) M="S4" ;;
      *"3.5 Sonnet"*) M="3.5S" ;;
      *"3 Opus"*) M="3O" ;;
      *"3 Haiku"*) M="3H" ;;
      *) M="''${MODEL:0:8}" ;;
    esac
    
    # Single printf for output (fastest)
    printf "''${COLOR}%s''${RESET} › %s%s | %s | \$%.2f\n" "$ACCOUNT" "$DIR_DISPLAY" "$GIT_INFO" "$M" "$COST"
  '';

  # Available statusline scripts
  statuslineScripts = {
    claude-statusline-powerline = mkStatuslineScript {
      name = "claude-statusline-powerline";
      style = "powerline";
      deps = gitDeps ++ hashingDeps;
    };

    claude-statusline-minimal = mkStatuslineScript {
      name = "claude-statusline-minimal";
      style = "minimal";
      deps = gitDeps ++ hashingDeps;
    };

    claude-statusline-context = mkStatuslineScript {
      name = "claude-statusline-context";
      style = "context";
      deps = gitDeps ++ hashingDeps;
    };

    claude-statusline-box = mkStatuslineScript {
      name = "claude-statusline-box";
      style = "box";
      deps = advancedDeps;
    };

    claude-statusline-fast = mkStatuslineScript {
      name = "claude-statusline-fast";
      style = "fast";
      deps = gitDeps ++ hashingDeps;
      optimized = true;
    };
  };

in
{
  options.programs.claude-code.statusline = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Claude Code statusline integration with multiple styles";
    };

    style = mkOption {
      type = types.enum [ "powerline" "minimal" "context" "box" "fast" ];
      default = "minimal";
      description = ''
        Statusline style to use:
        - powerline: Segment-based with powerline separators and colors
        - minimal: Clean single-line with smart abbreviations  
        - context: Information-dense with context tracking
        - box: Multi-line display with Unicode box drawing
        - fast: Performance-optimized with caching
      '';
    };

    enableAllStyles = mkOption {
      type = types.bool;
      default = false;
      description = "Install all statusline styles for testing and switching";
    };

    testMode = mkOption {
      type = types.bool;
      default = false;
      description = "Enable test mode with mock JSON data generation";
    };
  };

  # Add statusline configuration to the internal settings system
  options.programs.claude-code._internal.statuslineSettings = mkOption {
    type = types.attrs;
    internal = true;
    default = { };
  };

  config = mkIf cfg.enable {
    # Configure Claude Code statusline through the internal settings system
    # Use stable command name instead of absolute paths to avoid breakage on rebuilds
    programs.claude-code._internal.statuslineSettings = {
      statusLine = {
        type = "command";
        command = "claude-statusline-${cfg.style}";
        padding = 0;
      };
    };

    # Install the selected statusline script and test scripts
    home.packages = [
      statuslineScripts."claude-statusline-${cfg.style}"
    ] ++ optionals cfg.enableAllStyles (attrValues statuslineScripts)
    ++ optionals cfg.testMode [
      (writers.writeBashBin "test-claude-statusline" ''
        #!/usr/bin/env bash
        # Test Claude Code statusline with mock data
        
        echo "Testing Claude Code statusline styles..."
        echo
        
        # Generate mock JSON data
        MOCK_JSON='{
          "hook_event_name": "Status",
          "session_id": "test-session-123",
          "account": "test@example.com",
          "model": {
            "id": "claude-opus-4-1",
            "display_name": "Claude Opus 4.1"
          },
          "workspace": {
            "current_dir": "'$(pwd)'",
            "project_dir": "'$(pwd)'"
          },
          "version": "1.0.80",
          "cost": {
            "total_cost_usd": 0.42,
            "total_duration_ms": 45000,
            "total_lines_added": 156,
            "total_lines_removed": 23
          }
        }'
        
        # Test selected style
        echo "=== Current Style: ${cfg.style} ==="
        echo "$MOCK_JSON" | claude-statusline-${cfg.style}
        echo
        
        ${optionalString cfg.enableAllStyles ''
        # Test all styles if enabled
        for style in powerline minimal context box fast; do
          if [[ "$style" != "${cfg.style}" ]]; then
            echo "=== Style: $style ==="
            echo "$MOCK_JSON" | claude-statusline-$style
            echo
          fi
        done
        ''}
        
        echo "Testing complete! Configure your Claude Code settings.json with:"
        echo "{" 
        echo '  "statusLine": {'
        echo '    "type": "command",'
        echo '    "command": "'${statuslineScripts."claude-statusline-${cfg.style}"}/bin/claude-statusline-${cfg.style}'",'
        echo '    "padding": 0'
        echo '  }'
        echo "}"
      '')
    ];
  };
}
