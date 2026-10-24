# Account-agnostic Claude Code memory sharing (plan 064).
#
# Claude Code's file-based memory lives at $CLAUDE_CONFIG_DIR/projects/<key>/memory/,
# where <key> is the git-common-dir (main-worktree) path with '/' -> '-'. Because each
# account wrapper sets a different CLAUDE_CONFIG_DIR (.claude-<name>/), that store is
# otherwise PRIVATE per account and lost on an account switch. Memory is repo knowledge,
# not account knowledge, so we fold every account's projects/<key>/memory into one
# canonical store at <runtime>/shared-memory/<key>/ and symlink each account to it.
#
# This file is SOURCED (by the account wrapper's setup_environment, and by the plan-064
# behavioural test). It only DEFINES functions - it must not execute anything on source.
# Everything is best-effort and non-fatal: any failure is a silent no-op so a launch is
# never aborted (memory just stays per-account for that launch).
#
# Transcripts/todos stay per-account (cwd-keyed, credential-bound); only memory is shared.

# True iff "$1" is a directory containing at least one entry.
_cc_dir_nonempty() {
  local dir="$1" f
  [ -d "$dir" ] || return 1
  for f in "$dir"/* "$dir"/.*; do
    case "$f" in
      */. | */..) continue ;;
    esac
    [ -e "$f" ] && return 0
  done
  return 1
}

# Resolve the memory key for the current working directory the way Claude Code does:
# git-common-dir (main worktree) -> parent -> path with '/' replaced by '-'. Falls back
# to $PWD when not in a git repo. Prints the key, or nothing on failure.
_cc_memory_key() {
  local root
  if root=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    root=$(dirname -- "$root")
  else
    root=$(pwd -P 2>/dev/null) || root="$PWD"
  fi
  [ -n "$root" ] || return 1
  printf '%s' "${root//\//-}"
}

# Warn (stderr) about an unresolved multi-store conflict; never merges.
_cc_share_warn() {
  local key="$1" shared="$2"
  shift 2
  {
    printf 'claude: shared-memory: multiple non-empty memory stores for key "%s"; NOT merging.\n' "$key"
    printf 'claude: conflicting paths:\n'
    local p
    for p in "$@"; do printf 'claude:   %s\n' "$p"; done
    printf 'claude: resolve manually (merge into %s) then relaunch.\n' "$shared"
  } >&2
}

# Consolidate + symlink all accounts' memory for one explicit key. Separated from key
# resolution so the test can drive it deterministically without a git fixture.
#   $1 = runtime path (dir holding .claude-<name>/ and shared-memory/)
#   $2 = memory key
_cc_share_memory_for_key() {
  local runtime="$1" key="$2"
  [ -n "$runtime" ] && [ -n "$key" ] || return 0

  local shared="$runtime/shared-memory/$key"

  # Classify real (non-symlink) non-empty per-account memory dirs for this key.
  local d nonempty=()
  for d in "$runtime"/.claude-*/projects/"$key"/memory; do
    [ -e "$d" ] || continue
    if [ -d "$d" ] && [ ! -L "$d" ] && _cc_dir_nonempty "$d"; then
      nonempty+=("$d")
    fi
  done

  local shared_has=0
  if [ -d "$shared" ] && _cc_dir_nonempty "$shared"; then
    shared_has=1
  fi

  # Conflict cases: never auto-merge. Surface and bail, leaving per-account state intact.
  if [ "${#nonempty[@]}" -gt 1 ]; then
    _cc_share_warn "$key" "$shared" "${nonempty[@]}"
    return 0
  fi
  if [ "${#nonempty[@]}" -eq 1 ] && [ "$shared_has" -eq 1 ]; then
    _cc_share_warn "$key" "$shared" "${nonempty[0]}" "$shared"
    return 0
  fi

  mkdir -p "$runtime/shared-memory" 2>/dev/null || return 0

  # Seed the canonical store.
  if [ "${#nonempty[@]}" -eq 1 ] && [ "$shared_has" -eq 0 ]; then
    if [ -e "$shared" ]; then
      # existing shared dir is empty (shared_has==0) -> drop it, then move the live one in
      rmdir "$shared" 2>/dev/null || return 0
    fi
    mv "${nonempty[0]}" "$shared" 2>/dev/null || return 0
  else
    mkdir -p "$shared" 2>/dev/null || return 0
  fi

  # Flip every on-disk account's projects/<key>/memory to a symlink -> shared store.
  # Covers accounts that have not opened this repo yet (create the dir), replaces EMPTY
  # real dirs, leaves correct symlinks, and NEVER clobbers a non-empty real dir.
  local acct pk mem
  for acct in "$runtime"/.claude-*/; do
    [ -d "$acct" ] || continue
    pk="${acct}projects/$key"
    mem="$pk/memory"
    if [ -L "$mem" ]; then
      continue
    fi
    if [ -d "$mem" ] && _cc_dir_nonempty "$mem"; then
      continue
    fi
    mkdir -p "$pk" 2>/dev/null || continue
    if [ -d "$mem" ] && [ ! -L "$mem" ]; then
      rmdir "$mem" 2>/dev/null || continue
    fi
    [ -e "$mem" ] && continue
    ln -s "$shared" "$mem" 2>/dev/null || true
  done
  return 0
}

# Wrapper entry point: resolve the current key, then consolidate.
#   $1 = runtime path
_cc_share_memory() {
  local runtime="$1" key
  [ -n "$runtime" ] || return 0
  key=$(_cc_memory_key) || return 0
  [ -n "$key" ] || return 0
  _cc_share_memory_for_key "$runtime" "$key"
}
