# Example NixOS module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.custom-service;
in {
  options.services.custom-service = {
    enable = mkEnableOption "custom service";
    
    port = mkOption {
      type = types.port;
      default = 8000;
      description = "Port to listen on";
    };
    
    # Add more options as needed
  };
  
  config = mkIf cfg.enable {
    # Your service configuration here
    systemd.services.custom-service = {
      description = "Custom Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      
      serviceConfig = {
        ExecStart = "${pkgs.bash}/bin/bash -c 'echo Service started on port ${toString cfg.port}'";
        Restart = "on-failure";
        User = "nobody";
      };
    };
  };
}
