# Claude Code Statusline Complete Documentation

## Overview

Claude Code's statusline feature allows you to create custom status lines that display at the bottom of the Claude Code interface, similar to terminal prompts (PS1) in shells like Oh-my-zsh. The statusline receives contextual JSON data via stdin and outputs formatted text to stdout.

## Configuration

Add to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-powerline.sh",
    "padding": 0
  }
}
```

## JSON Input Structure

Your statusline script receives this JSON structure via stdin:

```json
{
  "hook_event_name": "Status",
  "session_id": "abc123-def456-ghi789",
  "transcript_path": "/path/to/transcript.json",
  "cwd": "/current/working/directory",
  "account": "user@example.com",
  "model": {
    "id": "claude-opus-4-1",
    "display_name": "Claude Opus 4.1"
  },
  "workspace": {
    "current_dir": "/current/working/directory",
    "project_dir": "/original/project/directory"
  },
  "version": "1.0.80",
  "output_style": {
    "name": "default"
  },
  "cost": {
    "total_cost_usd": 0.01234,
    "total_duration_ms": 45000,
    "total_api_duration_ms": 2300,
    "total_lines_added": 156,
    "total_lines_removed": 23
  }
}
```

### Field Descriptions

- **hook_event_name**: Always "Status" for statusline updates
- **session_id**: Unique identifier for the current Claude Code session
- **transcript_path**: Path to the conversation transcript JSON file
- **cwd**: Current working directory (deprecated, use workspace.current_dir)
- **account**: User account identifier (may not always be present)
- **model.id**: Model identifier (e.g., "claude-opus-4-1", "claude-3-5-sonnet")
- **model.display_name**: Human-readable model name
- **workspace.current_dir**: Current working directory
- **workspace.project_dir**: Original project directory when session started
- **version**: Claude Code version
- **output_style.name**: Current output style setting
- **cost.total_cost_usd**: Total cost in USD for the session
- **cost.total_duration_ms**: Total session duration in milliseconds
- **cost.total_api_duration_ms**: Total API call duration
- **cost.total_lines_added**: Total lines added in session
- **cost.total_lines_removed**: Total lines removed in session

## Environment Variables

While the statusline primarily uses JSON input, these environment variables may be available in the Claude Code context:

- `ANTHROPIC_API_KEY`: API key for Claude Code
- `CLAUDE_ACCOUNT`: Account identifier (when available)
- `CLAUDE_MODEL_DISPLAY`: Current model display name
- `CLAUDE_TOTAL_COST_USD`: Session cost in USD
- `CLAUDE_SESSION_ID`: Current session identifier

## Statusline Scripts

### 1. Powerline Style

**Description**: Segment-based statusline with powerline separators, colored backgrounds, and comprehensive git status. Account name gets consistent color throughout.

```bash
#!/bin/bash
# ~/.claude/statusline-powerline.sh
set -euo pipefail

# Read JSON input from Claude Code
JSON_INPUT=$(cat)

# Parse JSON data with jq
ACCOUNT=$(echo "$JSON_INPUT" | jq -r '.account // "default"')
MODEL=$(echo "$JSON_INPUT" | jq -r '.model.display_name // "Claude"')
DIR=$(echo "$JSON_INPUT" | jq -r '.workspace.current_dir // "~"')
COST=$(echo "$JSON_INPUT" | jq -r '.cost.total_cost_usd // 0')

# Generate consistent color from account name
ACCT_HASH=$(echo -n "$ACCOUNT" | sha256sum | cut -c1-8)
COLOR_NUM=$((0x${ACCT_HASH:0:2} % 6 + 1))

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
SEP_THIN=""

