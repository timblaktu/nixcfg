# modules/system/networking/mss-clamp/mss-clamp.nix
# Cross-platform TCP MSS clamping (+ optional interface MTU) for connectivity
# over MTU-constrained network paths.
#
# WHY THIS EXISTS
# ----------------
# A corporate VPN (e.g. Palo Alto GlobalProtect) tunneled over a low-MTU
# underlay - notably a phone hotspot whose carrier runs 464XLAT/NAT64 (IPv6-only
# cellular with a +20 B IPv6-header tax) - drops the effective path MTU well
# below 1500 (measured ~1340). On such a path Path-MTU-Discovery is typically
# broken too (the ICMP "fragmentation needed" / "packet too big" signals are
# filtered), so instead of adapting, large TCP packets are SILENTLY black-holed:
# small packets (ping, the TCP SYN) get through, but the server's large TLS
# certificate / HTTP body packets vanish, and curl/git/nix hang while a browser
# (QUIC/UDP, self-probing per RFC 8899) still works. Clamping the advertised TCP
# MSS so segments fit the constrained path restores connectivity.
#
# This is NOT a WSL feature - it is a generic networking-egress robustness
# measure. It lives here (structural, no corporate hostnames) so any host -
# the NixOS-WSL workstation behind GlobalProtect, the colleague's corp-wsl
# image, or an Apple-Silicon nix-darwin laptop on the same VPN - imports the
# same option. On the machine we cannot configure (the Windows host's PANGP
# stack is admin-locked), the WSL guest is the only egress we control; on the
# Mac, nix-darwin controls the host stack directly.
#
# SAFE TO LEAVE ALWAYS-ON. The clamp acts on every connection on every network,
# but harmlessly: 1240 = 1280 (IPv6 minimum MTU) - 40 B headers, which is
# universally routable, and the only cost is ~0.4% extra header overhead and
# marginally more packets. Making it conditional ("only when VPN+hotspot")
# would require a fragile network-detecting watchdog - the wrong trade for a
# free, reliable, stateless rule, especially while travelling on unknown links.
#
# PROVIDES
#   flake.modules.nixos.mss-clamp  - iptables mangle TCPMSS + optional ip-link MTU
#   flake.modules.darwin.mss-clamp - pf scrub max-mss + optional ifconfig MTU
#
# USAGE (host)
#   imports = [ inputs.self.modules.nixos.mss-clamp ];   # or .darwin.mss-clamp
#   mssClamp = {
#     enable = true;
#     # mss defaults to 1240
#     interfaceMtu = { eth0 = 1280; };  # belt-and-suspenders: caps OUTBOUND too
#   };
{ lib, ... }:
let
  # Shared option interface - identical on NixOS and Darwin so hosts configure
  # the feature the same way regardless of platform.
  sharedOptions = {
    enable = lib.mkEnableOption "TCP MSS clamping for MTU-constrained (VPN/cellular) network paths";

    mss = lib.mkOption {
      type = lib.types.ints.between 536 1460;
      default = 1240;
      description = ''
        MSS to clamp locally-originated TCP SYN segments to. Default 1240 =
        1280 (IPv6 minimum MTU) - 40 B (IPv4 + TCP headers); fits any reasonable
        path and is universally routable. Lower only for an even more
        constrained path.
      '';
    };

    interfaceMtu = lib.mkOption {
      type = lib.types.attrsOf (lib.types.ints.between 1280 9000);
      default = { };
      example = { eth0 = 1280; };
      description = ''
        Optional per-interface MTU set at boot. Belt-and-suspenders alongside the
        MSS clamp: the advertised-MSS clamp only bounds what the PEER sends us
        (inbound, the dominant TLS-download failure), whereas lowering the
        interface MTU also caps our OWN outbound segment size (e.g. large
        git pushes). Maps interface name -> MTU. NixOS applies it via
        `ip link set`; Darwin via `ifconfig`.
      '';
    };
  };
