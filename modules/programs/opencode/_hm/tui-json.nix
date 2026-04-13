# modules/programs/opencode/_hm/tui-json.nix
# OpenCode TUI config deployment (tui.json)
#
# OpenCode reads two config files:
#   - opencode.json: providers, MCP, agents, permissions, etc.
#   - tui.json:      theme, keybinds, scroll behavior, diff style, plugins
#
# This sub-module owns the `programs.opencode.tui.*` option surface and writes
# `tui.json` per account via the activation script. The tui keys MUST NOT be
# written into opencode.json — upstream `config/tui-migrate.ts` runs on every
# opencode startup, detects tui keys in opencode.json, and will only migrate
# them into tui.json if tui.json does NOT already exist. Combined with our
# activation script's rm/cp of opencode.json every HM switch, that silently
# discards tui.* changes after the first switch. See Plan 032 T1 findings.
#
# Upstream schema: ~/src/opencode/packages/opencode/src/config/tui-schema.ts
# Keybind keys:    ~/src/opencode/packages/opencode/src/config/config.ts:610-765
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.opencode;
  tuiCfg = cfg.tui;
  inherit (cfg) nixcfgPath;
  runtimePath = "${nixcfgPath}/opencode-runtime";

  # Build the tui.json payload for an account. All keys are optional —
  # only emit keys the user actually set so we don't fight upstream defaults.
  mkTuiConfig = _accountName:
    {
      "$schema" = "https://opencode.ai/tui.json";
    }
    // optionalAttrs (tuiCfg.theme != null) { inherit (tuiCfg) theme; }
    // optionalAttrs (tuiCfg.scrollSpeed != null) {
      scroll_speed = tuiCfg.scrollSpeed;
    }
    // optionalAttrs (tuiCfg.scrollAcceleration != null) {
      scroll_acceleration = { enabled = tuiCfg.scrollAcceleration; };
    }
    // optionalAttrs (tuiCfg.diffStyle != null) {
      diff_style = tuiCfg.diffStyle;
    }
    // optionalAttrs (tuiCfg.keybinds != { }) {
      keybinds = tuiCfg.keybinds;
    }
    // optionalAttrs (tuiCfg.plugins != [ ]) {
      plugin = tuiCfg.plugins;
    }
    // optionalAttrs (tuiCfg.pluginEnabled != { }) {
      plugin_enabled = tuiCfg.pluginEnabled;
    };

  mkTuiFile = accountName:
    pkgs.writeText "tui-${accountName}.json"
      (builtins.toJSON (mkTuiConfig accountName));

  # True if any tui option has a non-default value worth writing
  hasTuiContent =
    tuiCfg.theme != null
    || tuiCfg.scrollSpeed != null
    || tuiCfg.scrollAcceleration != null
    || tuiCfg.diffStyle != null
    || tuiCfg.keybinds != { }
    || tuiCfg.plugins != [ ]
    || tuiCfg.pluginEnabled != { };

in
{
  options.programs.opencode.tui = {
    # ─────────────────────────────────────────────────────────────────────
    # Core TUI fields (moved here from opencode.nix — they belong in tui.json)
    # Defaults are `null` so we only write keys the user sets, leaving
    # upstream defaults in place otherwise.
    # ─────────────────────────────────────────────────────────────────────
    theme = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Theme name (null = upstream default). Lives in tui.json.";
    };

    scrollSpeed = mkOption {
      type = types.nullOr (types.either types.int types.float);
      default = null;
      description = ''
        TUI scroll speed (null = upstream default).
        Upstream constraint: number >= 0.001.
      '';
    };

    scrollAcceleration = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = ''
        Enable scroll acceleration (null = upstream default). Serialized as
        `scroll_acceleration.enabled` in tui.json.
      '';
    };

    diffStyle = mkOption {
      # Upstream tui-schema.ts:22 — enum is strictly ["auto", "stacked"].
      # Prior values "unified" and "side-by-side" were invalid and silently
      # rejected by upstream's zod .strict() schema.
      type = types.nullOr (types.enum [ "auto" "stacked" ]);
      default = null;
      description = ''
        Diff display style (null = upstream default).
        Upstream accepts only "auto" or "stacked" — "auto" adapts to terminal
        width, "stacked" always uses single-column rendering.
      '';
    };

    # ─────────────────────────────────────────────────────────────────────
    # Keybinds
    # Upstream `KeybindOverride` in tui-schema.ts is a strict object whose
    # keys must be a subset of Config.Keybinds.shape (~110 bindings listed
    # in config.ts:610-765). We use `attrsOf str` here — unknown keys will
    # be rejected by upstream at runtime, which is the correct error path.
    # ─────────────────────────────────────────────────────────────────────
    keybinds = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = literalExpression ''
        {
          leader = "ctrl+x";
          session_new = "<leader>n";
          session_compact = "<leader>c";
        }
      '';
      description = ''
        TUI keybind overrides. Keys must match upstream binding names
        (see ~/src/opencode/packages/opencode/src/config/config.ts:610-765).
        Values are comma-separated key combinations.
      '';
    };

    # ─────────────────────────────────────────────────────────────────────
    # Plugins (tui-scoped — distinct from top-level `plugin` in opencode.json)
    # ─────────────────────────────────────────────────────────────────────
    plugins = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "TUI plugin specs (file paths or npm package specs).";
    };

    pluginEnabled = mkOption {
      type = types.attrsOf types.bool;
      default = { };
      description = "Per-plugin enable/disable overrides (keyed by plugin id).";
    };
  };

  config = mkIf (cfg.enable && hasTuiContent) {
    # Deploy tui.json per account, after the main opencodeConfigTemplates run
    # so the account directories already exist.
    home.activation.opencodeTuiJson = lib.hm.dag.entryAfter [ "opencodeConfigTemplates" ] ''
      ${concatStringsSep "\n" (mapAttrsToList (accountName: account: ''
        if [[ "${toString account.enable}" == "1" ]]; then
          accountDir="${runtimePath}/.opencode-${accountName}"
          tuiTarget="$accountDir/tui.json"

          # Remove any stale migration backup created by upstream
          # tui-migrate.ts on previous runs — the backup is from a period
          # when we were (incorrectly) writing tui keys into opencode.json.
          $DRY_RUN_CMD rm -f "$accountDir/opencode.json.tui-migration.bak"

          $DRY_RUN_CMD rm -f "$tuiTarget"
          $DRY_RUN_CMD cp "${mkTuiFile accountName}" "$tuiTarget"
          $DRY_RUN_CMD chmod 644 "$tuiTarget"
          echo "Updated: $tuiTarget"
        fi
      '') cfg.accounts)}
    '';
  };
}