# ANSI colors
BG_ACCT="\033[48;5;${ACCT_COLOR#*;}m"
FG_ACCT="\033[${ACCT_COLOR}m"
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
  REL_PATH="${DIR#$HOME/}"
  IFS='/' read -ra PARTS <<< "$REL_PATH"
  if [[ ${#PARTS[@]} -gt 3 ]]; then
    DIR_ABBR="~/${PARTS[0]:0:1}/…/${PARTS[-1]}"
  else
    DIR_ABBR="~/$REL_PATH"
  fi
else
  DIR_ABBR="${DIR##*/}"
fi

# Git branch detection
cd "$DIR" 2>/dev/null || true
GIT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || git describe --tags --always 2>/dev/null || echo "")
if [[ -n "$GIT_BRANCH" ]]; then
  GIT_BRANCH="${GIT_BRANCH:0:15}"
  # Check for dirty state
  if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
    GIT_STATUS="*"
  else
    GIT_STATUS=""
  fi
  GIT_SEGMENT="${BG_GIT}${FG_GIT}  ${GIT_BRANCH}${GIT_STATUS} ${RESET}${BG_MODEL}\033[38;5;236m${SEP}${RESET}"
else
  GIT_SEGMENT=""
fi

# Model abbreviation
MODEL_ABBR=$(echo "$MODEL" | sed -E 's/Claude 3\.5 Sonnet/C3.5-S/; s/Claude 3 Opus/C3-O/; s/Claude 3 Haiku/C3-H/; s/Claude Opus 4\.1/C4.1-O/; s/Claude Opus 4/C4-O/; s/Claude Sonnet 4/C4-S/')

# Format cost
COST_FMT=$(printf "%.3f" "$COST")

# Build statusline
echo -en "${BG_ACCT}\033[38;5;0m ⚡ ${ACCOUNT} ${RESET}${FG_ACCT}${BG_DIR}${SEP}${RESET}"
echo -en "${BG_DIR}${FG_DIR}  ${DIR_ABBR} ${RESET}"
[[ -n "$GIT_BRANCH" ]] && echo -en "${BG_GIT}\033[38;5;238m${SEP}${RESET}${GIT_SEGMENT}"
echo -en "${BG_MODEL}${FG_MODEL} 🤖 ${MODEL_ABBR} ${RESET}${BG_COST}\033[38;5;234m${SEP}${RESET}"
echo -e "${BG_COST}${FG_COST} \$${COST_FMT} ${RESET}\033[38;5;232m${SEP}${RESET}"
```

### 2. Minimalist Style

**Description**: Clean single-line format with smart abbreviations and subtle styling. Uses MD5 hash for consistent account colors.

```bash
#!/bin/bash
# ~/.claude/statusline-minimal.sh
set -euo pipefail

# Parse JSON input
JSON=$(cat)
ACCOUNT=$(echo "$JSON" | jq -r '.account // "user"')
MODEL=$(echo "$JSON" | jq -r '.model.display_name // "Claude"')
DIR=$(echo "$JSON" | jq -r '.workspace.current_dir // "~"')
COST=$(echo "$JSON" | jq -r '.cost.total_cost_usd // 0')

# Generate account color
HASH=$(echo -n "$ACCOUNT" | md5sum | cut -c1-2)
case $(printf "%d" "0x$HASH") in
  [0-42]*)  COLOR='\033[38;5;75m'  ;;  # Sky blue
  [43-85]*) COLOR='\033[38;5;114m' ;;  # Green
  [86-128]*) COLOR='\033[38;5;215m' ;; # Peach
  [129-170]*) COLOR='\033[38;5;183m' ;; # Purple
  [171-213]*) COLOR='\033[38;5;220m' ;; # Gold
  *) COLOR='\033[38;5;87m' ;;          # Cyan
esac

RESET='\033[0m'
DIM='\033[2m'

# Smart directory abbreviation
DIR_BASE=$(basename "$DIR")
if [[ "$DIR" == "$HOME" ]]; then
  DIR_DISPLAY="~"