in
{
  flake.modules = {
    # === NixOS variant ===
    # iptables (nft backend) mangle rule on locally-originated TCP SYNs, applied
    # by a boot oneshot. The netfilter rule is independent of the interface, so
    # it survives WSL re-creating eth0 on a network change; a full VM restart
    # re-runs the oneshot. (If WSL resets eth0's MTU mid-session the explicit
    # interfaceMtu is lost until next boot, but the load-bearing MSS clamp
    # persists - which is why the clamp, not the MTU, is the primary mechanism.)
    nixos.mss-clamp = { config, lib, pkgs, ... }:
      let cfg = config.mssClamp;
      in {
        options.mssClamp = sharedOptions;

        config = lib.mkIf cfg.enable {
          systemd.services.mss-clamp = {
            description = "Clamp TCP MSS (+ optional iface MTU) for MTU-constrained network paths";
            after = [ "network.target" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            path = [ pkgs.iptables pkgs.iproute2 ];
            script = ''
              set -eu
              # MSS clamp on locally-originated TCP SYNs (idempotent: check, then add).
              if ! iptables -t mangle -C OUTPUT -p tcp --tcp-flags SYN,RST SYN \
                   -j TCPMSS --set-mss ${toString cfg.mss} 2>/dev/null; then
                iptables -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN \
                  -j TCPMSS --set-mss ${toString cfg.mss}
              fi
              ${lib.concatStringsSep "\n" (lib.mapAttrsToList (iface: mtu:
                "ip link set dev ${iface} mtu ${toString mtu} || true"
              ) cfg.interfaceMtu)}
            '';
          };
        };
      };

    # === Darwin variant ===
    # macOS has no iptables; the equivalent MSS clamp is pf's `scrub ... max-mss`.
    # A launchd daemon enables pf and loads a ruleset that re-includes Apple's
    # bundled anchors (so system rules still load) plus our global scrub.
    #
    # UNTESTED ON HARDWARE (authored without a Mac to hand). Validate on the work
    # Mac (pa163076mac): (1) confirm the macOS pf `scrub out all max-mss` syntax
    # is accepted by this OS version, (2) confirm loading this ruleset does not
    # disrupt corporate/MDM networking, (3) confirm connectivity over
    # GlobalProtect + hotspot is restored. If touching pf is undesirable on the
    # managed Mac, set only `interfaceMtu` (the ifconfig fallback) and drop the
    # scrub. Logs to /var/log/mss-clamp.log.
    darwin.mss-clamp = { config, lib, pkgs, ... }:
      let
        cfg = config.mssClamp;
        pfConf = pkgs.writeText "mss-clamp.pf.conf" ''
          # Preserve Apple's default anchors so system pf rules still load,
          # then add the global MSS-clamp scrub. pf is default-pass here (no
          # block rules) - this only normalizes MSS, it does not filter traffic.
          scrub-anchor "com.apple/*"
          anchor "com.apple/*"
          load anchor "com.apple" from "/etc/pf.anchors/com.apple"
          scrub out all max-mss ${toString cfg.mss}
          pass
        '';
      in
      {
        options.mssClamp = sharedOptions;

        config = lib.mkIf cfg.enable {
          launchd.daemons.mss-clamp = {
            script = ''
              set -eu
              # Enable pf (no-op if already enabled), then load the MSS-clamp ruleset.
              /sbin/pfctl -E 2>/dev/null || true
              /sbin/pfctl -f ${pfConf} 2>/dev/null || true
              ${lib.concatStringsSep "\n" (lib.mapAttrsToList (iface: mtu:
                "/sbin/ifconfig ${iface} mtu ${toString mtu} || true"
              ) cfg.interfaceMtu)}
            '';
            serviceConfig = {
              RunAtLoad = true;
              KeepAlive = false;
              StandardOutPath = "/var/log/mss-clamp.log";
              StandardErrorPath = "/var/log/mss-clamp.log";
            };
          };
        };
      };
  };
}
