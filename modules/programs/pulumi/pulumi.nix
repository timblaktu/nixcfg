# modules/programs/pulumi/pulumi.nix
# Pulumi Infrastructure-as-Code CLI tooling
#
# Provides:
#   flake.modules.homeManager.pulumi - Pulumi CLI with optional ESC and plugins
#
# Features:
#   - Pulumi CLI installation
#   - Optional Pulumi ESC (Environments, Secrets, Configuration)
#   - User-specified provider/language plugins from nixpkgs
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.pulumi ];
#   pulumi.enable = true;
{ config, lib, inputs, ... }:
{
  flake.modules = {
    homeManager.pulumi = { config, lib, pkgs, ... }:
      let
        cfg = config.pulumi;
      in
      {
        options.pulumi = {
          enable = lib.mkEnableOption "Pulumi Infrastructure-as-Code CLI";

          enableEsc = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Install pulumi-esc (Environments, Secrets, Configuration)";
          };

          plugins = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = ''
              Additional Pulumi provider or language packages from nixpkgs.
              Example: [ pkgs.pulumi-language-python pkgs.pulumiPackages.pulumi-aws-native ]
            '';
          };
        };

        config = lib.mkIf cfg.enable (lib.mkMerge [
          # Inject Claude Code skill when both pulumi and claude-code are enabled
          (lib.mkIf (config.programs.claude-code.enable or false) {
            programs.claude-code.skills.custom.pulumi = {
              description = "Pulumi IaC recipes for stack management, state operations, and infrastructure deployment. Use when working with Pulumi stacks, previewing changes, or managing cloud resources.";
              skillContent = ''
                # Pulumi Infrastructure-as-Code Skill

                ## State Backend Configuration
                ```bash
                # S3 backend
                export PULUMI_BACKEND_URL="s3://my-state-bucket"
                export PULUMI_CONFIG_PASSPHRASE="..."  # for encryption

                # Stack config (Pulumi.dev.yaml) is LOCAL and gitignored
                # It is NOT stored in the state backend
                ```

                ## Stack Configuration
                ```bash
                # Set config values
                pulumi config set key value
                pulumi config set --secret key "sensitive-value"
                pulumi config rm key

                # View current config
                pulumi config
                ```

                ## Deployment
                ```bash
                # ALWAYS preview before applying
                pulumi preview
                pulumi up

                # Preview specific resource changes
                pulumi preview --diff
                ```

                ## State Surgery
                ```bash
                # Remove orphaned resources from state
                pulumi state delete <urn>

                # Import existing resources
                pulumi import <type> <name> <id>
                ```

                ## Common Gotchas

                ### AMI Changes May Not Replace Instances
                EC2 AMI changes in Pulumi modules may NOT force instance replacement.
                Verify the module tracks AMI as a replace-triggering property.
                Use `replaceOnChanges: ["ami"]` if needed.

                ### IgnoreChanges Pattern
                For SSM parameters or other values that get manually overwritten:
                ```typescript
                new aws.ssm.Parameter("param", {
                  // ...
                }, { ignoreChanges: ["value"] });
                ```

                ### Stack References
                Stack config files (`Pulumi.<stack>.yaml`) are local and gitignored.
                They contain per-environment configuration, not infrastructure state.
                State lives in the backend (S3, Pulumi Cloud, etc.).
              '';
            };
          })

          {
            home.packages =
              [ pkgs.pulumi ]
              ++ lib.optional cfg.enableEsc pkgs.pulumi-esc
              ++ cfg.plugins;
          }
        ]);
      };
  };
}
