{ config, lib, pkgs, modulesPath, ... }:
let
  # Reference the default user from the wslCommon configuration
  inherit (config.wsl) defaultUser;

  driveConfigs = [
    { name = "timblaktu"; letter = "X"; }
    { name = "timandclaudiablack"; letter = "Y"; }
    { name = "timblacksoftware"; letter = "Z"; }
  ];
  commonDrvfsOptions = user: [
    "uid=${toString config.users.users.${user}.uid}"
    "gid=${toString config.users.groups.users.gid}"
  ];
  mkDriveMount = { name, letter }: {
    name = "/mnt/gdrive-${name}";
    value = {
      device = "${letter}:";
      fsType = "drvfs";
      options = commonDrvfsOptions defaultUser;
    };
  };
in
{
  fileSystems = builtins.listToAttrs (map mkDriveMount driveConfigs);
}
