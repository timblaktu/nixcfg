{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    nix
    git
    pre-commit
    gitleaks
    nixpkgs-fmt
    nil
    sops
  ];

  shellHook = ''
    echo "🔒 NixCfg development environment loaded (shell.nix)"
    if [ -d .git ] && [ ! -f .git/hooks/pre-commit ]; then
      echo "Detected missing pre-commit hooks. Installing.."
      pre-commit install
    fi
  '';
}
