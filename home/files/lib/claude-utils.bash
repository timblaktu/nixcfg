# Wrapper functions for invoking headless claude-code as a CLI tool

clc_get_commit_message() {
  local model=sonnet
  local LET_CLAUDE_FIGURE_OUT_THE_DIFF=true  # seems to do a better job when in a known project dir
  local prompt='WITHOUT OUTPUTTING ANY OTHER CHARACTERS, Generate ONLY a conventional commit message string for the complete set of changes in a git repo, including both tracked and untracked files, as specified below. Your output MUST BE A VALID JSON STRING WITHOUT DOUBLE-QUOTES, i.e. ALL LINE BREAKS MUST BE ENCODED USING THE \\n ESCAPE CHARACTER.\n\n'
  if [ -v LET_CLAUDE_FIGURE_OUT_THE_DIFF ]; then
    prompt+="You are expected to analyze the git repo in PWD yourself."
  else
    prompt+="$( (PS4='+ '; set -x; git status --short ) 2>&1)\n\n$( (PS4='+ '; set -x; git --no-pager diff) 2>&1)"
  fi

  # printf "sending claude the prompt:\n%b\n\n" "$(echo "$prompt" | sed 's/^/    /')" >&2
  local r="$(claudepro --model $model -p "$prompt" --output-format json)"
  # printf "received response:\n%b\n\n" "$(echo $r | sed 's/^/    /')" >&2
  local just_the_json="{${r#*\{}"; r="${r%\}*}}"
  # printf "just_the_json:\n%b\n\n" "$(echo $just_the_json | sed 's/^/    /')" >&2
  
  echo "$just_the_json" | jq -r '.result'
}

# Export functions for bash (zsh doesn't support (or require) export -f)
if [[ -n "$BASH_VERSION" ]]; then
    export -f clc_get_commit_message 2>/dev/null || true
fi

