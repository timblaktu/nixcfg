# modules/programs/crowdstrike-falcon/crowdstrike-falcon.nix
# CrowdStrike Falcon sensor for NixOS [N]
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
#   - WSL2 note: Sensor enters Reduced Functionality Mode (RFM) on WSL2 kernel.
#     See docs/WSL-LIMITATIONS.md for details.
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
              cp -r usr/* $out/ 2>/dev/null || true
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
          ++ lib.optional (cfg.proxy.enable) "--apd=false --aph=${cfg.proxy.host} --app=${toString cfg.proxy.port}"
          ++ lib.optional (cfg.trace != "none") "--trace=${cfg.trace}"
        );

        # Resolve CID: secret file takes precedence over plaintext option
        cidValue =
          if cfg.cidSecretFile != null then
            "$(cat ${cfg.cidSecretFile})"
          else
            cfg.cid;

        # Resolve provisioning token similarly
        provisioningTokenValue =
          if cfg.provisioningTokenSecretFile != null then
            "$(cat ${cfg.provisioningTokenSecretFile})"
          else
            cfg.provisioningToken;

      in
      {
        options.services.falcon-sensor = {
          enable = lib.mkEnableOption "CrowdStrike Falcon sensor";

          package = lib.mkOption {
            type = lib.types.path;
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
            example = [ "Environment/Development" "Team/TigerTeam" ];
            description = "Sensor grouping tags (max 256 chars combined).";
          };

          backend = lib.mkOption {
            type = lib.types.enum [ "auto" "bpf" "kernel" ];
            default = "bpf";
            description = ''
              Sensor backend. "bpf" is recommended for NixOS and WSL2 (looser
              kernel requirements). "kernel" requires a kernel on CrowdStrike's
              supported whitelist.
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
        };

        config = lib.mkIf cfg.enable {
          assertions = [
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
