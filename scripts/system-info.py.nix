{ lib, pkgs }:
{
  deps = with pkgs.python3Packages; [
    psutil
  ];

  options = {
    # Enable Python validation (flake8, etc.)
    doCheck = true;
    # Could specify flakeIgnore rules if needed:
    # flakeIgnore = [ "E501" "W503" ];
  };
}
