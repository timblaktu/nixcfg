# pkgs/dev-switch/default.nix
#
# dev-switch: activate a downstream flake's home-manager / NixOS / nix-darwin
# config while overriding one or more of its inputs with LOCAL checkouts.
#
# Motivation: when you develop an upstream module library (e.g. nixcfg) that a
# downstream flake consumes (e.g. nixcfg-work), the normal apply loop is
# commit -> push -> `nix flake update <input>` -> switch. That round-trips the
# network on every tweak. dev-switch collapses it to a single `--override-input`
# switch against your local working copy, so you push/relock only once, at the
# end. It is deliberately generic: any input name, any local path, any of the
# three activation front-ends, any target flake.
{ lib, writeShellApplication, git, nix, coreutils }:

writeShellApplication {
  name = "dev-switch";
  runtimeInputs = [ git nix coreutils ];
  # home-manager / nixos-rebuild / darwin-rebuild are intentionally NOT bundled:
  # they are resolved from the caller's PATH at runtime to avoid version coupling.
  text = ''
    set -euo pipefail

    PROG=dev-switch
    ACTION=home
    DIRTY=0
    PRINT=0
    declare -a OVERRIDES=()
    declare -a EXTRA=()
    TARGET=""

    usage() {
      cat <<'EOF'
    dev-switch - activate a flake config with LOCAL input overrides (fast dev loop)

    Usage:
      dev-switch [options] [TARGET] [-- EXTRA_ARGS...]

    TARGET:
      A flake config to activate: either full 'FLAKE#ATTR' or just 'FLAKE'. When
      the '#ATTR' is omitted it defaults per --action:
        home           -> "$USER@$(hostname)"
        nixos|darwin   -> "$(hostname)"
      TARGET itself defaults to '.' when omitted.

    Options:
      -o, --override NAME=PATH   Override input NAME with local PATH. Repeatable.
                                PATH -> git+file://ABS?ref=BRANCH&rev=HEAD (committed),
                                or path:ABS when --dirty (uncommitted working tree).
      -a, --action ACTION       home | nixos | darwin            (default: home)
      -d, --dirty               Include uncommitted working-tree changes of overrides
                                (uses path:, which copies the whole dir incl. .git).
      -p, --print               Print the assembled command instead of running it.
      -h, --help                Show this help.

    Anything after '--', and any unrecognized flag, is passed through to the
    underlying switch command (e.g. --show-trace, --refresh, -j0).

    Examples:
      # Test local nixcfg via the nixcfg-work home config (the nixcfg dev loop):
      dev-switch -o nixcfg=~/src/nixcfg ~/src/nixcfg-work

      # Iterate on UNCOMMITTED edits (no commit needed):
      dev-switch -d -o nixcfg=~/src/nixcfg ~/src/nixcfg-work

      # NixOS host, override two inputs, pass a nix flag through:
      dev-switch -a nixos -o nixpkgs=~/src/nixpkgs -o foo=~/src/foo ~/src/mysys -- --show-trace

      # Just show what would run:
      dev-switch -p -o nixcfg=~/src/nixcfg ~/src/nixcfg-work
    EOF
    }

    die() { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 2; }

    while (( $# )); do
      case "$1" in
        -o|--override) [[ $# -ge 2 ]] || die "--override needs NAME=PATH"; OVERRIDES+=("$2"); shift 2 ;;
        --override=*)  OVERRIDES+=("''${1#*=}"); shift ;;
        -a|--action)   [[ $# -ge 2 ]] || die "--action needs a value"; ACTION="$2"; shift 2 ;;
        --action=*)    ACTION="''${1#*=}"; shift ;;
        -d|--dirty)    DIRTY=1; shift ;;
        -p|--print)    PRINT=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        --)            shift; EXTRA+=("$@"); break ;;
        -*)            EXTRA+=("$1"); shift ;;   # unknown flag -> pass through
        *)             if [[ -z "$TARGET" ]]; then TARGET="$1"; else EXTRA+=("$1"); fi; shift ;;
      esac
    done

    case "$ACTION" in home|nixos|darwin) ;; *) die "invalid --action '$ACTION' (home|nixos|darwin)" ;; esac

    # Default target + attr.
    [[ -n "$TARGET" ]] || TARGET="."
    if [[ "$TARGET" != *"#"* ]]; then
      case "$ACTION" in
        home) TARGET="$TARGET#$USER@$(hostname)" ;;
        *)    TARGET="$TARGET#$(hostname)" ;;
      esac
    fi

    # Resolve each NAME=PATH override into --override-input args.
    declare -a OARGS=()
    resolve() {
      local spec="$1" name path abs ref rev url
      [[ "$spec" == *=* ]] || die "override must be NAME=PATH: '$spec'"
      name="''${spec%%=*}"
      path="''${spec#*=}"
      path="''${path/#\~/$HOME}"                       # expand a leading ~
      abs="$(cd "$path" 2>/dev/null && pwd)" || die "override path not found: $path"
      if (( DIRTY )); then
        url="path:$abs"
      elif git -C "$abs" rev-parse --git-dir >/dev/null 2>&1; then
        ref="$(git -C "$abs" branch --show-current || true)"
        rev="$(git -C "$abs" rev-parse HEAD)"
        if git -C "$abs" status --porcelain --untracked-files=no | grep -q .; then
          printf '%s: note: %s has uncommitted tracked changes; using committed HEAD %s (pass --dirty to include them)\n' \
            "$PROG" "$abs" "''${rev:0:12}" >&2
        fi
        if [[ -n "$ref" ]]; then url="git+file://$abs?ref=$ref&rev=$rev"; else url="git+file://$abs?rev=$rev"; fi
      else
        url="path:$abs"
      fi
      OARGS+=(--override-input "$name" "$url")
    }
    if (( ''${#OVERRIDES[@]} )); then
      for o in "''${OVERRIDES[@]}"; do resolve "$o"; done
    fi

    # Assemble the activation command.
    declare -a CMD=()
    case "$ACTION" in
      home)   CMD=(home-manager switch --flake "$TARGET") ;;
      nixos)  CMD=(sudo nixos-rebuild switch --flake "$TARGET") ;;
      darwin) CMD=(darwin-rebuild switch --flake "$TARGET") ;;
    esac
    (( ''${#OARGS[@]} )) && CMD+=("''${OARGS[@]}")
    (( ''${#EXTRA[@]} )) && CMD+=("''${EXTRA[@]}")

    if (( PRINT )); then
      printf '%q ' "''${CMD[@]}"; printf '\n'
      exit 0
    fi
    printf '%s: + %s\n' "$PROG" "''${CMD[*]}" >&2
    exec "''${CMD[@]}"
  '';

  meta = {
    description = "Activate a flake config with local --override-input checkouts (fast dev loop)";
    longDescription = ''
      dev-switch runs home-manager / nixos-rebuild / darwin-rebuild switch against a
      downstream flake while overriding one or more of its inputs with local
      checkouts, so upstream module changes can be tested without commit/push/relock
      churn. Generic over input name, local path, activation front-end and target.
    '';
    mainProgram = "dev-switch";
    platforms = lib.platforms.unix;
  };
}
