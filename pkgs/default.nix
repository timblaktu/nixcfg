# Custom packages
{ pkgs ? import <nixpkgs> { } }:

{
  nixvim-anywhere = pkgs.callPackage ./nixvim-anywhere { };
  markitdown = pkgs.callPackage ./markitdown-rs { };
}
