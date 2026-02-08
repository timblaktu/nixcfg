# Shared library for Git forge authentication modules (GitHub, GitLab, etc.)
#
# Provides common option types, helper functions, and wrapper generators
# for consistent authentication across different git forges.
#
# Usage:
#   let
#     gitForgeLib = import ./lib/git-forge-auth.nix { inherit pkgs lib config options; };
#   in
#   gitForgeLib.mkBitwardenOptions { ... }
#
{ pkgs, lib, config, options }:

let
  inherit (lib) mkOption mkEnableOption types mkIf mkMerge mkForce optionalString;

  # Import shared rbw helper library
  rbwLib = import ./rbw.nix { inherit pkgs lib; };
in
rec {
  # Re-export rbwLib for convenience
  inherit rbwLib;

  # Common Bitwarden credential options
  # Used by both GitHub and GitLab modules
  mkBitwardenOptions = { defaultTokenName, exampleItem ? null }: {
    tokenName = mkOption {
      type = types.str;
      default = defaultTokenName;
      description = ''
        Bitwarden entry name for the token.
        Deprecated: Use 'item' and 'field' for more control.
      '';
    };

    item = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Bitwarden item name.
        Takes precedence over tokenName if set.
      '';
      example = exampleItem;
    };

    field = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Custom field name within the Bitwarden item.
        If null, retrieves the password field.
        Only used when 'item' is set.
      '';
      example = "token";
    };
  };

  # Common SOPS options
  mkSopsOptions = { defaultSecretName, defaultSecretsFile }: {
    secretName = mkOption {
      type = types.str;
      default = defaultSecretName;
      description = "Secret name in SOPS file";
    };

    secretsFile = mkOption {
      type = types.path;
      default = defaultSecretsFile;
      description = "Path to SOPS secrets file";
    };
  };

  # Common git credential helper options
  mkGitCredentialOptions = { defaultUserName ? null }: {
    enableCredentialHelper = mkOption {
      type = types.bool;
      default = true;
      description = "Configure git credential helper for this forge";
    };

    userName = mkOption {
      type = types.nullOr types.str;
      default = defaultUserName;
      description = ''
        Username for HTTPS authentication.
        If null, the credential helper will provide the username.
      '';
    };
  };

  # Helper to resolve bitwarden config to item/field for rbwLib
  resolveBwConfig = bwCfg:
    if bwCfg.item != null then {
      item = bwCfg.item;
      field = bwCfg.field;
    } else {
      item = bwCfg.tokenName;
      field = null;
    };

  # Generate a CLI wrapper with Bitwarden token injection
  mkBitwardenCliWrapper =
    { name           # Binary name (e.g., "gh", "glab")
    , package        # Package providing the binary
    , bwConfig       # Bitwarden configuration (item, field, tokenName)
    , envVar         # Environment variable name (e.g., "GH_TOKEN")
    , syncInterval   # Sync interval in seconds
    }:
    let
      resolved = resolveBwConfig bwConfig;
    in
    pkgs.writeShellScriptBin name ''
      ${rbwLib.mkGitAuthSetup {
        inherit (resolved) item field;
        varName = envVar;
        staleSeconds = syncInterval;
      }}
      exec ${package}/bin/${name} "$@"
    '';

  # Generate a CLI wrapper with SOPS token injection
  mkSopsCliWrapper =
    { name           # Binary name (e.g., "gh", "glab")
    , package        # Package providing the binary
    , sopsConfig     # SOPS configuration (secretName)
    , envVar         # Environment variable name
    }:
    pkgs.writeShellScriptBin name ''
      ${if options ? sops then ''
        TOKEN_FILE="${config.sops.secrets."${sopsConfig.secretName}".path}"
        if [ -f "$TOKEN_FILE" ]; then
          export ${envVar}="$(cat "$TOKEN_FILE")"
        fi
      '' else ''
        echo "Warning: SOPS mode configured but SOPS module not available" >&2
      ''}
      exec ${package}/bin/${name} "$@"
    '';

  # Common mode option
  mkModeOption = mkOption {
    type = types.enum [ "bitwarden" "sops" ];
    default = "bitwarden";
    description = "Secret backend to use for token storage";
  };

  # Common protocol option
  mkProtocolOption = mkOption {
    type = types.enum [ "https" "ssh" ];
    default = "https";
    description = "Git protocol for operations";
  };

  # Common rbw sync interval option
  mkRbwSyncIntervalOption = mkOption {
    type = types.int;
    default = 300;
    description = ''
      Time in seconds before rbw cache is considered stale and needs sync.
      The sync happens automatically before credential retrieval if the
      last sync was longer than this interval ago.

      Set to 0 to sync on every command (slower but always fresh).
      Set to a larger value (e.g., 3600) if you rarely rotate tokens.

      Default: 300 (5 minutes)
    '';
    example = 600;
  };
}