elif [[ "$DIR" == "$HOME"/* ]]; then
  DIR_PARENT=$(dirname "${DIR#$HOME/}" | head -c 1)
  [[ "$DIR_PARENT" == "/" || "$DIR_PARENT" == "." ]] && DIR_DISPLAY="~/$DIR_BASE" || DIR_DISPLAY="~/$DIR_PARENT…/$DIR_BASE"
else
  DIR_DISPLAY="/$DIR_BASE"
fi

# Git branch/worktree
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
  [[ -n "$BRANCH" ]] && GIT=" ${DIM}│${RESET} ${COLOR}${GIT_ICON}${RESET} ${BRANCH:0:12}"
else
  GIT=""
fi

# Model shortening
MODEL_SHORT=$(echo "$MODEL" | sed -E 's/Claude Opus 4\.1/4.1-O/; s/Claude Opus 4/4-O/; s/Claude Sonnet 4/4-S/; s/Claude 3\.5 Sonnet/3.5-S/; s/Claude 3 Opus/3-O/; s/Claude 3 Haiku/3-H/; s/Claude //g')

# Output
printf "${COLOR}◉ %s${RESET} ${DIM}❯${RESET} %s%s ${DIM}│${RESET} %s ${DIM}│${RESET} ${COLOR}\$${RESET}%.2f\n" \
  "$ACCOUNT" "$DIR_DISPLAY" "$GIT" "$MODEL_SHORT" "$COST"
```

### 3. Context-Aware Style

**Description**: Information-dense display with context usage tracking, git statistics, and truecolor support using HSL color generation.

```bash
#!/bin/bash
# ~/.claude/statusline-context.sh
set -euo pipefail

# Read and parse JSON
JSON_INPUT=$(cat)
ACCOUNT=$(echo "$JSON_INPUT" | jq -r '.account // "user"')
MODEL=$(echo "$JSON_INPUT" | jq -r '.model.display_name // "Claude"')
DIR=$(echo "$JSON_INPUT" | jq -r '.workspace.current_dir // "~"')
COST=$(echo "$JSON_INPUT" | jq -r '.cost.total_cost_usd // 0')
SESSION_ID=$(echo "$JSON_INPUT" | jq -r '.session_id // ""')
DURATION=$(echo "$JSON_INPUT" | jq -r '.cost.total_duration_ms // 0')

# Model-specific context limits
case "$MODEL" in
  *"Opus 4.1"*) CONTEXT_LIMIT=200000 ;;
  *"Opus 4"*) CONTEXT_LIMIT=200000 ;;
  *"Sonnet 4"*) CONTEXT_LIMIT=200000 ;;
  *"3.5 Sonnet"*) CONTEXT_LIMIT=200000 ;;
  *"3 Opus"*) CONTEXT_LIMIT=200000 ;;
  *"3 Haiku"*) CONTEXT_LIMIT=200000 ;;
  *) CONTEXT_LIMIT=200000 ;;
esac

# Account color generation using SHA
ACCT_HASH=$(echo -n "$ACCOUNT" | sha1sum | cut -c1-6)
HUE=$((0x${ACCT_HASH:0:2} * 360 / 255))

# Simple RGB approximation
R=$((128 + (HUE % 128)))
G=$((128 + ((HUE * 2) % 128)))
B=$((128 + ((HUE * 3) % 128)))

COLOR="\033[38;2;${R};${G};${B}m"
RESET='\033[0m'
DIM='\033[2m'
BOLD='\033[1m'

# Directory with breadcrumb
if [[ "$DIR" == "$HOME" ]]; then
  DIR_DISPLAY="~"
elif [[ "$DIR" == "$HOME"/* ]]; then
  REL="${DIR#$HOME/}"
  IFS='/' read -ra PARTS <<< "$REL"
  if [[ ${#PARTS[@]} -gt 2 ]]; then
    DIR_DISPLAY="~"
    for ((i=0; i<${#PARTS[@]}-1; i++)); do
      DIR_DISPLAY+="/${PARTS[$i]:0:1}"
    done
    DIR_DISPLAY+="/${PARTS[-1]}"
  else
    DIR_DISPLAY="~/$REL"
  fi
else
  DIR_DISPLAY="${DIR}"
fi

# Enhanced git info
cd "$DIR" 2>/dev/null || true
GIT_INFO=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || git describe --always 2>/dev/null)
  BRANCH="${BRANCH:0:15}"
  
  # Git stats
  STAGED=$(git diff --cached --numstat 2>/dev/null | wc -l)
  UNSTAGED=$(git diff --numstat 2>/dev/null | wc -l)
  UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
  
  GIT_STATS=""
  [[ $STAGED -gt 0 ]] && GIT_STATS+="+$STAGED"
  [[ $UNSTAGED -gt 0 ]] && GIT_STATS+="~$UNSTAGED"
  [[ $UNTRACKED -gt 0 ]] && GIT_STATS+="?$UNTRACKED"
  
  GIT_INFO=" ${DIM}git:${RESET}${COLOR}$BRANCH${RESET}"
  [[ -n "$GIT_STATS" ]] && GIT_INFO+="${DIM}($GIT_STATS)${RESET}"
fi

# Model emoji
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
  SESSION_TIME=" ${DIM}⏱${RESET} ${MINS}m${SECS}s"
else
  SESSION_TIME=""
fi

# Build statusline
echo -en "${BOLD}${COLOR}▶ $ACCOUNT${RESET} "
echo -en "${DIM}│${RESET} 📂 $DIR_DISPLAY$GIT_INFO "
echo -en "${DIM}│${RESET} $MODEL_ICON $MODEL_SHORT "
echo -en "${DIM}│${RESET} ${COLOR}\$${RESET}$(printf "%.2f" "$COST")"
echo -e "$SESSION_TIME"
```

### 4. Box Drawing Style

**Description**: Multi-line display with Unicode box drawing characters, git ahead/behind indicators, and cost-based coloring.

```bash
#!/bin/bash
# ~/.claude/statusline-box.sh
set -euo pipefail

# Parse JSON
JSON=$(cat)
ACCOUNT=$(echo "$JSON" | jq -r '.account // "user"')
MODEL=$(echo "$JSON" | jq -r '.model.display_name // "Claude"')
DIR=$(echo "$JSON" | jq -r '.workspace.current_dir // "~"')
COST=$(echo "$JSON" | jq -r '.cost.total_cost_usd // 0')
LINES_ADDED=$(echo "$JSON" | jq -r '.cost.total_lines_added // 0')
LINES_REMOVED=$(echo "$JSON" | jq -r '.cost.total_lines_removed // 0')

# Account color from CRC32
if command -v python3 >/dev/null 2>&1; then
  COLOR_CODE=$(python3 -c "import binascii; print(binascii.crc32(b'$ACCOUNT') % 6 + 31)")
else
  COLOR_CODE=$(($(echo -n "$ACCOUNT" | cksum | cut -d' ' -f1) % 6 + 31))
fi

COLOR="\033[1;${COLOR_CODE}m"
RESET='\033[0m'
DIM='\033[2m'
BOLD='\033[1m'

# Directory
DIR_NAME=$(basename "$DIR")
DIR_PARENT=$(dirname "$DIR")
[[ "$DIR_PARENT" == "$HOME" ]] && DIR_PARENT="~"
[[ "$DIR_PARENT" == "/" ]] && DIR_PARENT=""

# Git info
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
  
  GIT_LINE="${DIM}├─${RESET} ${COLOR}⎇${RESET} $BRANCH$AHEAD_BEHIND"
fi

# Model display
MODEL_DISPLAY=$(echo "$MODEL" | sed -E 's/Claude //; s/Opus 4\.1/Opus-4.1/; s/Opus 4/Opus-4/; s/Sonnet 4/Sonnet-4/')

# Format cost with color
COST_COLOR=""
if (( $(echo "$COST > 1" | bc -l) )); then
  COST_COLOR="\033[38;5;196m"  # Red for high cost
elif (( $(echo "$COST > 0.5" | bc -l) )); then
  COST_COLOR="\033[38;5;214m"  # Orange for medium
else
  COST_COLOR="\033[38;5;82m"   # Green for low
fi

# Lines changed
LINES_INFO=""
if [[ $LINES_ADDED -gt 0 ]] || [[ $LINES_REMOVED -gt 0 ]]; then
  LINES_INFO=" ${DIM}(+${LINES_ADDED}/-${LINES_REMOVED})${RESET}"
fi

# Build multi-line display
echo -e "${DIM}╭──${RESET} ${BOLD}${COLOR}$ACCOUNT${RESET} ${DIM}──────────────╮${RESET}"
echo -e "${DIM}├─${RESET} 📍 ${DIR_PARENT:+$DIR_PARENT/}${BOLD}$DIR_NAME${RESET}"
[[ -n "$GIT_LINE" ]] && echo -e "$GIT_LINE"
echo -e "${DIM}├─${RESET} 🤖 $MODEL_DISPLAY"
echo -e "${DIM}╰─${RESET} ${COST_COLOR}\$$(printf "%.3f" "$COST")${RESET}$LINES_INFO ${DIM}──────────────╯${RESET}"
```

### 5. Performance-Optimized Style

**Description**: Fast statusline with 5-second git caching, minimal subshells, and optimized string operations.

```bash
#!/bin/bash
# ~/.claude/statusline-fast.sh
set -euo pipefail

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
for ((i=0; i<${#ACCOUNT}; i++)); do
  HASH=$(( (HASH * 31 + $(printf "%d" "'${ACCOUNT:$i:1}")) % 256 ))
done
COLOR_INDEX=$((HASH % 6))

# Pre-computed ANSI colors
COLORS=('\033[38;5;39m' '\033[38;5;42m' '\033[38;5;208m' '\033[38;5;201m' '\033[38;5;226m' '\033[38;5;51m')
COLOR="${COLORS[$COLOR_INDEX]}"
RESET='\033[0m'

# Fast directory abbreviation (no subshells)
case "$DIR" in
  "$HOME") DIR_DISPLAY="~" ;;
  "$HOME"/*) 
    REL="${DIR#$HOME/}"
    DIR_DISPLAY="~/${REL##*/}"
    ;;
  *) DIR_DISPLAY="${DIR##*/}" ;;
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
  *) M="${MODEL:0:8}" ;;
