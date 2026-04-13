# modules/programs/crowdstrike-falcon/crowdstrike-falcon.nix
# CrowdStrike Falcon sensor for NixOS
#
# Provides:
#   flake.modules.nixos.crowdstrike-falcon - CrowdStrike Falcon sensor systemd service
#
# Features:
#   - Package derivation: .deb extraction + autoPatchelfHook + buildFHSEnv wrapper
#   - Systemd service: falcond with ExecStartPre for falconctl configuration
#   - Mutable /opt/CrowdStrike via tmpfiles (required by falcon sensor)
#   - Secret file support for CID and provisioning token (SOPS/agenix compatible)
#   - Golden image support: autoRemoveAid clears Agent ID on service start
#
# WSL2 WARNING: The microsoft-standard-WSL2 kernel is NOT on CrowdStrike's
# supported kernel whitelist. The sensor enters Reduced Functionality Mode (RFM)
# on WSL2 — heartbeats and inventory only, no detection or prevention. The
# Windows-side Falcon WSL2 Visibility Plugin (sensor 7.26+) provides actual
# detection coverage for WSL2 workloads. See:
#   - docs/CROWDSTRIKE-WSL2-SECURITY-BRIEF.md (IT-facing overview)
#   - modules/programs/crowdstrike-falcon/docs/WSL-LIMITATIONS.md (technical reference)
#
# Usage:
#   imports = [ inputs.self.modules.nixos.crowdstrike-falcon ];
#   services.falcon-sensor = {
#     enable = true;
#     package = pkgs.requireFile { ... };  # or /path/to/falcon-sensor.deb
#     cid = "XXXXXXXX-XX";
#   };
{ config, lib, inputs, ... }:
{
  flake.modules = {

    nixos.crowdstrike-falcon = { config, lib, pkgs, ... }:
      let
        cfg = config.services.falcon-sensor;

        # Build the falcon-sensor package from a .deb file.
        # The .deb contains precompiled binaries that need FHS paths.
        falcon-sensor-unwrapped = pkgs.stdenv.mkDerivation {
          pname = "falcon-sensor-unwrapped";
          version = cfg.packageVersion;

          src = cfg.package;

          nativeBuildInputs = with pkgs; [
            dpkg
            autoPatchelfHook
          ];

          buildInputs = with pkgs; [
            openssl
            libnl
            zlib
            stdenv.cc.cc.lib
          ];

          unpackPhase = ''
            dpkg-deb -x "$src" .
          '';

          installPhase = ''
            mkdir -p $out

            # Falcon sensor installs to /opt/CrowdStrike
            if [ -d opt/CrowdStrike ]; then
              cp -r opt/CrowdStrike $out/opt-crowdstrike
            fi

            # Some .deb layouts use usr/lib or usr/bin
            if [ -d usr ]; then
              cp -r usr/* $out/
            fi

            # Ensure key binaries are findable
            mkdir -p $out/bin
            for bin in falcond falconctl falcon-kernel-check; do
              if [ -f "$out/opt-crowdstrike/$bin" ]; then
                ln -sf "$out/opt-crowdstrike/$bin" "$out/bin/$bin"
              fi
            done
          '';

          # Falcon sensor links against libraries at runtime that may not
          # be in the derivation closure -- FHS wrapper handles this.
          dontAutoPatchelf = false;

          meta = {
            description = "CrowdStrike Falcon sensor (extracted from .deb)";
            license = lib.licenses.unfree;
            platforms = [ "x86_64-linux" ];
          };
        };

        # Wrap in FHS environment so falcond can find its expected paths.
        # unsharePid must be false -- falcond needs to see system PIDs.
        falcon-sensor-fhs = pkgs.buildFHSEnv {
          name = "falcon-sensor-fhs";
          unsharePid = false;
          unshareUser = false;
          unshareIpc = false;
          unshareNet = false;
          unshareCgroup = false;

          targetPkgs = pkgs: with pkgs; [
            openssl
            libnl
            zlib
            stdenv.cc.cc.lib
            # Falcon needs access to /proc, /sys, and kernel interfaces
            iproute2
            procps
            kmod
          ];

          extraBuildCommands = ''
            # Falcon expects its binaries under /opt/CrowdStrike
            mkdir -p $out/opt/CrowdStrike
          '';

          runScript = "bash";
        };

        # Build falconctl command with all configured parameters
        falconctlSetArgs = lib.concatStringsSep " " (
          lib.optional (cidValue != "") "--cid=${cidValue}"
          ++ lib.optional (provisioningTokenValue != "") "--provisioning-token=${provisioningTokenValue}"
          ++ lib.optional (cfg.tags != [ ]) "--tags=${lib.concatStringsSep "," cfg.tags}"
          ++ lib.optional (cfg.backend != "auto") "--backend=${cfg.backend}"
          ++ lib.optionals cfg.proxy.enable [
            "--apd=false"
            "--aph=${cfg.proxy.host}"
            "--app=${toString cfg.proxy.port}"
          ]
          ++ lib.optional (cfg.cloudRegion != "us-1") "--cloud=${cfg.cloudRegion}"
          ++ lib.optional (cfg.trace != "none") "--trace=${cfg.trace}"
        );

        # Resolve CID: secret file takes precedence over plaintext option
        cidValue =
          if cfg.cidSecretFile != null then
            "$(cat '${cfg.cidSecretFile}')"
          else
            cfg.cid;

        # Resolve provisioning token similarly
        provisioningTokenValue =
          if cfg.provisioningTokenSecretFile != null then
            "$(cat '${cfg.provisioningTokenSecretFile}')"
          else
            cfg.provisioningToken;

      in
      {
        options.services.falcon-sensor = {
          enable = lib.mkEnableOption ''
            CrowdStrike Falcon sensor.

            On WSL2, the sensor enters Reduced Functionality Mode (RFM) because the
            microsoft-standard-WSL2 kernel is not on CrowdStrike's supported whitelist.
            RFM provides heartbeats and asset inventory only — no detection or prevention.
            Set {option}`acknowledgeWslRfm` to suppress the WSL RFM warning.
            See docs/CROWDSTRIKE-WSL2-SECURITY-BRIEF.md for the full analysis
          '';

          package = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Path to the Falcon sensor .deb package. The package is not
              publicly downloadable -- it requires CrowdStrike Falcon Console
              authentication.

              Options:
              - requireFile: `pkgs.requireFile { name = "falcon-sensor_7.x.deb"; sha256 = "..."; }`
              - Local path: `/path/to/falcon-sensor.deb`
              - Corporate artifact server: `builtins.fetchurl { ... }`
            '';
            example = lib.literalExpression ''
              pkgs.requireFile {
                name = "falcon-sensor_7.18.0-17106_amd64.deb";
                sha256 = "0000000000000000000000000000000000000000000000000000";
                url = "https://falcon.crowdstrike.com/hosts/sensor-downloads";
              }
            '';
          };

          packageVersion = lib.mkOption {
            type = lib.types.str;
            default = "0.0.0";
            description = "Version string for the Falcon sensor package (informational).";
            example = "7.18.0-17106";
          };

          cid = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Customer ID (CID). Format: <hex>-<checksum>.";
          };

          cidSecretFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Path to a file containing the CID (alternative to plaintext cid option).
              Use with SOPS/agenix for secret management. Takes precedence over cid.
            '';
            example = "/run/secrets/crowdstrike-cid";
          };

          provisioningToken = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Installation/provisioning token for host registration.";
          };

          provisioningTokenSecretFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Path to a file containing the provisioning token.
              Takes precedence over provisioningToken.
            '';
            example = "/run/secrets/crowdstrike-provisioning-token";
          };

          tags = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [ "Environment/Development" "Team/DevTeam" ];
            description = "Sensor grouping tags (max 256 chars combined).";
          };

          backend = lib.mkOption {
            type = lib.types.enum [ "auto" "bpf" "kernel" ];
            default = "bpf";
            description = ''
              Sensor backend. "bpf" is recommended for NixOS (looser kernel
              requirements). "kernel" requires a kernel on CrowdStrike's
              supported whitelist.

              Note: On WSL2, neither backend prevents Reduced Functionality Mode
              (RFM). The kernel identity check triggers RFM regardless of backend
              choice because the microsoft-standard-WSL2 kernel is not whitelisted.
            '';
          };

          cloudRegion = lib.mkOption {
            type = lib.types.enum [ "us-1" "us-2" "eu-1" "us-gov-1" "us-gov-2" ];
            default = "us-1";
            description = "CrowdStrike cloud region.";
          };

          proxy = {
            enable = lib.mkEnableOption "proxy for Falcon cloud communication";
            host = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Proxy hostname.";
            };
            port = lib.mkOption {
              type = lib.types.port;
              default = 8080;
              description = "Proxy port.";
            };
          };

          trace = lib.mkOption {
            type = lib.types.enum [ "none" "err" "warn" "info" "debug" ];
            default = "warn";
            description = "Sensor log/trace level.";
          };

          autoRemoveAid = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Remove Agent ID (AID) on service start. Enable for golden image
              cloning so each instance gets a unique AID upon first registration.
            '';
          };

          acknowledgeWslRfm = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Whether you acknowledge that on WSL2, the Falcon sensor enters
              Reduced Functionality Mode (RFM) — heartbeats and asset inventory
              only, no detection or prevention. The microsoft-standard-WSL2 kernel
              is not on CrowdStrike's supported whitelist and this cannot be changed.

              Set to true to suppress the WSL RFM assertion. This confirms you
              understand the sensor provides compliance inventory only on WSL2,
              and that actual detection coverage comes from the Windows-side Falcon
              WSL2 Visibility Plugin (sensor 7.26+).

              See docs/CROWDSTRIKE-WSL2-SECURITY-BRIEF.md for the full analysis.
            '';
          };
        };

        config = lib.mkIf cfg.enable {
          assertions = [
            {
              assertion = cfg.package != null;
              message = "services.falcon-sensor.package must be set to a Falcon sensor .deb path.";
            }
            {
              assertion = cfg.cid != "" || cfg.cidSecretFile != null;
              message = ''
                services.falcon-sensor: Either `cid` or `cidSecretFile` must be
                set when the Falcon sensor is enabled. Contact IT for your
                CrowdStrike Customer ID (CID).
              '';
            }
            {
              assertion = cfg.proxy.enable -> cfg.proxy.host != "";
              message = ''
                services.falcon-sensor: `proxy.host` must be set when proxy is enabled.
              '';
            }
            {
              assertion = builtins.stringLength (lib.concatStringsSep "," cfg.tags) <= 256;
              message = "services.falcon-sensor.tags: combined length exceeds CrowdStrike's 256-char limit.";
            }
            {
              assertion = !((config.wsl.enable or false) && cfg.backend == "kernel");
              message = "services.falcon-sensor: 'kernel' backend is not supported on WSL2. Use 'bpf'.";
            }
            {
              assertion = !((config.wsl.enable or false) && cfg.enable && !cfg.acknowledgeWslRfm);
              message = ''
                services.falcon-sensor: On WSL2, the CrowdStrike Falcon sensor enters
                Reduced Functionality Mode (RFM) — heartbeats and asset inventory only,
                no detection or prevention. The microsoft-standard-WSL2 kernel is not on
                CrowdStrike's supported whitelist.

                Actual WSL2 detection coverage comes from the Windows-side Falcon WSL2
                Visibility Plugin (sensor 7.26+), not from a Linux sensor inside WSL.

                If you understand this and want the sensor for compliance inventory,
                set `services.falcon-sensor.acknowledgeWslRfm = true`.

                See docs/CROWDSTRIKE-WSL2-SECURITY-BRIEF.md for the full analysis.
              '';
            }
          ];

          # Allow unfree -- Falcon sensor is proprietary
          nixpkgs.config.allowUnfreePredicate = pkg:
            builtins.elem (lib.getName pkg) [
              "falcon-sensor-unwrapped"
            ];

          # Mutable directory required by Falcon sensor at runtime.
          # The sensor writes state (AID, channel files, event logs) here.
          systemd.tmpfiles.rules = [
            "d /opt/CrowdStrike 0750 root root -"
          ];

          systemd.services.falcon-sensor = {
            description = "CrowdStrike Falcon Sensor";
            after = [ "network-online.target" "local-fs.target" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];

            path = [ falcon-sensor-fhs ];

            serviceConfig = {
              Type = "forking";
              PIDFile = "/run/falcond.pid";

              ExecStartPre =
                let
                  setupScript = pkgs.writeShellScript "falcon-sensor-setup" ''
                    set -euo pipefail

                    # Symlink sensor binaries into /opt/CrowdStrike
                    # (falcond expects to find its support files here)
                    for f in ${falcon-sensor-unwrapped}/opt-crowdstrike/*; do
                      base="$(basename "$f")"
                      ln -sf "$f" "/opt/CrowdStrike/$base"
                    done

                    ${lib.optionalString cfg.autoRemoveAid ''
                      # Remove existing Agent ID for golden image cloning
                      if [ -f /opt/CrowdStrike/falconctl ]; then
                        /opt/CrowdStrike/falconctl -d --aid || true
                      fi
                    ''}

                    # Configure sensor parameters via falconctl
                    if [ -f /opt/CrowdStrike/falconctl ] && [ -n "${falconctlSetArgs}" ]; then
                      /opt/CrowdStrike/falconctl -s ${falconctlSetArgs}
                    fi
                  '';
                in
                "+${setupScript}";

              ExecStart = "${falcon-sensor-fhs}/bin/falcon-sensor-fhs -c /opt/CrowdStrike/falcond";

              Restart = "on-failure";
              RestartSec = 5;
              TimeoutStartSec = 120;

              # Security hardening (minimal -- falcond needs broad access)
              ProtectSystem = "false";
              ProtectHome = "read-only";
            };

            unitConfig = {
              # Documentation for operators
              Documentation = [
                "https://falcon.crowdstrike.com/documentation"
              ];
            };
          };
        };
      };

  };
}
