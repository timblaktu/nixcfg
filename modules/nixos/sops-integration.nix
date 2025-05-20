# SOPS-NIX integration for secrets management
{ config, lib, pkgs, ... }:

{
  imports = [
    # Import sops-nix module (already included in flake.nix)
  ];

  # This setting determines the default secrets file to use
  sops.defaultSopsFile = ../secrets/common/secrets.yaml;
  
  # Define an example secret
  sops.secrets.example_key = {
    # No additional configuration needed for basic usage
  };
  
  # Define a secret with specific permissions
  sops.secrets.api_token = {
    owner = "tim";
    group = "users";
    mode = "0400";
  };
  
  # Define a secret to be used by a service
  sops.secrets.db_password = {
    owner = "postgres";
    group = "postgres";
    # This will make the path to the secret available as an environment variable
    # to the postgresql service
    sopsFile = ../secrets/common/db.yaml;
  };
  
  # Integration with systemd
  systemd.services.example-service = {
    serviceConfig = {
      # Make secret available to the service
      EnvironmentFile = [
        config.sops.secrets.api_token.path
      ];
    };
  };
}