esac

# Single printf for output (fastest)
printf "${COLOR}%s${RESET} › %s%s | %s | \$%.2f\n" "$ACCOUNT" "$DIR_DISPLAY" "$GIT_INFO" "$M" "$COST"
```

## Installation

1. Save your chosen script(s) to `~/.claude/` directory
2. Make them executable: `chmod +x ~/.claude/statusline-*.sh`
3. Update your `~/.claude/settings.json` to point to your chosen script
4. Restart Claude Code to see your new statusline

## Testing

Test any statusline manually with mock data:

```bash
echo '{
  "account": "test@example.com",
  "model": {"display_name": "Claude Opus 4.1"},
  "workspace": {"current_dir": "/home/user/projects/myapp"},
  "cost": {"total_cost_usd": 0.42}
}' | ~/.claude/statusline-minimal.sh
```

## Tips

- Keep statuslines concise - they should fit on one line (except box style)
- Use emojis and colors to make information scannable
- Cache expensive operations like git status
- Test scripts before deploying to avoid Claude Code issues
- Ensure scripts output to stdout, not stderr
- Scripts should complete quickly (<300ms) to avoid delays

## Model Abbreviations

Common model name mappings used in scripts:

- `Claude Opus 4.1` → `O4.1` or `C4.1-O`
- `Claude Opus 4` → `O4` or `C4-O`
- `Claude Sonnet 4` → `S4` or `C4-S`
- `Claude 3.5 Sonnet` → `3.5S` or `C3.5-S`
- `Claude 3 Opus` → `3O` or `C3-O`
- `Claude 3 Haiku` → `3H` or `C3-H`

## Requirements

- **jq**: JSON parsing (required for all scripts)
- **git**: Git branch/status detection (optional)
- **bash**: Shell scripting environment
- **bc**: Floating point calculations (optional, for some scripts)
- **python3**: CRC32 hashing (optional, falls back to cksum)

## Troubleshooting

1. **Statusline not appearing**: Check script is executable (`chmod +x`)
2. **Parse errors**: Validate JSON in settings.json
3. **Git info missing**: Ensure you're in a git repository
4. **Colors not working**: Check terminal supports ANSI colors
5. **Performance issues**: Use the fast/cached version or reduce git operations