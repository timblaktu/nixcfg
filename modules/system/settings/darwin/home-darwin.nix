# modules/system/settings/darwin/home-darwin.nix
# Darwin-only Home Manager layer
#
# Provides:
#   flake.modules.homeManager.home-darwin - macOS-specific HM tweaks composed
#     alongside the platform-neutral home-dev-team / home-enterprise tiers.
#
# This is the Darwin counterpart to home-wsl (wsl-enterprise.nix). Darwin hosts
# import home-dev-team + home-darwin, exactly as WSL hosts import home-dev-team
# + home-wsl. It is intentionally thin: the common tiers already cover ~81% of
# the corp dev stack natively on aarch64-darwin (see Plan 001 T10 portability
# inventory), and platform-aware modules (e.g. podman-tools, terminal) adapt
# themselves. Darwin-only home-manager options (macOS launchd agents, Colima env
# wiring, Spotlight/Finder HM tweaks) belong here as the need arises.
#
# Usage:
#   # In a Darwin host HM config (common tier + Darwin layer):
#   imports = [
#     inputs.self.modules.homeManager.home-dev-team
#     inputs.self.modules.homeManager.home-darwin
#   ];
_:
{
  flake.modules.homeManager.home-darwin = { ... }: {
    # Thin by design. No imports or settings yet -- the platform-neutral tiers
    # (home-enterprise / home-dev-team) plus the platform-aware feature modules
    # provide the working Darwin baseline. Add macOS-only HM config here when a
    # concrete need appears (keeps darwin-isms out of the common tiers).
  };
}
