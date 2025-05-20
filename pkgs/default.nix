# Custom packages
{ pkgs ? import <nixpkgs> {} }:

{
  example-package = pkgs.callPackage ./example-package {};
  
  # Add more packages as needed
  # my-package = pkgs.callPackage ./my-package {};
}
