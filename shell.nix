{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    nix
    git
    nixpkgs-fmt
    nil # Nix language server
    sops # For secrets
  ];
}
