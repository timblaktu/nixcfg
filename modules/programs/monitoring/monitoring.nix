# modules/programs/monitoring/monitoring.nix
# System monitoring tools and tmux dashboard
#
# Provides:
#   flake.modules.homeManager.monitoring - monitoring packages, btop config,
#     `monitor` launcher, `monitor-rebuild` declarative fallback
#   flake.modules.nixos.monitoring       - security.wrappers, below daemon,
#     sysstat collection
#
# Dashboard ownership model:
#   The live `monitor` tmux session is owned by tmux-resurrect/continuum: once
#   built, it is persisted across tmux server restarts by resurrect and the
#   monitoring commands are re-launched from resurrect's process whitelist
#   (configured in modules/programs/tmux/tmux.nix @resurrect-processes).
#
#   `monitor-rebuild` is a plain-tmux shell script generated declaratively by
#   nix on every home-manager switch. It is a PASSIVE FALLBACK — it is never
#   invoked automatically. Run it by hand only when:
#     * resurrect/continuum has restored a corrupted session
#     * you want to revert the live session to the canonical layout
#     * a fresh machine has no resurrect snapshot to restore from
#   It kills any existing `monitor` session and rebuilds it from scratch using
#   the windows/panes/commands defined in this file. Because it is regenerated
#   from nix on every switch, it is always in sync with the declared layout.
#
#   `monitor` is a convenience launcher: attach to the live session if it
#   exists, otherwise bootstrap it by calling `monitor-rebuild` and then attach.
#
# Features:
#   - Tier 1 packages: btop, bandwhich, sysstat, iotop-c, nvtop, below, trippy
#   - Tier 2 packages (opt-in via enableTier2): gping, nload, dool, iftop
#   - btop configured for build monitoring (iowait graphs, gruvbox theme)
#   - Dashboard windows: overview (btop + bandwhich), io (iostat + iotop-c),
#     network (nload + gping); extra (dool + iftop) when enableTier2 is set
#   - NixOS security.wrappers for bandwhich, iotop-c, trippy (capabilities)
#   - Optional below recording daemon (systemd service, eBPF-based)
#   - Optional sysstat collection (sadc timer for historical sar data)
#
# Quick start:
#   monitor              # Attach (or bootstrap+attach) to monitoring dashboard
#   monitor-rebuild      # Force-rebuild the session from the declarative spec
#   btop                 # Standalone system overview
#   below replay         # Historical system replay (requires below daemon)
#   sar -u 1 5           # CPU utilization from sysstat collection
#
# WSL2 caveats:
#   - below.enable defaults to false: needs cgroupv2 + eBPF on WSL2 kernel
#   - nvtop won't show GPU data without CUDA passthrough (wsl-settings.cuda.enable)
#   - bandwhich/iotop-c wrappers only active after NixOS rebuild (not just HM switch)
#   - sysstat.enable defaults to false: sadc should work on WSL2 but test first
#
# Usage in host config:
#   NixOS:  imports = [ inputs.self.modules.nixos.monitoring ];
#           monitoring.enable = true;
#   HM:     imports = [ inputs.self.modules.homeManager.monitoring ];
#           monitoring.enable = true;
#           monitoring.enableTier2 = true;  # optional
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager Module ===
    homeManager.monitoring = { config, lib, pkgs, ... }:
      let
        cfg = config.monitoring;
        pingTargetsStr = lib.concatStringsSep " " cfg.dashboard.pingTargets;

        # monitor-tool: tiny dispatcher that prefers the NixOS security.wrappers
        # path for capability-requiring tools (bandwhich, iotop-c, iftop, trip)
        # and falls back to PATH lookup. Used by monitor-rebuild so the same
        # rebuild script works on NixOS hosts (where /run/wrappers/bin/<tool>
        # exists with the right capabilities) and on Home-Manager-only hosts
        # (where it doesn't and the unwrapped binary runs in degraded mode or
        # fails visibly via remain-on-exit).
        monitor-tool = pkgs.writeShellApplication {
          name = "monitor-tool";
          runtimeInputs = [ ];
          text = ''
            tool="$1"; shift
            for d in /run/wrappers/bin /run/current-system/sw/bin; do
              if [ -x "$d/$tool" ]; then
                exec "$d/$tool" "$@"
              fi
            done
            exec "$tool" "$@"
          '';
        };

        # monitor-rebuild: declarative, plain-tmux construction of the
        # monitoring dashboard session. PASSIVE FALLBACK — never invoked
        # automatically. Run by hand when the live session has been corrupted
        # (by resurrect, by accident, by manual edits) or when bootstrapping a
        # fresh tmux server with no snapshot to restore.
        #
        # Idempotent: kills any existing session named ${cfg.dashboard.sessionName}
        # first, then rebuilds it from scratch using the windows/panes/commands
        # declared below. Because this script is regenerated on every
        # home-manager switch, it is always in sync with the nix-declared
        # layout and can be used to revert the live session to canonical state
        # at any time.
        monitor-rebuild = pkgs.writeShellApplication {
          name = "monitor-rebuild";
          runtimeInputs = [ pkgs.tmux monitor-tool ];
          # Each pane spawns the monitoring tool directly as its command (no
          # shell wrapper for the user's interactive zsh, no send-keys). This
          # avoids races between send-keys and shell init hooks, and ensures
          # `pane_current_command` reflects the real tool so resurrect's
          # @resurrect-processes whitelist matches on restore.
          #
          # Tools that require Linux capabilities (bandwhich, iotop-c, iftop,
          # trippy) are launched via `r <tool>` — a tiny inline shell helper
          # that prefers /run/wrappers/bin/<tool> (NixOS security.wrappers
          # path with capabilities) and falls back to PATH lookup. This keeps
          # the rebuild script identical between NixOS hosts (where the
          # wrappers exist) and Home-Manager-only hosts (where they don't and
          # the tool runs in degraded mode or fails visibly).
          #
          # `set-option -g remain-on-exit on` keeps a pane visible if its
          # tool exits (e.g. permission denied), so failures are diagnosable
          # instead of the pane silently disappearing.
          text = ''
            SESSION="${cfg.dashboard.sessionName}"
            T="${monitor-tool}/bin/monitor-tool"
            tmux kill-session -t "$SESSION" 2>/dev/null || true
            tmux set-option -g remain-on-exit on

            # Window 1: overview — btop (large) + bandwhich (small)
            tmux new-session -d -s "$SESSION" -n overview 'btop'
            tmux split-window -v -t "$SESSION:overview" "$T bandwhich"
            tmux select-layout -t "$SESSION:overview" main-horizontal
            tmux set-option -t "$SESSION:overview" main-pane-height 70%

            # Window 2: io — iostat + iotop-c (iotop-c needs CAP_SYS_PTRACE)
            tmux new-window -t "$SESSION:" -n io 'iostat -xz 2'
            tmux split-window -v -t "$SESSION:io" "$T iotop-c"
            tmux select-layout -t "$SESSION:io" even-vertical

            # Window 3: network — nload + gping
            tmux new-window -t "$SESSION:" -n network 'nload'
            tmux split-window -h -t "$SESSION:network" 'gping ${pingTargetsStr}'
            tmux select-layout -t "$SESSION:network" even-horizontal
          ''
          + lib.optionalString cfg.enableTier2 ''

            # Window 4: extra — dool + iftop (iftop needs CAP_NET_RAW)
            tmux new-window -t "$SESSION:" -n extra 'dool --all'
            tmux split-window -h -t "$SESSION:extra" "$T iftop"
            tmux select-layout -t "$SESSION:extra" tiled
          ''
          + ''

            tmux select-window -t "$SESSION:overview"
            echo "Rebuilt $SESSION session. Attach with: monitor"
          '';
        };

        # monitor: convenience launcher.
        #   - If already inside the monitor session: no-op
        #   - If the session exists: attach (or switch-client if in tmux)
        #   - Otherwise: bootstrap via monitor-rebuild, then attach
        monitor = pkgs.writeShellApplication {
          name = "monitor";
          runtimeInputs = [ pkgs.tmux monitor-rebuild ];
          text = ''
            SESSION="${cfg.dashboard.sessionName}"
            if [ -n "''${TMUX:-}" ]; then
              current=$(tmux display-message -p '#S')
              if [ "$current" = "$SESSION" ]; then
                echo "Already in $SESSION session"
                exit 0
              fi
            fi
            if ! tmux has-session -t "$SESSION" 2>/dev/null; then
              monitor-rebuild
            fi
            if [ -n "''${TMUX:-}" ]; then
              tmux switch-client -t "$SESSION"
            else
              tmux attach-session -t "$SESSION"
            fi
          '';
        };
      in
      {
        options.monitoring = {
          enable = lib.mkEnableOption "system monitoring tools and tmux dashboard";

          enableTier2 = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Tier 2 monitoring packages (gping, nload, dool, iftop)";
          };

          btop = {
            colorTheme = lib.mkOption {
              type = lib.types.str;
              default = "gruvbox_dark_v2";
              description = "btop color theme name";
            };

            updateMs = lib.mkOption {
              type = lib.types.int;
              default = 2000;
              description = "btop update interval in milliseconds";
            };
          };

          dashboard = {
            sessionName = lib.mkOption {
              type = lib.types.str;
              default = "monitor";
              description = "tmux session name for the monitoring dashboard";
            };

            pingTargets = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "1.1.1.1" "8.8.8.8" ];
              description = "Hosts to ping in gping pane";
            };
          };
        };

        config = lib.mkIf cfg.enable {
          # Tier 1 packages
          home.packages = with pkgs; [
            bandwhich
            sysstat
            iotop-c
            nvtopPackages.full
            below
            trippy
            gping
            nload
          ]
          # Tier 2 packages
          ++ lib.optionals cfg.enableTier2 [
            dool
            iftop
          ]
          # monitor + monitor-rebuild + monitor-tool (defined in outer let)
          ++ [ monitor monitor-rebuild monitor-tool ];

          # btop configuration via native HM module
          programs.btop = {
            enable = true;
            settings = {
              color_theme = cfg.btop.colorTheme;
              theme_background = false;
              update_ms = cfg.btop.updateMs;
              proc_sorting = "cpu lazy";
              shown_boxes = "cpu mem proc net";
              cpu_graph_lower = "iowait";
              cpu_graph_upper = "total";
              show_disks = true;
              io_mode = true;
            };
          };

        };
      };

    # === NixOS Module ===
    nixos.monitoring = { config, lib, pkgs, ... }:
      let
        cfg = config.monitoring;
      in
      {
        options.monitoring = {
          enable = lib.mkEnableOption "system monitoring NixOS integration (wrappers, daemons)";

          wrappers = {
            enableBandwhich = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Add security.wrappers entry for bandwhich (cap_net_admin,cap_net_raw)";
            };

            enableIotop = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Add security.wrappers entry for iotop-c (cap_net_admin,cap_dac_read_search,cap_sys_ptrace)";
            };

            enableTrippy = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Add security.wrappers entry for trippy (cap_net_raw)";
            };

            enableIftop = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Add security.wrappers entry for iftop (cap_net_raw,cap_net_admin)";
            };
          };

          below = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable below recording daemon (requires cgroupv2 + eBPF; opt-in on WSL2)";
            };

            retainSeconds = lib.mkOption {
              type = lib.types.int;
              default = 604800;
              description = "How long to retain below recordings (default: 7 days)";
            };

            intervalSeconds = lib.mkOption {
              type = lib.types.int;
              default = 5;
              description = "below recording interval in seconds";
            };
          };

          sysstat = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable sysstat (sadc) collection timer for historical sar data";
            };

            intervalSeconds = lib.mkOption {
              type = lib.types.int;
              default = 60;
              description = "sadc collection interval in seconds";
            };

            historyDays = lib.mkOption {
              type = lib.types.int;
              default = 7;
              description = "Number of days to retain sysstat data files";
            };
          };
        };

        config = lib.mkIf cfg.enable (lib.mkMerge [
          # Security wrappers for privilege elevation via capabilities
          (lib.mkIf cfg.wrappers.enableBandwhich {
            security.wrappers.bandwhich = {
              source = "${pkgs.bandwhich}/bin/bandwhich";
              capabilities = "cap_net_admin,cap_net_raw+ep";
              owner = "root";
              group = "root";
            };
          })

          (lib.mkIf cfg.wrappers.enableIotop {
            security.wrappers.iotop-c = {
              source = "${pkgs.iotop-c}/bin/iotop-c";
              # iotop relies on netlink taskstats (CVE-2011-2494 mitigation):
              # cap_net_admin is the one that actually unlocks the kernel
              # interface; the ptrace + dac_read_search caps let it inspect
              # other users' /proc entries.
              capabilities = "cap_net_admin,cap_dac_read_search,cap_sys_ptrace+ep";
              owner = "root";
              group = "root";
            };
          })

          (lib.mkIf cfg.wrappers.enableTrippy {
            security.wrappers.trip = {
              source = "${pkgs.trippy}/bin/trip";
              capabilities = "cap_net_raw+ep";
              owner = "root";
              group = "root";
            };
          })

          (lib.mkIf cfg.wrappers.enableIftop {
            security.wrappers.iftop = {
              source = "${pkgs.iftop}/bin/iftop";
              capabilities = "cap_net_raw,cap_net_admin+ep";
              owner = "root";
              group = "root";
            };
          })

          # below recording daemon
          (lib.mkIf cfg.below.enable {
            systemd.services.below-record = {
              description = "Below resource monitor recording daemon";
              after = [ "local-fs.target" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "simple";
                ExecStart = lib.concatStringsSep " " [
                  "${pkgs.below}/bin/below"
                  "record"
                  "--retain-for-s"
                  (toString cfg.below.retainSeconds)
                  "--interval-s"
                  (toString cfg.below.intervalSeconds)
                  "--compress"
                ];
                Restart = "on-failure";
                RestartSec = "10s";
              };
            };
          })

          # sysstat (sadc) collection
          (lib.mkIf cfg.sysstat.enable {
            # Ensure data directory exists
            systemd.tmpfiles.rules = [
              "d /var/log/sa 0755 root root -"
            ];

            # sadc oneshot service
            systemd.services.sysstat-collect = {
              description = "sysstat system activity data collection";
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${pkgs.sysstat}/lib/sa/sadc 1 1 /var/log/sa";
              };
            };

            # Timer for periodic collection
            systemd.timers.sysstat-collect = {
              description = "sysstat collection timer";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnBootSec = "1min";
                OnUnitActiveSec = "${toString cfg.sysstat.intervalSeconds}s";
                AccuracySec = "10s";
              };
            };

            # Daily cleanup of old data files
            systemd.services.sysstat-cleanup = {
              description = "sysstat data cleanup";
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${pkgs.findutils}/bin/find /var/log/sa -name 'sa*' -mtime +${toString cfg.sysstat.historyDays} -delete";
              };
            };

            systemd.timers.sysstat-cleanup = {
              description = "sysstat daily cleanup timer";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "daily";
                Persistent = true;
              };
            };
          })
        ]);
      };
  };
}
