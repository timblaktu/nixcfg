# modules/flake-parts/tests.nix
# Tier-0 eval-regression gate for NixOS + Home Manager configurations
#
# Plan 054 P5a consolidated this suite: per-host/-module standalone eval checks
# were folded into batched gates (regression-test, eval-hm-modules,
# eval-nixos-modules), the misnamed build-*-dryrun forcers were renamed to
# eval-*, the SSH-2223 triple was merged into one eval-wsl-settings-ssh-port,
# and pure no-op checks were deleted. See docs/VMTEST-TARGET-DESIGN.md §T0.
{ inputs, self, config, ... }:
let
  inherit (config.meta) username;
in
{
  perSystem = { config, self', inputs', pkgs, system, lib, ... }:
    let
      # Helper function to create a Home Manager ACTIVATION test.
      #
      # Unlike a plain eval (which only references string attrs and so forces
      # config *evaluation*), this forces the activationPackage — including the
      # generated activation-script.drv — to actually BUILD. That is the only
      # thing that exercises activation-string generators such as the
      # claude-code .claude.json `jq_args` block, where a shell-quoting bug
      # (an apostrophe in a hook body breaking a single-quoted JSON literal)
      # produced a bash syntax error that `nix flake check --no-build` and the
      # eval tests both passed straight over (Plan 046, 2026-06-25).
      #
      # CAVEAT: this check only provides protection when it is BUILT. The fast
      # commit gate runs `nix flake check --no-build`, which skips building
      # checks, so it will NOT catch activation-string regressions. Exercise it
      # via full `nix flake check` (final PR validation / CI) or directly:
      #   nix build '.#checks.x86_64-linux.activate-hm-thinky-nixos'
      mkHmActivationTest = name: configName:
        let
          activationPackage = self.homeConfigurations.${configName}.activationPackage;
        in
        pkgs.runCommand "activate-hm-${name}"
          {
            meta = {
              description = "Activation-script BUILD test for ${configName} HM configuration";
              maintainers = [ ];
              timeout = 300;
            };
            # Referencing the activationPackage as a build input forces it (and
            # the activation-script.drv it depends on) to build.
            inherit activationPackage;
          } ''
          echo "Building activation script for ${configName}..."
          test -x "$activationPackage/activate" \
            || (echo "❌ activation script missing or not executable" && exit 1)
          # Belt-and-suspenders: the activate script is bash; syntax-check it so
          # a future generator bug surfaces here as a clear failure, not a
          # mid-switch crash on the user's host.
          ${pkgs.bash}/bin/bash -n "$activationPackage/activate" \
            || (echo "❌ activation script has a shell syntax error" && exit 1)
          echo "✅ ${configName} activation script built and is syntactically valid"
          touch $out
        '';

      # Helper function to create module integration tests
      mkModuleTest = { name, description, hostName, attributes, checks }:
        pkgs.runCommand name
          ({
            meta = {
              inherit description;
              maintainers = [ ];
              timeout = 30;
            };
          } // attributes) ''
          echo "${description}..."
          # If we got here, the configuration evaluated successfully
          ${checks}
          echo "✅ ${description} passed"
          touch $out
        '';

      # === Tier-0 batched-eval helpers (Plan 054 P5a) ===

      # Force a single HM module to evaluate standalone against home-minimal.
      # Returns the config's home.homeDirectory so that referencing it forces
      # full evaluation. Used by the eval-hm-modules batch gate.
      forceHmModuleEval = module:
        let
          hmConfig = inputs.home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              self.modules.homeManager.home-minimal
              module
              {
                homeMinimal = {
                  username = "testuser";
                  homeDirectory = "/home/testuser";
                };
              }
            ];
            extraSpecialArgs = { inherit inputs; };
          };
        in
        hmConfig.config.home.homeDirectory;

      # Force a single NixOS layer module to evaluate standalone. `extraConfig`
      # carries the per-layer assertion setup each module needs. Returns the
      # config's system.stateVersion to force evaluation. Used by
      # eval-nixos-modules.
      forceNixosModuleEval = module: extraConfig:
        let
          nixosConfig = inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              module
              extraConfig
              { system.stateVersion = "24.11"; }
            ];
          };
        in
        nixosConfig.config.system.stateVersion;
    in
    {
      checks = {
        # Run all tests with: nix flake check
        # Run a specific test: nix build .#checks.x86_64-linux.regression-test

        # === MODULE INTEGRATION TESTS ===
        # Rewritten (Plan 054 P5a): asserts systemDefault.userGroups (contains
        # wheel) in addition to userName, instead of only echoing a constant.
        module-base-integration = mkModuleTest {
          name = "module-base-integration";
          description = "Testing system default module integration";
          hostName = "thinky-nixos";
          attributes = {
            inherit (self.nixosConfigurations.thinky-nixos.config.systemDefault) userName;
            userGroups = builtins.concatStringsSep " " self.nixosConfigurations.thinky-nixos.config.systemDefault.userGroups;
          };
          checks = ''
            [[ "$userName" == "${username}" ]] || (echo "❌ Username not ${username}" && exit 1)
            echo "$userGroups" | grep -qw "wheel" || (echo "❌ userGroups missing wheel (got: $userGroups)" && exit 1)
            echo "User name: $userName"
            echo "User groups: $userGroups"
          '';
        };

        # === BINFMT CROSS-ARCHITECTURE INTEGRATION TEST ===
        module-binfmt-integration = mkModuleTest {
          name = "module-binfmt-integration";
          description = "Testing binfmt cross-architecture build support";
          hostName = "thinky-nixos";
          attributes = {
            binfmtEnabled = if self.nixosConfigurations.thinky-nixos.config.wsl-settings.binfmt.enable then "1" else "0";
            emulatedSystems = builtins.concatStringsSep " " self.nixosConfigurations.thinky-nixos.config.boot.binfmt.emulatedSystems;
            preferStatic = if self.nixosConfigurations.thinky-nixos.config.boot.binfmt.preferStaticEmulators then "1" else "0";
            hasAarch64Reg = if (builtins.hasAttr "aarch64-linux" self.nixosConfigurations.thinky-nixos.config.boot.binfmt.registrations) then "1" else "0";
            matchCreds = if self.nixosConfigurations.thinky-nixos.config.boot.binfmt.registrations.aarch64-linux.matchCredentials then "1" else "0";
            extraPlatforms = builtins.concatStringsSep " " self.nixosConfigurations.thinky-nixos.config.nix.settings.extra-platforms;
          };
          checks = ''
            [[ "$binfmtEnabled" == "1" ]] || (echo "FAIL: binfmt not enabled" && exit 1)
            echo "binfmt enabled: $binfmtEnabled"

            echo "$emulatedSystems" | grep -q "aarch64-linux" || (echo "FAIL: aarch64-linux not in emulatedSystems" && exit 1)
            echo "emulated systems: $emulatedSystems"

            [[ "$preferStatic" == "1" ]] || (echo "FAIL: preferStaticEmulators not true" && exit 1)
            echo "prefer static emulators: $preferStatic"

            [[ "$hasAarch64Reg" == "1" ]] || (echo "FAIL: aarch64-linux registration missing" && exit 1)
            echo "aarch64-linux registration exists: $hasAarch64Reg"

            [[ "$matchCreds" == "1" ]] || (echo "FAIL: matchCredentials (C flag) not set" && exit 1)
            echo "matchCredentials (C flag): $matchCreds"

            echo "$extraPlatforms" | grep -q "aarch64-linux" || (echo "FAIL: aarch64-linux not in extra-platforms" && exit 1)
            echo "nix extra-platforms: $extraPlatforms"
          '';
        };

        # === WSL SETTINGS EVAL (merged SSH-2223 triple, Plan 054 P5a T0.5) ===
        # Folds ssh-service-configured + cross-module-wsl-base +
        # module-wsl-settings-integration into one eval keeping the invariants
        # worth having: openssh port == wsl sshPort, base userName == wsl
        # defaultUser (plus the ssh-enabled / port-2223 / wsl-enabled guards).
        eval-wsl-settings-ssh-port = pkgs.runCommand "eval-wsl-settings-ssh-port"
          {
            meta = {
              description = "Eval: WSL settings SSH/user invariants (openssh port == wsl sshPort; base userName == wsl defaultUser)";
              maintainers = [ ];
              timeout = 30;
            };
            enable = if self.nixosConfigurations.thinky-nixos.config.wsl.enable then "1" else "0";
            sshEnable = if self.nixosConfigurations.thinky-nixos.config.services.openssh.enable then "1" else "0";
            hostname = self.nixosConfigurations.thinky-nixos.config.wsl-settings.hostname;
            inherit (self.nixosConfigurations.thinky-nixos.config.systemDefault) userName;
            wslUser = self.nixosConfigurations.thinky-nixos.config.wsl.defaultUser;
            sshPort = toString self.nixosConfigurations.thinky-nixos.config.wsl-settings.sshPort;
            opensshPort = toString (builtins.head self.nixosConfigurations.thinky-nixos.config.services.openssh.ports);
          } ''
          echo "Evaluating WSL settings SSH/user invariants..."
          [[ "$enable" == "1" ]] || (echo "❌ WSL not enabled" && exit 1)
          [[ "$sshEnable" == "1" ]] || (echo "❌ SSH not enabled" && exit 1)
          [[ "$hostname" == "thinky-nixos" ]] || (echo "❌ hostname mismatch (got $hostname)" && exit 1)
          [[ "$sshPort" == "2223" ]] || (echo "❌ wsl-settings.sshPort != 2223 (got $sshPort)" && exit 1)
          [[ "$sshPort" == "$opensshPort" ]] || (echo "❌ openssh port ($opensshPort) != wsl sshPort ($sshPort)" && exit 1)
          [[ "$userName" == "$wslUser" ]] || (echo "❌ base userName ($userName) != wsl defaultUser ($wslUser)" && exit 1)
          echo "✅ WSL settings invariants hold: hostname=$hostname sshPort=$sshPort user=$userName"
          touch $out
        '';

        # === USER CONFIGURATION TESTS ===
        user-configured = pkgs.runCommand "user-configured"
          {
            meta = {
              description = "Verify primary user is properly configured";
              maintainers = [ ];
              timeout = 30;
            };
            # Force evaluation by referencing configuration attributes
            isNormalUser = if self.nixosConfigurations.thinky-nixos.config.users.users.${username}.isNormalUser then "1" else "0";
            extraGroups = builtins.concatStringsSep " " self.nixosConfigurations.thinky-nixos.config.users.users.${username}.extraGroups;
          } ''
          echo "Testing user ${username} configuration..."
          # If we got here, the configuration evaluated successfully
          [[ "$isNormalUser" == "1" ]] || (echo "❌ User not normal user" && exit 1)
          echo "$extraGroups" | grep -q "wheel" || (echo "❌ User not in wheel group" && exit 1)
          echo "User is normal user: $isNormalUser"
          echo "User groups: $extraGroups"
          echo "✅ User ${username} configuration passed"
          touch $out
        '';

        # === TOOL-AWARE SKILL INJECTION TESTS ===
        # Verify that program modules inject Claude Code skills when both
        # the program and claude-code are enabled (Plan 038)
        skill-injection-awscli =
          let
            hmConfig = (inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                self.modules.homeManager.home-minimal
                self.modules.homeManager.claude-code
                self.modules.homeManager.awscli
                {
                  homeMinimal = { username = "testuser"; homeDirectory = "/home/testuser"; };
                  programs.claude-code.enable = true;
                  programs.claude-code.accounts.max.enable = true;
                  awscli.enable = true;
                }
              ];
              extraSpecialArgs = { inherit inputs; };
            }).config;
            hasSkill = builtins.hasAttr "aws-cli" hmConfig.programs.claude-code.skills.custom;
            skillDesc = if hasSkill then hmConfig.programs.claude-code.skills.custom.aws-cli.description else "";
          in
          pkgs.runCommand "skill-injection-awscli"
            {
              meta = { description = "Verify awscli injects Claude Code skill"; timeout = 30; };
              inherit hasSkill skillDesc;
            } ''
            [[ "$hasSkill" == "1" ]] || (echo "FAIL: aws-cli skill not injected" && exit 1)
            [[ -n "$skillDesc" ]] || (echo "FAIL: aws-cli skill has empty description" && exit 1)
            echo "aws-cli skill injected with description: $skillDesc"
            touch $out
          '';

        skill-injection-glab =
          let
            hmConfig = (inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                self.modules.homeManager.home-minimal
                self.modules.homeManager.claude-code
                self.modules.homeManager.gitlab-auth
                self.modules.homeManager.secrets-management
                {
                  homeMinimal = { username = "testuser"; homeDirectory = "/home/testuser"; };
                  programs.claude-code.enable = true;
                  programs.claude-code.accounts.max.enable = true;
                  secretsManagement.enable = true;
                  gitAuth.gitlab.enable = true;
                }
              ];
              extraSpecialArgs = { inherit inputs; };
            }).config;
            hasSkill = builtins.hasAttr "glab-cli" hmConfig.programs.claude-code.skills.custom;
          in
          pkgs.runCommand "skill-injection-glab"
            {
              meta = { description = "Verify gitlab-auth injects Claude Code skill"; timeout = 30; };
              hasSkill = if hasSkill then "1" else "0";
            } ''
            [[ "$hasSkill" == "1" ]] || (echo "FAIL: glab-cli skill not injected" && exit 1)
            echo "glab-cli skill injected"
            touch $out
          '';

        skill-injection-pulumi =
          let
            hmConfig = (inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                self.modules.homeManager.home-minimal
                self.modules.homeManager.claude-code
                self.modules.homeManager.pulumi
                {
                  homeMinimal = { username = "testuser"; homeDirectory = "/home/testuser"; };
                  programs.claude-code.enable = true;
                  programs.claude-code.accounts.max.enable = true;
                  pulumi.enable = true;
                }
              ];
              extraSpecialArgs = { inherit inputs; };
            }).config;
            hasSkill = builtins.hasAttr "pulumi" hmConfig.programs.claude-code.skills.custom;
          in
          pkgs.runCommand "skill-injection-pulumi"
            {
              meta = { description = "Verify pulumi injects Claude Code skill"; timeout = 30; };
              hasSkill = if hasSkill then "1" else "0";
            } ''
            [[ "$hasSkill" == "1" ]] || (echo "FAIL: pulumi skill not injected" && exit 1)
            echo "pulumi skill injected"
            touch $out
          '';

        # Negative test: skills NOT injected when claude-code is disabled
        skill-injection-negative =
          let
            hmConfig = (inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                self.modules.homeManager.home-minimal
                self.modules.homeManager.claude-code
                self.modules.homeManager.awscli
                {
                  homeMinimal = { username = "testuser"; homeDirectory = "/home/testuser"; };
                  # claude-code NOT enabled, awscli IS enabled
                  awscli.enable = true;
                }
              ];
              extraSpecialArgs = { inherit inputs; };
            }).config;
            skillCount = builtins.length (builtins.attrNames hmConfig.programs.claude-code.skills.custom);
          in
          pkgs.runCommand "skill-injection-negative"
            {
              meta = { description = "Verify skills NOT injected when claude-code disabled"; timeout = 30; };
              skillCount = toString skillCount;
            } ''
            [[ "$skillCount" == "0" ]] || (echo "FAIL: $skillCount skills injected when claude-code disabled" && exit 1)
            echo "No skills injected when claude-code disabled (correct)"
            touch $out
          '';

        # === PACKAGE BUILD TESTS (T0.6) ===
        # Referencing packages in checks forces nix flake check to build them.
        # These verify that all custom packages build successfully.
        build-marker-pdf = self'.packages.marker-pdf;
        build-markitdown = self'.packages.markitdown;
        build-tomd = self'.packages.tomd;
        build-nixvim-anywhere = self'.packages.nixvim-anywhere;
        build-docling = self'.packages.docling;
        build-termux-claude-scripts = self'.packages.termux-claude-scripts;

        # === TOPLEVEL / TARBALL / IMAGE EVAL FORCERS (Plan 054 P5a T0.4) ===
        # Renamed from build-*-dryrun: they force a *deeper* eval (toplevel /
        # tarballBuilder / images attrset) than regression-test's stateVersion,
        # so they stay as per-host deep-eval gates. They never build — the old
        # build-* prefix was misleading.
        eval-thinky-nixos-toplevel = pkgs.runCommand "eval-thinky-nixos-toplevel"
          {
            meta = {
              description = "Force eval of thinky-nixos system.build.toplevel";
              maintainers = [ ];
              timeout = 30;
            };
            # Force full evaluation of the NixOS toplevel derivation (without building it)
            inherit (self.nixosConfigurations.thinky-nixos.config.system.build) toplevel;
          } ''
          echo "Testing thinky-nixos build evaluation..."
          echo "Toplevel derivation: $toplevel"
          echo "thinky-nixos build evaluation passed"
          touch $out
        '';

        eval-nixos-wsl-minimal-toplevel = pkgs.runCommand "eval-nixos-wsl-minimal-toplevel"
          {
            meta = {
              description = "Force eval of nixos-wsl-minimal system.build.toplevel";
              maintainers = [ ];
              timeout = 30;
            };
            # Force full evaluation of the NixOS toplevel derivation (without building it)
            inherit (self.nixosConfigurations.nixos-wsl-minimal.config.system.build) toplevel;
          } ''
          echo "Testing nixos-wsl-minimal build evaluation..."
          echo "Toplevel derivation: $toplevel"
          echo "nixos-wsl-minimal build evaluation passed"
          touch $out
        '';

        eval-nixos-dev-team-toplevel = pkgs.runCommand "eval-nixos-dev-team-toplevel"
          {
            meta = {
              description = "Force eval of nixos-dev-team system.build.toplevel";
              maintainers = [ ];
              timeout = 30;
            };
            inherit (self.nixosConfigurations.nixos-dev-team.config.system.build) toplevel;
          } ''
          echo "Testing nixos-dev-team build evaluation..."
          echo "Toplevel derivation: $toplevel"
          echo "nixos-dev-team build evaluation passed"
          touch $out
        '';

        eval-nixos-wsl-dev-team-tarball = pkgs.runCommand "eval-nixos-wsl-dev-team-tarball"
          {
            meta = {
              description = "Force eval of nixos-wsl-dev-team tarball builder";
              maintainers = [ ];
              timeout = 30;
            };
            inherit (self.nixosConfigurations.nixos-wsl-dev-team.config.system.build) tarballBuilder;
          } ''
          echo "Testing nixos-wsl-dev-team tarball builder evaluation..."
          echo "Tarball builder derivation: $tarballBuilder"
          echo "nixos-wsl-dev-team tarball builder evaluation passed"
          touch $out
        '';

        eval-thinky-nixos-tarball = pkgs.runCommand "eval-thinky-nixos-tarball"
          {
            meta = {
              description = "Force eval of thinky-nixos tarball builder";
              maintainers = [ ];
              timeout = 30;
            };
            inherit (self.nixosConfigurations.thinky-nixos.config.system.build) tarballBuilder;
          } ''
          echo "Testing thinky-nixos tarball builder evaluation..."
          echo "Tarball builder derivation: $tarballBuilder"
          echo "thinky-nixos tarball builder evaluation passed"
          touch $out
        '';

        # Regression guard: the setup-username bootstrap script must target the
        # user the image actually ships (wsl-settings.defaultUser). A hardcoded
        # "dev" previously made setup-username abort on every distributed image,
        # which ships "user". The script now derives its "from" user from the
        # same option; this check fails if that wiring ever regresses.
        wsl-dev-team-setup-username-user =
          let
            devTeamCfg = self.nixosConfigurations.nixos-wsl-dev-team.config;
            shippedUser = devTeamCfg.wsl-settings.defaultUser;
            setupUsername = lib.findFirst
              (p: (p.name or "") == "setup-username")
              null
              devTeamCfg.environment.systemPackages;
          in
          assert setupUsername != null;
          pkgs.runCommand "wsl-dev-team-setup-username-user"
            {
              meta = {
                description = "setup-username targets the shipped WSL default user";
                maintainers = [ ];
                timeout = 30;
              };
              inherit shippedUser;
              script = "${setupUsername}/bin/setup-username";
            } ''
            echo "Shipped default user: $shippedUser"
            grep -qF "BOOTSTRAP_USER=\"$shippedUser\"" "$script" \
              || (echo "❌ setup-username BOOTSTRAP_USER does not match wsl-settings.defaultUser ($shippedUser)" && exit 1)
            echo "✅ setup-username bootstraps from '$shippedUser'"
            touch $out
          '';

        # === IMAGE OUTPUTS EVALUATION TESTS ===
        # Verifies image.modules framework produces expected image attributes.
        # Forces eval of the images attrset without building. For a full VMA
        # build, use e.g.:
        #   nix build '.#nixosConfigurations.nixos-dev-team.config.system.build.images.proxmox'
        eval-images-dev-team = pkgs.runCommand "eval-images-dev-team"
          {
            meta = {
              description = "Force eval of nixos-dev-team image.modules (Proxmox VMA wiring)";
              maintainers = [ ];
              timeout = 30;
            };
            imageNames = builtins.concatStringsSep " " (builtins.attrNames self.nixosConfigurations.nixos-dev-team.config.system.build.images);
            hasProxmox = if (builtins.hasAttr "proxmox" self.nixosConfigurations.nixos-dev-team.config.system.build.images) then "1" else "0";
          } ''
          echo "Testing nixos-dev-team image outputs evaluation..."
          echo "Available images: $imageNames"
          [[ "$hasProxmox" == "1" ]] || (echo "FAIL: proxmox image missing from system.build.images" && exit 1)
          echo "Proxmox image present in system.build.images"
          echo "nixos-dev-team image outputs evaluation passed"
          touch $out
        '';

        eval-images-ec2 = pkgs.runCommand "eval-images-ec2"
          {
            meta = {
              description = "Force eval of nixos-dev-team-ec2 image.modules (Amazon AMI wiring)";
              maintainers = [ ];
              timeout = 30;
            };
            imageNames = builtins.concatStringsSep " " (builtins.attrNames self.nixosConfigurations.nixos-dev-team-ec2.config.system.build.images);
            hasAmazon = if (builtins.hasAttr "amazon" self.nixosConfigurations.nixos-dev-team-ec2.config.system.build.images) then "1" else "0";
          } ''
          echo "Testing nixos-dev-team-ec2 image outputs evaluation..."
          echo "Available images: $imageNames"
          [[ "$hasAmazon" == "1" ]] || (echo "FAIL: amazon image missing from system.build.images" && exit 1)
          echo "Amazon image present in system.build.images"
          echo "nixos-dev-team-ec2 image outputs evaluation passed"
          touch $out
        '';

        eval-images-graviton = pkgs.runCommand "eval-images-graviton"
          {
            meta = {
              description = "Force eval of nixos-dev-team-graviton image.modules (Amazon AMI wiring)";
              maintainers = [ ];
              timeout = 30;
            };
            imageNames = builtins.concatStringsSep " " (builtins.attrNames self.nixosConfigurations.nixos-dev-team-graviton.config.system.build.images);
            hasAmazon = if (builtins.hasAttr "amazon" self.nixosConfigurations.nixos-dev-team-graviton.config.system.build.images) then "1" else "0";
          } ''
          echo "Testing nixos-dev-team-graviton image outputs evaluation..."
          echo "Available images: $imageNames"
          [[ "$hasAmazon" == "1" ]] || (echo "FAIL: amazon image missing from system.build.images" && exit 1)
          echo "Amazon image present in system.build.images"
          echo "nixos-dev-team-graviton image outputs evaluation passed"
          touch $out
        '';

        # === FILES MODULE TEST (Plan 054 P5a, salvaged) ===
        # Rewritten from a tautological hasAttr check into one genuine
        # files-module assertion: build an HM config that uses the files
        # module's staticFiles path and assert the generated home.file exists
        # with the expected content. This exercises the real home.file
        # generation code in modules/programs/files/_homefiles-module.nix.
        files-module-test =
          let
            hmConfig = inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                self.modules.homeManager.home-minimal
                self.modules.homeManager.files
                {
                  homeMinimal = { username = "testuser"; homeDirectory = "/home/testuser"; };
                  homeFiles.enable = true;
                  homeFiles.staticFiles.glow = {
                    source = ../programs/files/files/glow.yml;
                    target = ".config/glow/glow.yml";
                  };
                }
              ];
              extraSpecialArgs = { inherit inputs; };
            };
            generatedSource = hmConfig.config.home.file.".config/glow/glow.yml".source;
          in
          pkgs.runCommand "files-module-test"
            {
              meta = {
                description = "Verify files module generates a real home.file with expected content";
                maintainers = [ ];
                timeout = 30;
              };
              # Referencing the generated source forces the files module's
              # home.file generation to evaluate.
              generatedSource = "${generatedSource}";
            } ''
            echo "Testing files module home.file generation..."
            test -e "$generatedSource" || (echo "❌ generated home.file source missing" && exit 1)
            grep -q "Glow configuration" "$generatedSource" \
              || (echo "❌ generated glow.yml missing expected content" && exit 1)
            echo "✅ files module generated .config/glow/glow.yml with expected content"
            touch $out
          '';

        # === TMUX PICKER SYNTAX (Plan 054 P5a, rewritten to actually assert) ===
        # Script location: modules/programs/tmux/files/tmux-session-picker
        tmux-picker-syntax =
          let
            tmuxPickerPath = ../programs + "/tmux/files/tmux-session-picker";
          in
          pkgs.runCommand "test-tmux-session-picker-syntax"
            {
              meta = {
                description = "Test tmux-session-picker bash syntax and single source of truth";
                maintainers = [ ];
                timeout = 30;
              };
            } ''
            echo "Testing tmux-session-picker single source of truth implementation..."

            # Test that the source file exists
            source_file="${tmuxPickerPath}"
            if [[ ! -f "$source_file" ]]; then
              echo "❌ Source file not found: $source_file"
              exit 1
            fi

            # Test that file is a valid bash script (shebang)
            if ! head -n 1 "$source_file" | grep -q "#!/usr/bin/env bash"; then
              echo "❌ Source file is not a valid bash script"
              exit 1
            fi

            # Actually syntax-check the script (this is the real assertion —
            # the previous version never ran bash -n).
            ${pkgs.bash}/bin/bash -n "$source_file" \
              || (echo "❌ tmux-session-picker has a bash syntax error" && exit 1)

            echo "✅ tmux-session-picker exists and passes bash -n syntax check"
            echo "✅ Script owned by tmux module in modules/programs/tmux/files/"
            touch $out
          '';

        # === OPENCODE CONFIGURATION TESTS ===
        # Test OpenCode JSON output is valid
        opencode-json-syntax =
          let
            hmConfig = self.homeConfigurations."${username}@thinky-nixos".config;
            # Build a sample config to test JSON generation
            sampleConfig = {
              "$schema" = "https://opencode.ai/config.json";
              model = hmConfig.programs.opencode-enhanced.defaultModel or "anthropic/claude-sonnet-4-5";
              mcp = hmConfig.programs.opencode-enhanced._internal.mcpServers or { };
              autoupdate = hmConfig.programs.opencode-enhanced.autoupdate or true;
              share = hmConfig.programs.opencode-enhanced.share or "manual";
            };
            configJson = builtins.toJSON sampleConfig;
          in
          pkgs.runCommand "opencode-json-syntax"
            {
              meta = {
                description = "Test OpenCode JSON configuration syntax";
                maintainers = [ ];
                timeout = 30;
              };
              passAsFile = [ "configContent" ];
              configContent = configJson;
            } ''
            echo "Testing OpenCode JSON syntax..."

            # Validate JSON with jq
            if ${pkgs.jq}/bin/jq '.' "$configContentPath" > /dev/null 2>&1; then
              echo "✅ JSON syntax is valid"
            else
              echo "❌ JSON syntax error"
              ${pkgs.jq}/bin/jq '.' "$configContentPath" || true
              exit 1
            fi

            # Check required structure
            schema=$(${pkgs.jq}/bin/jq -r '.["$schema"]' "$configContentPath")
            if [[ "$schema" == "https://opencode.ai/config.json" ]]; then
              echo "✅ Schema reference is correct"
            else
              echo "❌ Missing or incorrect schema reference"
              exit 1
            fi

            # Check model is set
            model=$(${pkgs.jq}/bin/jq -r '.model' "$configContentPath")
            if [[ "$model" != "null" && -n "$model" ]]; then
              echo "✅ Model configured: $model"
            else
              echo "❌ Model not configured"
              exit 1
            fi

            echo "✅ OpenCode JSON syntax validation passed"
            touch $out
          '';

        # Test MCP server configuration structure
        opencode-mcp-structure =
          let
            hmConfig = self.homeConfigurations."${username}@thinky-nixos".config;
            mcpServers = hmConfig.programs.opencode-enhanced._internal.mcpServers or { };
          in
          pkgs.runCommand "opencode-mcp-structure"
            {
              meta = {
                description = "Test OpenCode MCP server configuration structure";
                maintainers = [ ];
                timeout = 30;
              };
              passAsFile = [ "mcpContent" ];
              mcpContent = builtins.toJSON mcpServers;
            } ''
            echo "Testing OpenCode MCP server structure..."

            # Parse MCP config
            servers=$(${pkgs.jq}/bin/jq -r 'keys[]' "$mcpContentPath" 2>/dev/null || echo "")

            for server in $servers; do
              echo "Checking server: $server"

              # Each server must have 'type' field
              serverType=$(${pkgs.jq}/bin/jq -r --arg s "$server" '.[$s].type // "missing"' "$mcpContentPath")
              if [[ "$serverType" == "missing" ]]; then
                echo "❌ Server $server missing 'type' field"
                exit 1
              fi
              echo "  ✅ type: $serverType"

              # Local servers must have 'command' array
              if [[ "$serverType" == "local" ]]; then
                cmdLen=$(${pkgs.jq}/bin/jq -r --arg s "$server" '.[$s].command | length' "$mcpContentPath")
                if [[ "$cmdLen" -eq 0 ]]; then
                  echo "❌ Server $server has empty command"
                  exit 1
                fi
                echo "  ✅ command has $cmdLen elements"
              fi

              # Check enabled field (OpenCode uses 'enabled' not 'enable')
              enabled=$(${pkgs.jq}/bin/jq -r --arg s "$server" '.[$s].enabled // "missing"' "$mcpContentPath")
              if [[ "$enabled" != "true" && "$enabled" != "false" && "$enabled" != "missing" ]]; then
                echo "❌ Server $server has invalid 'enabled' value: $enabled"
                exit 1
              fi
              echo "  ✅ enabled: $enabled"
            done

            if [[ -z "$servers" ]]; then
              echo "⚠️  No MCP servers configured (this may be intentional)"
            else
              echo "✅ All MCP server configurations valid"
            fi

            touch $out
          '';

        # === STATIC ANALYSIS & LINTING ===
        # These checks run source-level analysis tools. They require a build to
        # execute the tool but are logically code quality checks.
        lint-formatting = pkgs.runCommand "lint-formatting"
          {
            meta = {
              description = "Check nixpkgs-fmt formatting on all .nix files";
              maintainers = [ ];
              timeout = 120;
            };
            nativeBuildInputs = [ pkgs.nixpkgs-fmt pkgs.findutils ];
            src = self;
          } ''
          cd $src
          find . -name '*.nix' -not -path './.git/*' -not -path './result*' -print0 \
            | xargs -0 nixpkgs-fmt --check
          touch $out
        '';

        lint-statix = pkgs.runCommand "lint-statix"
          {
            meta = {
              description = "Check Nix anti-patterns with statix";
              maintainers = [ ];
              timeout = 120;
            };
            nativeBuildInputs = [ pkgs.statix ];
            src = self;
          } ''
          cd $src
          statix check .
          touch $out
        '';

        lint-deadnix = pkgs.runCommand "lint-deadnix"
          {
            meta = {
              description = "Check for dead code with deadnix";
              maintainers = [ ];
              timeout = 120;
            };
            nativeBuildInputs = [ pkgs.deadnix ];
            src = self;
          } ''
          cd $src
          deadnix --no-lambda-pattern-names --no-underscore --fail .
          touch $out
        '';

        # Validate UTF-8 BOM on PowerShell scripts.
        # PS 5.1 reads no-BOM files as Windows-1252, corrupting non-ASCII
        # characters (em dashes become smart quotes = string delimiters).
        # See .gitattributes for full explanation.
        lint-ps1-encoding = pkgs.runCommand "lint-ps1-encoding"
          {
            meta = {
              description = "Verify PowerShell scripts have UTF-8 BOM for PS 5.1 compat";
              maintainers = [ ];
              timeout = 10;
            };
            src = self;
          } ''
          # Use a status file since pipeline subshells can't set parent variables
          status=$(mktemp)
          echo "ok" > "$status"
          find $src -name '*.ps1' -not -path '*/.git/*' -exec sh -c '
            statusfile="$1"; shift
            for f; do
              bom=$(head -c 3 "$f" | od -A n -t x1 | tr -d " \n")
              if [ "$bom" != "efbbbf" ]; then
                echo "FAIL: $f missing UTF-8 BOM (found: $bom)"
                echo "fail" > "$statusfile"
              fi
            done
          ' _ "$status" {} +
          if [ "$(cat "$status")" = "fail" ]; then
            echo ""
            echo "PowerShell scripts must have UTF-8 BOM for Windows PowerShell 5.1."
            echo "Without BOM, PS 5.1 reads as Windows-1252 and misinterprets non-ASCII"
            echo "characters as string delimiters, causing silent parse failures."
            echo "Fix: printf '\\xef\\xbb\\xbf' | cat - file > tmp && mv tmp file"
            rm -f "$status"
            exit 1
          fi
          rm -f "$status"
          echo "All .ps1 files have UTF-8 BOM"
          touch $out
        '';

        # === MODULE ISOLATION EVAL GATES (Plan 054 P5a T0.2 / T0.3) ===
        # Prove that individual modules evaluate standalone without a host
        # config — the property that catches breakage in modules no tested host
        # enables (e.g. corp-only modules). Batched into one gate per module
        # class (was: 20 eval-hm-module-* + 6 eval-nixos-module-*). Nix names
        # the broken module on failure.

        # Every HM module forced to evaluate standalone against home-minimal.
        eval-hm-modules =
          let
            hmModules = {
              inherit (self.modules.homeManager)
                claude-code development-tools esp-idf files git git-auth-helpers
                github-auth gitlab-auth neovim onedrive opencode podman
                secrets-management shell shell-utils system-tools terminal tmux
                windows-terminal yazi;
            };
            forced = lib.mapAttrsToList
              (name: module: "${name}:${forceHmModuleEval module}")
              hmModules;
          in
          pkgs.runCommand "eval-hm-modules"
            {
              meta = {
                description = "Isolation eval gate: all HM modules evaluate standalone";
                maintainers = [ ];
                timeout = 120;
              };
              forced = builtins.concatStringsSep " " forced;
            } ''
            echo "All HM modules evaluate standalone:"
            for m in $forced; do echo "  $m"; done
            touch $out
          '';

        # Every NixOS system-layer module forced to evaluate standalone, with
        # its required per-layer assertion setup carried as extraConfig.
        eval-nixos-modules =
          let
            nixosModules = {
              system-minimal = {
                module = self.modules.nixos.system-minimal;
                extraConfig = { };
              };
              system-default = {
                module = self.modules.nixos.system-default;
                # system-default asserts userName != ""
                extraConfig = { systemDefault.userName = "testuser"; };
              };
              system-cli = {
                module = self.modules.nixos.system-cli;
                # system-cli imports system-default which asserts userName != ""
                extraConfig = { systemDefault.userName = "testuser"; };
              };
              system-desktop = {
                module = self.modules.nixos.system-desktop;
                # system-desktop imports system-cli → system-default
                extraConfig = { systemDefault.userName = "testuser"; };
              };
              secrets-management = {
                module = self.modules.nixos.secrets-management;
                # secrets-management sets sops.* options, which require sops-nix
                extraConfig = { imports = [ inputs.sops-nix.nixosModules.sops ]; };
              };
              wsl = {
                module = self.modules.nixos.wsl;
                extraConfig = {
                  # WSL module requires system-cli co-imported (for containerRuntime.enablePodman)
                  imports = [ self.modules.nixos.system-cli ];
                  # system-cli imports system-default which asserts userName != ""
                  systemDefault.userName = "testuser";
                  # WSL module asserts hostname, defaultUser, and sshPort
                  wsl-settings = {
                    hostname = "test-wsl";
                    defaultUser = "testuser";
                    sshPort = 2223;
                  };
                };
              };
            };
            forced = lib.mapAttrsToList
              (name: spec: "${name}:${forceNixosModuleEval spec.module spec.extraConfig}")
              nixosModules;
          in
          pkgs.runCommand "eval-nixos-modules"
            {
              meta = {
                description = "Isolation eval gate: all NixOS system-layer modules evaluate standalone";
                maintainers = [ ];
                timeout = 120;
              };
              forced = builtins.concatStringsSep " " forced;
            } ''
            echo "All NixOS layer modules evaluate standalone:"
            for m in $forced; do echo "  $m"; done
            touch $out
          '';

        # === HM ACTIVATION-SCRIPT BUILD TESTS (T0.7, build-tier) ===
        # thinky-nixos enables programs.claude-code with accounts + categorized
        # hooks, so building its activationPackage exercises the .claude.json
        # activation generator and guards the shell-quoting bug class (Plan 046).
        # Only meaningful when BUILT — `nix flake check --no-build` skips these;
        # run full `nix flake check` or
        #   nix build '.#checks.x86_64-linux.activate-hm-thinky-nixos'
        activate-hm-thinky-nixos = mkHmActivationTest "thinky-nixos" "${username}@thinky-nixos";
        # Second host to widen the activation-build coverage pattern (T0.7).
        activate-hm-nixvim-minimal = mkHmActivationTest "nixvim-minimal" "${username}@nixvim-minimal";

        # === REGRESSION TEST (Plan 054 P5a T0.1 — the single host/config eval batch) ===
        # Forces evaluation of ALL NixOS and HM configs. Absorbs the 12
        # standalone host/config evals plus config-snapshot-validation
        # (stateVersion == "24.11" equality assertions).
        regression-test = pkgs.runCommand "regression-test"
          {
            meta = {
              description = "Verify all NixOS and Home Manager configurations evaluate";
              maintainers = [ ];
              timeout = 120;
            };
            # Force evaluation of all NixOS configurations
            nixosThinky = self.nixosConfigurations.thinky-nixos.config.system.stateVersion;
            nixosPotato = self.nixosConfigurations.potato.config.system.stateVersion;
            nixosMbp = self.nixosConfigurations.mbp.config.system.stateVersion;
            nixosWslMinimal = self.nixosConfigurations.nixos-wsl-minimal.config.system.stateVersion;
            nixosWslDevTeam = self.nixosConfigurations.nixos-wsl-dev-team.config.system.stateVersion;
            nixosDevTeam = self.nixosConfigurations.nixos-dev-team.config.system.stateVersion;
            nixosDevTeamEc2 = self.nixosConfigurations.nixos-dev-team-ec2.config.system.stateVersion;
            nixosDevTeamGraviton = self.nixosConfigurations.nixos-dev-team-graviton.config.system.stateVersion;
            # Force evaluation of all 4 x86_64-linux Home Manager configurations
            # (homeDirectory + username, for parity with the folded eval-hm-* checks)
            hmThinky = self.homeConfigurations."${username}@thinky-nixos".config.home.homeDirectory;
            hmThinkyUser = self.homeConfigurations."${username}@thinky-nixos".config.home.username;
            hmUbuntu = self.homeConfigurations."${username}@thinky-ubuntu".config.home.homeDirectory;
            hmUbuntuUser = self.homeConfigurations."${username}@thinky-ubuntu".config.home.username;
            hmMbp = self.homeConfigurations."${username}@mbp".config.home.homeDirectory;
            hmMbpUser = self.homeConfigurations."${username}@mbp".config.home.username;
            hmNixvim = self.homeConfigurations."${username}@nixvim-minimal".config.home.homeDirectory;
            hmNixvimUser = self.homeConfigurations."${username}@nixvim-minimal".config.home.username;
          } ''
          echo "Regression test: evaluating all configurations..."
          echo ""
          echo "NixOS configurations:"
          echo "  thinky-nixos:            stateVersion=$nixosThinky"
          echo "  potato:                  stateVersion=$nixosPotato"
          echo "  mbp:                     stateVersion=$nixosMbp"
          echo "  nixos-wsl-minimal:       stateVersion=$nixosWslMinimal"
          echo "  nixos-wsl-dev-team:      stateVersion=$nixosWslDevTeam"
          echo "  nixos-dev-team:          stateVersion=$nixosDevTeam"
          echo "  nixos-dev-team-ec2:      stateVersion=$nixosDevTeamEc2"
          echo "  nixos-dev-team-graviton: stateVersion=$nixosDevTeamGraviton"
          echo ""
          echo "Home Manager configurations:"
          echo "  ${username}@thinky-nixos:   homeDir=$hmThinky user=$hmThinkyUser"
          echo "  ${username}@thinky-ubuntu:  homeDir=$hmUbuntu user=$hmUbuntuUser"
          echo "  ${username}@mbp:            homeDir=$hmMbp user=$hmMbpUser"
          echo "  ${username}@nixvim-minimal: homeDir=$hmNixvim user=$hmNixvimUser"
          echo ""
          # Folded config-snapshot-validation: stateVersion baseline equality.
          for pair in \
            "thinky-nixos:$nixosThinky" \
            "potato:$nixosPotato" \
            "nixos-wsl-minimal:$nixosWslMinimal" \
            "mbp:$nixosMbp"; do
            host="''${pair%%:*}"
            actual="''${pair#*:}"
            if [[ "$actual" != "24.11" ]]; then
              echo "❌ $host: stateVersion mismatch! Expected 24.11, got $actual"
              exit 1
            fi
            echo "✅ $host: stateVersion $actual matches baseline"
          done
          echo ""
          echo "All configurations evaluated successfully"
          touch $out
        '';
      };
    };
}
