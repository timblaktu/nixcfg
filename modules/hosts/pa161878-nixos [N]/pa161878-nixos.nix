# modules/hosts/pa161878-nixos [N]/pa161878-nixos.nix
# Dendritic host composition for pa161878-nixos (WSL work environment)
#
# This module defines both NixOS system and Home Manager configurations
# following the dendritic pattern. Uses the tiger-team layer modules as
# base, adding only personal-specific configuration.
#
# Layer chain:
#   NixOS:  wsl-tiger-team -> wsl-enterprise -> system-cli + wsl
#   HM:     home-tiger-team -> home-enterprise -> home-default + all tools
#
# Deploy NixOS: sudo nixos-rebuild switch --flake '.#pa161878-nixos'
# Deploy HM:    home-manager switch --flake '.#tim@pa161878-nixos'
{ config, lib, inputs, ... }:
let
  # SSH public keys (shared across configurations)
  sshKeys = {
    timblaktu = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGkVsx3oZrqwkfU6FmhqNEeAGN8dj6lPxNcEwVCmJcQh timblaktu@gmail.com";
  };

  # Common user settings
  username = config.meta.username;
  homeDirectory = "/home/${username}";
in
{
  # === NixOS System Module ===
  flake.modules.nixos.pa161878-nixos = { config, lib, pkgs, ... }: {
    imports = [
      ./_hardware-config.nix
      # Tiger-team layer (chains: wsl-enterprise -> system-cli + wsl)
      inputs.self.modules.nixos.wsl-tiger-team
    ];

    # Personal overrides (bare values override enterprise mkDefault;
    # mkForce where tiger-team sets bare values)
    systemDefault.userName = username;

    wsl-settings = {
      # mkForce: tiger-team sets "nixos-wsl-tiger" as bare value (priority 100)
      hostname = lib.mkForce "pa161878-nixos";
      defaultUser = username;
      sshPort = 2223;
      userGroups = [ "wheel" "dialout" ];
      sshAuthorizedKeys = [ sshKeys.timblaktu ];
      # binfmt.enable: inherited from tiger-team (true)
      # cuda.enable: inherited from enterprise (false)
      # usbip.autoAttachByHardwareId: inherited from tiger-team (FTDI, Jetson APX)
    };

    # Jetson Orin Nano USB device rules
    services.udev.packages = [
      (pkgs.writeTextFile {
        name = "10-jetson-usb";
        destination = "/etc/udev/rules.d/10-jetson-usb.rules";
        text = ''
          # NVIDIA Jetson Recovery Mode (APX) — USB flashing via sdkmanager/initrd flash
          SUBSYSTEM=="usb", ATTR{idVendor}=="0955", ATTR{idProduct}=="7523", MODE="0666", GROUP="dialout"

          # NVIDIA Jetson Orin Nano (L4T running) — ADB/serial over USB
          # Commented: PID 7020 is unverified for Orin Nano; confirm with usbipd.exe list when booted
          # SUBSYSTEM=="usb", ATTR{idVendor}=="0955", ATTR{idProduct}=="7020", MODE="0666", GROUP="dialout"
        '';
      })
    ];
  };

  # === Home Manager Module ===
  flake.modules.homeManager."${username}@pa161878-nixos" = { config, lib, pkgs, ... }: {
    imports = [
      # Tiger-team bundle (enterprise + team tools: claude-code, opencode,
      # gitlab-auth, podman, development-tools, windows-terminal, and all
      # enterprise modules: shell, git, tmux, neovim, wsl-home, etc.)
      inputs.self.modules.homeManager.home-tiger-team
      # Personal-only modules (not shared with team)
      inputs.self.modules.homeManager.secrets-management
      inputs.self.modules.homeManager.github-auth
      inputs.self.modules.homeManager.esp-idf
      inputs.self.modules.homeManager.pulumi
      # awscli: imported via home-tiger-team; azureAuth configured below
    ];

    # Required by system types
    homeMinimal = {
      inherit username homeDirectory;
    };

    # Host-specific overrides
    homeDefault.enableLocalAI = false;
    espIdf.enable = true;
    pulumi.enable = true;

    # Secrets management (personal bitwarden)
    secretsManagement = {
      enable = true;
      rbw.email = "timblaktu@gmail.com";
      rbw.lockTimeout = 28800; # 8 hours
    };

    # GitHub authentication (personal PATs + org tokens)
    gitAuth.github = {
      enable = true;
      mode = "bitwarden";
      bitwarden = {
        item = "github.com";
        field = "PAT-timtam2026";
      };
      cli.tokenOverrides.pr = {
        item = "github.com";
        field = "PAT-pubclassic";
      };
      orgs.kyosaku-kai = {
        bitwarden = {
          item = "github.com";
          field = "kyosaku-kai-2026";
        };
      };
    };

    # GitLab authentication (host + personal credentials)
    gitAuth.gitlab = {
      host = "git.panasonic.aero";
      mode = "bitwarden";
      bitwarden = {
        item = "GitLab git.panasonic.aero";
        field = "lord (access token)";
      };
      cli.apiUser = "blackt1";
    };

    # AWS CLI with Azure AD SSO (personal -- needs secretsManagement for rbw)
    awscli = {
      enable = true;
      azureAuth.enable = true;
    };

    # Git: use work email for work GitLab repos
    programs.git.includes = [
      {
        condition = "hasconfig:remote.*.url:https://git.panasonic.aero/**";
        contents.user.email = "timothy.black@panasonic.aero";
      }
    ];

    # === Claude Code: personal accounts + deployment-specific work config ===
    # Tiger-team provides structural work account template; we fill in
    # deployment values (baseUrl, bitwarden, modelMappings) and add personal accounts.
    programs.claude-code.defaultAccount = lib.mkForce "max";
    programs.claude-code.accounts = inputs.self.lib.claudeCode.personalAccounts // {
      work = (inputs.self.lib.claudeCode.workAccount.work or {}) // {
        api = {
          baseUrl = "https://codecompanionv2.d-dp.nextcloud.aero";
          authMethod = "bedrock";
          modelMappings = {
            haiku = "devstral";
            sonnet = "qwen-a3b";
            opus = "claude-sonnet-4-5-20250929";
          };
        };
        secrets.bearerToken.bitwarden = {
          item = "PAC Code Companion v2";
          field = "Bedrock API Key";
        };
      };
    };

    # === OpenCode: personal accounts + deployment-specific work config ===
    programs.opencode.defaultAccount = lib.mkForce "max";
    programs.opencode.accounts = inputs.self.lib.openCode.personalAccounts // {
      work = (inputs.self.lib.openCode.workAccount.work or {}) // {
        model = "bedrock/us.anthropic.claude-sonnet-4-5-20250929-v1:0";
        secrets.envTokens = {
          BEDROCK_API_TOKEN = {
            bitwarden = { item = "PAC Code Companion v2"; field = "Bedrock API Key"; };
          };
          AI_PROXY_API_KEY = {
            bitwarden = { item = "PAC Code Companion v2"; field = "API Key"; };
          };
        };
      };
    };
    programs.opencode.provider = {
      bedrock = {
        options.baseURL = "https://ai-platform-bedrockapis.d-dp.nextcloud.aero/api/v1";
        models = {
          "us.anthropic.claude-sonnet-4-5-20250929-v1:0" = { name = "Claude Sonnet 4.5"; };
          "us.anthropic.claude-opus-4-5-20251101-v1:0" = { name = "Claude Opus 4.5"; };
        };
      };
      ai-proxy = {
        options.baseURL = "https://codecompanionv2.d-dp.nextcloud.aero/v1";
        models = {
          "qwen-a3b" = {
            name = "Qwen A3B";
            modalities = {
              input = [ "text" "image" ];
              output = [ "text" ];
            };
          };
          "devstral" = { name = "Devstral"; };
          "kimi-linear-reap-a3b" = { name = "Kimi Linear Reap A3B"; };
          "glm-47" = { name = "GLM 47"; };
        };
      };
    };
  };

  # === Configuration Registration ===
  # Note: Registration is done in flake-modules/ files using lib helpers.
  # The host module only defines flake.modules.{nixos,homeManager}.* content.
  # This avoids circular dependencies that occur when trying to both define
  # and register configurations in the same module.
  #
  # Registration happens in:
  # - flake-modules/nixos-configurations.nix (uses lib.mkNixos)
  # - flake-modules/home-configurations.nix (uses lib.mkHomeManager)
}
