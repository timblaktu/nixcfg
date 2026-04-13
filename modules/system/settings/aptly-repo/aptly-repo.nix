# modules/system/settings/aptly-repo/aptly-repo.nix
# Aptly Debian apt repository server module
#
# Provides:
#   flake.modules.nixos.aptly-repo - Aptly service with declarative repos
#
# Configures aptly as a Debian apt repository server with REST API.
# Publishes signed repos via filesystem endpoints; Caddy serves them.
#
# GPG signing has two modes:
#   generateKey = true:  Generates a keypair on first boot if none exists.
#                        Fully reproducible -- no external secrets needed.
#                        Key survives reboots (in dataDir/.gnupg) but not
#                        full disk wipes (regenerated automatically).
#   generateKey = false: Copies pre-provisioned keyrings from secrets manager.
#                        Stable key identity across reinstalls, but requires
#                        secret decryption (host key dependency).
#
# Declarative repos: attrset of repos created/published idempotently
# via the aptly API at boot.
_: {
  flake.modules.nixos.aptly-repo = { config, lib, pkgs, ... }:

    with lib;

    let
      cfg = config.services.aptly-repo;

      publishDir =
        if (cfg.publishEndpoints ? default)
        then cfg.publishEndpoints.default.rootDir
        else "${cfg.dataDir}/public";

      gnupgDir =
        if cfg.signing.keyringDir != null
        then cfg.signing.keyringDir
        else "${cfg.dataDir}/.gnupg";

      # Repo submodule type
      repoSubmodule = types.submodule {
        options = {
          distribution = mkOption {
            type = types.str;
            description = "Distribution name (appears in dists/<distribution>/)";
            example = "main";
          };
          component = mkOption {
            type = types.str;
            default = "main";
            description = "Component name for the repository";
          };
          comment = mkOption {
            type = types.str;
            default = "";
            description = "Human-readable comment for the repository";
          };
          architectures = mkOption {
            type = types.nullOr (types.listOf types.str);
            default = null;
            description = "Architectures for this repo. Falls back to global aptly architectures when null.";
          };
        };
      };

      # Generate aptly.conf JSON from Nix options
      aptlyConfig = builtins.toJSON ({
        rootDir = cfg.dataDir;
        downloadConcurrency = 4;
        architectures = cfg.architectures;
        gpgDisableSign = !cfg.signing.enable;
        gpgDisableVerify = !cfg.signing.enable;
        gpgProvider = cfg.signing.gpgProvider;
      } // optionalAttrs (cfg.publishEndpoints != { }) {
        FileSystemPublishEndpoints = cfg.publishEndpoints;
      } // cfg.extraConfig);

      configFile = pkgs.writeText "aptly.conf" aptlyConfig;

      gpg = "${pkgs.gnupg}/bin/gpg";

      # Script: generate GPG keypair on first boot if none exists
      generateGpgScript = pkgs.writeShellScript "aptly-setup-gpg-generate" ''
        set -euo pipefail

        GNUPG_DIR="${gnupgDir}"
        PUBLISH_DIR="${publishDir}"

        mkdir -p "$GNUPG_DIR"
        chmod 0700 "$GNUPG_DIR"

        if [ -f "$GNUPG_DIR/secring.gpg" ] && [ -f "$GNUPG_DIR/pubring.gpg" ]; then
          echo "aptly-setup-gpg: keyrings exist, skipping generation"
        else
          echo "aptly-setup-gpg: generating new GPG keypair..."
          TMPGNUPG=$(mktemp -d)

          ${gpg} --homedir "$TMPGNUPG" --batch --gen-key <<'KEYSPEC'
        Key-Type: RSA
        Key-Length: 4096
        Name-Real: n3x Apt Repository
        Name-Email: apt@n3x.internal
        Expire-Date: 0
        %no-protection
        %commit
        KEYSPEC

          ${gpg} --homedir "$TMPGNUPG" --export-secret-keys > "$GNUPG_DIR/secring.gpg"
          ${gpg} --homedir "$TMPGNUPG" --export > "$GNUPG_DIR/pubring.gpg"
          chmod 0600 "$GNUPG_DIR/secring.gpg"
          chmod 0644 "$GNUPG_DIR/pubring.gpg"

          rm -rf "$TMPGNUPG"
          echo "aptly-setup-gpg: keypair generated"
        fi

        chown -R aptly:aptly "$GNUPG_DIR"

        # Export ASCII public key to publish dir (always, in case publish dir was wiped)
        mkdir -p "$PUBLISH_DIR"
        TMPEXPORT=$(mktemp -d)
        cp "$GNUPG_DIR/pubring.gpg" "$TMPEXPORT/pubring.gpg"
        ${gpg} --homedir "$TMPEXPORT" --no-default-keyring \
          --keyring "$TMPEXPORT/pubring.gpg" --armor --export \
          > "$PUBLISH_DIR/gpg-key.asc" 2>/dev/null
        rm -rf "$TMPEXPORT"
        chmod 0644 "$PUBLISH_DIR/gpg-key.asc"
        chown aptly:aptly "$PUBLISH_DIR/gpg-key.asc"

        echo "aptly-setup-gpg: done"
      '';

      # Script: copy pre-provisioned GPG keyrings (secrets manager mode)
      copyGpgScript = pkgs.writeShellScript "aptly-setup-gpg-copy" ''
        set -euo pipefail

        GNUPG_DIR="${gnupgDir}"
        PUBLISH_DIR="${publishDir}"

        echo "aptly-setup-gpg: copying pre-provisioned keyrings to $GNUPG_DIR"

        mkdir -p "$GNUPG_DIR"
        chmod 0700 "$GNUPG_DIR"

        cp "${cfg.signing.privateKeyFile}" "$GNUPG_DIR/secring.gpg"
        chmod 0600 "$GNUPG_DIR/secring.gpg"

        cp "${cfg.signing.publicKeyFile}" "$GNUPG_DIR/pubring.gpg"
        chmod 0644 "$GNUPG_DIR/pubring.gpg"

        chown -R aptly:aptly "$GNUPG_DIR"

        ${optionalString (cfg.signing.publicKeyAsciiFile != null) ''
          mkdir -p "$PUBLISH_DIR"
          cp "${cfg.signing.publicKeyAsciiFile}" "$PUBLISH_DIR/gpg-key.asc"
          chmod 0644 "$PUBLISH_DIR/gpg-key.asc"
          chown aptly:aptly "$PUBLISH_DIR/gpg-key.asc"
        ''}

        echo "aptly-setup-gpg: done"
      '';

      # Script: create repos and publish endpoints idempotently via API
      ensureReposScript = pkgs.writeShellScript "aptly-ensure-repos" ''
        set -euo pipefail

        API="http://${cfg.bindAddress}:${toString cfg.port}"

        # Wait for API readiness
        echo "aptly-ensure-repos: waiting for API at $API"
        for i in $(seq 1 30); do
          if ${pkgs.curl}/bin/curl -sf "$API/api/version" > /dev/null 2>&1; then
            echo "aptly-ensure-repos: API ready"
            break
          fi
          if [ "$i" = "30" ]; then
            echo "aptly-ensure-repos: FATAL - API not ready after 30s" >&2
            exit 1
          fi
          sleep 1
        done

        ${concatStringsSep "\n" (mapAttrsToList
          (name: repo:
            let
              repoArchitectures =
                if repo.architectures != null
                then repo.architectures
                else cfg.architectures;
              signingJson =
                if cfg.signing.enable then
                  { Batch = true; } // optionalAttrs (cfg.signing.keyId != null) { GpgKey = cfg.signing.keyId; }
                else
                  { Skip = true; };
              createJson = builtins.toJSON {
                Name = name;
                Comment = repo.comment;
                DefaultDistribution = repo.distribution;
                DefaultComponent = repo.component;
              };
              publishJson = builtins.toJSON {
                SourceKind = "local";
                Sources = [{ Name = name; Component = repo.component; }];
                Distribution = repo.distribution;
                Architectures = repoArchitectures;
                Signing = signingJson;
              };
            in
            ''
              # --- Repo: ${name} ---
              if ! ${pkgs.curl}/bin/curl -sf "$API/api/repos/${name}" > /dev/null 2>&1; then
                echo "aptly-ensure-repos: creating repo ${name}"
                ${pkgs.curl}/bin/curl -sf -X POST "$API/api/repos" \
                  -H 'Content-Type: application/json' \
                  -d '${createJson}'
                echo ""
              else
                echo "aptly-ensure-repos: repo ${name} already exists"
              fi

              # Check if distribution is already published on this endpoint
              DIST_COUNT=$(${pkgs.curl}/bin/curl -sf "$API/api/publish" | \
                ${pkgs.jq}/bin/jq '[.[] | select(.Storage == "filesystem:default" and .Distribution == "${repo.distribution}")] | length' 2>/dev/null || echo "0")

              if [ "$DIST_COUNT" = "0" ]; then
                echo "aptly-ensure-repos: publishing ${name} (distribution: ${repo.distribution})"
                ${pkgs.curl}/bin/curl -sf -X POST "$API/api/publish/filesystem:default:" \
                  -H 'Content-Type: application/json' \
                  -d '${publishJson}'
                echo ""
              else
                echo "aptly-ensure-repos: distribution ${repo.distribution} already published"
              fi
            '')
          cfg.repos)}

        echo "aptly-ensure-repos: done"
      '';
    in
    {
      options.services.aptly-repo = {
        enable = mkEnableOption "aptly Debian repository server";

        port = mkOption {
          type = types.port;
          default = 8080;
          description = "Port for aptly REST API";
        };

        bindAddress = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = ''
            Address to bind the API to. Default is localhost-only
            (Caddy reverse-proxies to provide external access).
          '';
        };

        dataDir = mkOption {
          type = types.path;
          default = "/var/lib/aptly";
          description = "Root directory for aptly data (repos, pool, db)";
        };

        architectures = mkOption {
          type = types.listOf types.str;
          default = [ "amd64" "arm64" ];
          description = "Architectures to support in repositories";
        };

        signing = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Enable GPG signing of published repos. When false, aptly
              publishes unsigned repos (suitable for initial testing).
            '';
          };

          gpgProvider = mkOption {
            type = types.enum [ "internal" "gpg" "gpg1" "gpg2" ];
            default = "internal";
            description = ''
              GPG implementation. "internal" uses aptly's built-in Go
              implementation (no external gpg required). "gpg"/"gpg2"
              use the system gpg binary.
            '';
          };

          keyringDir = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = ''
              Path to GPG keyring directory. When using the internal
              provider, this is the directory containing the private key.
              When null, defaults to $dataDir/.gnupg.
            '';
          };

          privateKeyFile = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Path to GPG private keyring (secring.gpg). Used in copy mode
              (generateKey = false). Set to the decrypted secret path,
              e.g. from sops-nix.
            '';
          };

          publicKeyFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = ''
              Path to GPG public keyring (pubring.gpg). Stored unencrypted
              in the nix store.
            '';
          };

          publicKeyAsciiFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = ''
              Path to ASCII-armored GPG public key. Copied to the publish
              directory as gpg-key.asc for client download.
            '';
          };

          keyId = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              GPG key ID to use for signing. When null, aptly uses the
              first available key in the keyring.
            '';
          };

          generateKey = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Generate a GPG keypair on first boot if none exists in the
              keyring directory. The key persists across reboots (stored in
              dataDir/.gnupg) but is regenerated after a full disk wipe.

              When true, privateKeyFile/publicKeyFile are ignored.
              The public key is exported to the publish directory as
              gpg-key.asc on every boot.

              This mode is suitable for hosts where the SSH host key may
              change (reinstalls) and secrets would become undecryptable.
            '';
          };
        };

        repos = mkOption {
          type = types.attrsOf repoSubmodule;
          default = { };
          description = ''
            Declarative aptly repositories. Each entry creates a local repo
            and publishes it to the default filesystem endpoint at boot.
          '';
        };

        publishEndpoints = mkOption {
          type = types.attrsOf (types.attrsOf types.anything);
          default = {
            default = {
              rootDir = "/var/lib/aptly/public";
              linkMethod = "hardlink";
              verifyMethod = "md5";
            };
          };
          description = ''
            FileSystemPublishEndpoints for aptly.conf. Each key is an
            endpoint name; the default endpoint publishes to the public
            directory served by Caddy.
          '';
        };

        extraConfig = mkOption {
          type = types.attrsOf types.anything;
          default = { };
          description = "Extra JSON fields to merge into aptly.conf";
        };

        openFirewall = mkOption {
          type = types.bool;
          default = false;
          description = "Open firewall port for aptly API";
        };
      };

      config = mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.signing.enable && !cfg.signing.generateKey -> cfg.signing.privateKeyFile != null;
            message = "services.aptly-repo.signing.enable requires signing.privateKeyFile (or signing.generateKey = true)";
          }
          {
            assertion = cfg.signing.enable && !cfg.signing.generateKey -> cfg.signing.publicKeyFile != null;
            message = "services.aptly-repo.signing.enable requires signing.publicKeyFile (or signing.generateKey = true)";
          }
        ];

        environment.systemPackages = [
          pkgs.aptly
        ] ++ optional (cfg.signing.gpgProvider != "internal" || cfg.signing.generateKey) pkgs.gnupg;

        # GPG keyring setup service
        systemd.services.aptly-setup-gpg = mkIf cfg.signing.enable {
          description = "Set up GPG keyrings for aptly signing";
          wantedBy = [ "multi-user.target" ];
          before = [ "aptly.service" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = if cfg.signing.generateKey then generateGpgScript else copyGpgScript;
          };
        };

        # aptly API server
        systemd.services.aptly = {
          description = "Aptly Debian Repository API Server";
          after = [ "network.target" ]
            ++ optional cfg.signing.enable "aptly-setup-gpg.service";
          requires = optional cfg.signing.enable "aptly-setup-gpg.service";
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "simple";
            ExecStart = concatStringsSep " " [
              "${pkgs.aptly}/bin/aptly"
              "api"
              "serve"
              "-config=${configFile}"
              "-listen=${cfg.bindAddress}:${toString cfg.port}"
              "-no-lock"
            ];
            User = "aptly";
            Group = "aptly";
            StateDirectory = "aptly";
            WorkingDirectory = cfg.dataDir;
            Environment = "HOME=${cfg.dataDir}";
            Restart = "on-failure";
            RestartSec = "5s";

            # Hardening
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = [ cfg.dataDir ];
            NoNewPrivileges = true;
            PrivateTmp = true;
          };

          # Ensure publish directory exists
          preStart = ''
            ${optionalString (cfg.publishEndpoints ? default) ''
              mkdir -p ${cfg.publishEndpoints.default.rootDir}
            ''}
          '';
        };

        # Declarative repo creation and publishing service
        systemd.services.aptly-ensure-repos = mkIf (cfg.repos != { }) {
          description = "Ensure aptly repositories exist and are published";
          after = [ "aptly.service" ];
          requires = [ "aptly.service" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = ensureReposScript;
          };
        };

        # System user and group
        users.users.aptly = {
          isSystemUser = true;
          group = "aptly";
          home = cfg.dataDir;
        };
        users.groups.aptly = { };

        # Ensure publish directory exists before service starts (systemd namespace
        # setup requires all ReadWritePaths to exist; preStart runs too late)
        systemd.tmpfiles.rules = optional (cfg.publishEndpoints ? default) (
          "d ${cfg.publishEndpoints.default.rootDir} 0755 aptly aptly -"
        );

        # Firewall
        networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
      };
    };
}
