# Custom packages
{ pkgs ? import <nixpkgs> { } }:

rec {
  nixvim-anywhere = pkgs.callPackage ./nixvim-anywhere { };
  markitdown = pkgs.callPackage ./markitdown-rs { };
  marker-pdf = pkgs.callPackage ./marker-pdf { };
  tomd = pkgs.callPackage ./tomd { inherit marker-pdf; };
}
