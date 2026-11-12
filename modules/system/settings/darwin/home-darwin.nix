# modules/system/settings/darwin/home-darwin.nix
# Darwin-only Home Manager layer
#
# Provides:
#   flake.modules.homeManager.home-darwin - the thin macOS-only HM layer for the
#     host, composed alongside the platform-neutral home-enterprise tier.
#
# This is the Darwin counterpart to home-wsl (wsl-enterprise.nix). Under the
# two-role corp Mac model, nix-darwin configures the macOS HOST (appearance,
# apps, power, Touch-ID, and the Nix + Lima prerequisites) while the actual dev
# environment runs inside a Lima NixOS Linux guest, substituted from the cache,
# NOT natively on macOS. So the macOS host imports the ENTERPRISE tier
# (home-enterprise) + home-darwin as a thin host, while the DEV tier
# (home-dev-team + toolchain) is a guest concern - unlike a WSL host, which
# imports home-dev-team + home-wsl directly because it IS the dev environment.
#
# home-darwin stays intentionally thin. The platform-neutral tiers are largely
# portable to aarch64-darwin (see Plan 001 T10 portability inventory, ~81%),
# which is why the native host layer CAN stay thin - not because the dev stack
# runs natively on the Mac. Darwin-only home-manager options (macOS launchd
# agents, Spotlight/Finder HM tweaks) belong here as the need arises.
#
# Usage:
#   # In a Darwin host HM config (enterprise tier + Darwin layer):
#   imports = [
#     inputs.self.modules.homeManager.home-enterprise
#     inputs.self.modules.homeManager.home-darwin
#   ];
_:
{
  flake.modules.homeManager.home-darwin = _: {
    # Thin by design. No imports or settings yet -- the host's enterprise tier
    # (home-enterprise) plus the platform-aware feature modules provide the
    # working macOS host baseline (the dev tier runs in the Lima guest, not
    # here). Add macOS-only HM config here when a concrete need appears (keeps
    # darwin-isms out of the common tiers).
  };
}
