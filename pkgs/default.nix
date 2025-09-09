# Custom packages
{ pkgs ? import <nixpkgs> {} }:

{
  nixvim-anywhere = pkgs.callPackage ./nixvim-anywhere {};
}
