# modules/system/settings/dev-team/dev-team.nix
# Platform-agnostic dev team NixOS module
#
# Provides:
#   flake.modules.nixos.dev-team - Shared dev team system config
#
# This is the platform-agnostic base for dev team configurations.
# It imports system-cli and adds binfmt cross-compilation, Podman,
# Claude Code enterprise, and standard dev utilities.
#
# Platform-specific layers import this module and add their own config:
#   - wsl-dev-team: adds WSL enterprise base, USBIP, terminal profile
#   - nixos-dev-team: adds VM hardware config
#   - nixos-proxmox-dev-team: adds Proxmox image output
#
# Does NOT set nixpkgs.config.allowUnfree (must stay at registration
# level for VM test compatibility).
#
# Does NOT import system-cli -- consumers must co-import a system type.
# NixOS deferred modules (flake-parts pattern) are not deduplicated by
# reference identity, so importing system-cli here AND in wsl-enterprise
# causes "option already declared" errors. Instead:
#   - nixos-dev-team imports system-cli + dev-team
#   - wsl-dev-team imports wsl-enterprise (has system-cli) + dev-team
#
# Priority layering:
#   dev-team uses mkDefault (1000) for all values -- platform layers
#   and hosts can override with bare values (100) or mkForce (50).
#
# Usage:
#   # In a host module (must co-import a system type):
#   imports = [
#     inputs.self.modules.nixos.system-cli  # or wsl-enterprise, etc.
#     inputs.self.modules.nixos.dev-team
#   ];
{ config, lib, inputs, ... }:
{
  flake.modules.nixos.dev-team = { config, lib, pkgs, inputs, ... }: {

    config = {
      # === User & System Defaults ===
      # Generic username for distribution (default credential, users expected to change)
      systemDefault.userName = lib.mkDefault "user";

      # TODO: manage this secret via rbw (Bitwarden item: "dev-team VM Default User")
      # Default password for initial access (hash of "pac123")
      users.users.${config.systemDefault.userName} = {
        hashedPassword = lib.mkDefault
          "$6$2VLAqVZZHeMdVqhL$TLfROheuwsIheXUaz4CHuceiXmdsRdTVtmQUEGTgRrHpTUgr7aiMzq7vGGqdS62x7pDI1Ryhxd4DWDloeCRc0/";
        # Note: On WSL, plugdev must also be in wsl-settings.userGroups (wsl-dev-team
        # handles this) because wsl.nix uses mkOverride 90 on extraGroups.
        extraGroups = lib.mkDefault [ "plugdev" ];
      };

      # Passwordless sudo for wheel group (standard for dev images)
      security.sudo.wheelNeedsPassword = lib.mkDefault false;

      # Enable SSH password authentication (admin requirement)
      systemCli.sshPasswordAuth = lib.mkDefault true;

      # State version
      system.stateVersion = lib.mkDefault "24.11";

      # === Cross-Architecture Build Support (binfmt + QEMU) ===
      # Only emulate architectures that aren't the native system.
      # On x86_64: emulate aarch64 (cross-build Graviton images).
      # On aarch64: no emulation needed (native Graviton builds).
      boot.binfmt.emulatedSystems = lib.mkDefault
        (lib.optionals (pkgs.stdenv.hostPlatform.system != "aarch64-linux") [ "aarch64-linux" ]);
      boot.binfmt.preferStaticEmulators = lib.mkDefault true;
      # matchCredentials (C flag) enables credential pass-through for binfmt
      # Only set when aarch64 emulation is active (not on native aarch64 hosts)
      boot.binfmt.registrations.aarch64-linux.matchCredentials =
        lib.mkIf (pkgs.stdenv.hostPlatform.system != "aarch64-linux") (lib.mkDefault true);
      nix.settings.extra-platforms = lib.mkDefault
        (lib.optionals (pkgs.stdenv.hostPlatform.system != "aarch64-linux") [ "aarch64-linux" ]);

      # === Feature Flags ===
      # Enable Podman container runtime
      systemCli.enablePodman = lib.mkDefault true;

      # Enable Claude Code enterprise managed settings at /etc/claude-code/
      systemCli.enableClaudeCodeEnterprise = lib.mkDefault true;

      # === Development Utilities ===
      environment.systemPackages = with pkgs; [
        usbutils # lsusb -- USB device enumeration (Jetson flashing, usbipd workflows)
        kmod # lsmod, modprobe, modinfo -- kernel module management
        dediprog-sf100 # dpcmd -- SPI flash programmer CLI (SF100/SF600/SF700)
        flashrom # Multi-programmer SPI flash tool (also supports Dediprog via -p dediprog)
      ];

      # === Hardware Programmer Access ===
      # Udev rules for team hardware programmers (non-root access via plugdev group)
      # - dediprog-sf100: SPI flash programmer
      # - openocd: ST-LINK/V2-1, CMSIS-DAP, J-Link, and other JTAG/SWD debug probes
      services.udev.packages = [ pkgs.dediprog-sf100 pkgs.openocd ];
      users.groups.plugdev = { };
    };
  };

  # ===========================================================================
  # Home Manager Module: home-dev-team (COMMON, platform-neutral)
  # ===========================================================================
  # The HM half of the dev-team tier, mirroring nixos.dev-team. Imports the
  # COMMON home-enterprise base (cross-platform) and adds the cross-platform dev
  # toolchain. Contains NO WSL-specific modules: windows-terminal moved to
  # home-wsl (wsl-enterprise.nix). WSL hosts import this + home-wsl; Darwin hosts
  # import this + home-darwin.
  #
  # Layers are convenience bundles, not gatekeepers: another team can
  # independently import claude-code, opencode, etc.; any host can cherry-pick.
  flake.modules.homeManager.home-dev-team = { config, lib, pkgs, ... }: {
    imports = [
      # COMMON enterprise HM bundle (home-default, shell, git, tmux, neovim,
      # terminal, shell-utils, system-tools, yazi, files, git-auth-helpers)
      inputs.self.modules.homeManager.home-enterprise
      # AI development tools
      inputs.self.modules.homeManager.claude-code
      inputs.self.modules.homeManager.opencode
      # Authentication
      inputs.self.modules.homeManager.gitlab-auth
      # Containers
      inputs.self.modules.homeManager.podman
      # Development toolchain
      inputs.self.modules.homeManager.development-tools
      # AWS CLI with Azure AD SSO
      inputs.self.modules.homeManager.awscli
      # JFrog CLI with Artifactory credential injection
      inputs.self.modules.homeManager.jfrog-cli
    ];

    # === Development Tools ===
    # Enable the development toolchain bundle (Python, Rust, Node, Go, etc.)
    # Imported above but mkEnableOption defaults to false.
    developmentTools.enable = lib.mkDefault true;

    # === Claude Code Configuration ===
    # Team-shared structural config: work account template + enterprise defaults.
    # Hosts ADD personal accounts (max, pro) via module system merging --
    # accounts is attrsOf submodule, so dev-team's work + host's max/pro coexist.
    #
    # Deployment-specific values (baseUrl, bitwarden items, modelMappings) must be
    # set by the host config or a private flake input overlay.
    programs.claude-code = inputs.self.lib.claudeCode.baseConfig // {
      defaultAccount = "work";
      accounts = inputs.self.lib.claudeCode.workAccount;
      statusline = inputs.self.lib.claudeCode.defaultStatusline;
      mcpServers = inputs.self.lib.claudeCode.defaultMcpServers;
      subAgents.custom = inputs.self.lib.claudeCode.defaultSubAgents;
    };

    # === OpenCode Configuration ===
    # Team-shared structural config: work account template + base settings.
    # Same merging pattern as claude-code for host personal accounts.
    #
    # Deployment-specific values (baseURL, bitwarden items, models) must be
    # set by the host config or a private flake input overlay.
    programs.opencode = inputs.self.lib.openCode.baseConfig // {
      defaultAccount = "work";
      accounts = inputs.self.lib.openCode.workAccount;
      provider = inputs.self.lib.openCode.baseConfig.provider
        // inputs.self.lib.openCode.workProvider;
      mcpServers = inputs.self.lib.openCode.defaultMcpServers;
      commands = inputs.self.lib.openCode.defaultCommands;
      agentFiles.custom = inputs.self.lib.openCode.defaultAgentFiles;
      skills = inputs.self.lib.openCode.defaultSkills;
      fileCommands.custom = inputs.self.lib.openCode.defaultFileCommands;
    };

    # === GitLab Authentication ===
    # Team GitLab config structure. Host must set gitAuth.gitlab.host to
    # their GitLab instance. Personal credential details (bitwarden item/field,
    # mode, apiUser) are also left to hosts.
    gitAuth.gitlab = {
      enable = lib.mkDefault true;
      cli.enable = lib.mkDefault true;
      # Don't pre-fill username in git credential config.
      # glab auth git-credential rejects username mismatches (compares against
      # glab's internal user from whoami). Without pre-filled username, glab
      # provides credentials directly. See CLAUDE.md glab credential helper fix.
      git.userName = lib.mkDefault null;
    };

    # === Podman Tools ===
    # Aliases default to docker→podman on Linux (platform-aware module).
    programs.podman-tools = {
      enable = lib.mkDefault true;
      enableCompose = lib.mkDefault true;
    };

    # === Tmux ===
    # Auto-reload tmux config when home-manager generation changes.
    programs.tmux.autoReload.enable = lib.mkDefault true;

    # === AWS CLI ===
    # Team-standard AWS CLI v2. Only the base CLI is enabled here;
    # azureAuth requires secretsManagement (Bitwarden) which is personal.
    # Hosts with secretsManagement enable azureAuth themselves.
    awscli.enable = lib.mkDefault true;

    # === JFrog CLI ===
    # Team-standard JFrog CLI. Host must set jfrogCli.host and
    # bitwarden item/field for their Artifactory instance.
    jfrogCli.enable = lib.mkDefault true;

    # === Team CLI Tools ===
    # Standalone CLI tools that don't warrant their own module.
    home.packages = with pkgs; [
      confluence-markdown-exporter # Confluence → Markdown bulk exporter
    ];

    # Does NOT configure (left to host):
    # - homeMinimal.username / homeMinimal.homeDirectory
    # - secretsManagement.* (personal bitwarden email)
    # - gitAuth.github.* (personal GitHub PATs)
    # - gitAuth.gitlab.bitwarden.* (personal credential details)
    # - gitAuth.gitlab.mode (bitwarden vs token -- personal choice)
    # - gitAuth.gitlab.cli.apiUser (personal GitLab username)
    # - awscli.azureAuth.* (requires secretsManagement for Bitwarden)
    # - jfrogCli.host (team Artifactory hostname)
    # - jfrogCli.bitwarden.* (personal credential details)
    #
    # WSL-only configuration (windowsTerminal appearance) moved to home-wsl.
  };
}
