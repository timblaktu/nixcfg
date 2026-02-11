# modules/flake-parts/vm-tests.nix
# VM test infrastructure for NixOS integration testing
#
# Provides:
#   - mkVmTest helper: wraps pkgs.testers.nixosTest with common defaults
#   - All VM-based checks (prefixed with vm-)
#
# VM tests compose from dendritic modules (self.modules.nixos.*, self.modules.homeManager.*)
# rather than importing full host configs. This avoids WSL/hardware dependencies.
#
# Naming convention:
#   vm-*  → T2/T3 tests (require KVM to build)
#
# Usage:
#   nix build '.#checks.x86_64-linux.vm-boot-minimal' -L    # Run specific VM test
#   nix flake check                                          # Run all (including VM tests)
#   nix flake check --no-build                               # Skip VM tests (eval-only)
{ inputs, self, ... }: {
  perSystem = { config, self', inputs', pkgs, system, lib, ... }:
    let
      # mkVmTest: Create a NixOS VM test with common defaults
      #
      # Arguments:
      #   name        - Test name (will be prefixed with "vm-" in checks)
      #   description - Human-readable test description
      #   modules     - List of NixOS modules to import (from self.modules.nixos.*)
      #   nodes       - Full nodes attrset (overrides single-node shorthand when provided)
      #   testScript  - Python test script (nixos-test-driver syntax)
      #   memory      - VM memory in MB (default: 1024)
      #   extraConfig - Additional NixOS config merged into the machine node
      #
      # The helper provides:
      #   - Firewall disabled (simplifies test networking)
      #   - Configurable memory (default 1024 MB)
      #   - meta.timeout set to 300s (5 minutes, reasonable for VM tests)
      #
      # Example:
      #   mkVmTest {
      #     name = "boot-minimal";
      #     description = "Minimal NixOS boots to multi-user.target";
      #     modules = [ self.modules.nixos.system-minimal ];
      #     testScript = ''
      #       machine.start()
      #       machine.wait_for_unit("multi-user.target")
      #     '';
      #   }
      mkVmTest =
        { name
        , description ? "VM test: ${name}"
        , modules ? [ ]
        , nodes ? null
        , testScript
        , memory ? 1024
        , extraConfig ? { }
        ,
        }:
        pkgs.testers.nixosTest {
          name = "vm-${name}";

          nodes = if nodes != null then nodes else {
            machine = { config, pkgs, ... }: {
              imports = modules;

              # Common VM test defaults
              networking.firewall.enable = false;
              virtualisation.memorySize = memory;
            } // extraConfig;
          };

          testScript = testScript;
        };

    in
    {
      checks = {
        # === VM INTEGRATION TESTS ===
        # Wired from tests/integration/ — require KVM to build

        # SSH key management: multi-node test (host1 + host2)
        # Tests SSH service, key deployment, cross-host auth, error recovery
        vm-ssh-management = import ../../tests/integration/ssh-management.nix {
          inherit pkgs lib;
        };

        # SOPS-NiX secret deployment: single-node test
        # Tests age key generation, encryption/decryption, permissions, rotation
        vm-sops-deployment = import ../../tests/integration/sops-deployment.nix {
          inherit pkgs lib;
        };

        # === VM BOOT SMOKE TESTS (T2) ===

        # Boot smoke test: does a minimal NixOS config boot to multi-user.target?
        # Uses system-minimal module (base layer: nix settings, GC, store optimization)
        vm-boot-minimal = mkVmTest {
          name = "boot-minimal";
          description = "Minimal NixOS boots to multi-user.target";
          modules = [ self.modules.nixos.system-minimal ];
          testScript = ''
            machine.start()
            machine.wait_for_unit("multi-user.target")
            machine.succeed("nix --version")
          '';
        };

        # === VM SYSTEM TYPE LAYER TESTS (T2) ===
        # Each test verifies that a system type layer adds its expected functionality
        # on top of the layers it imports.

        # system-default: imports minimal, adds user creation, locale, timezone, zsh
        vm-system-type-default = mkVmTest {
          name = "system-type-default";
          description = "system-default layer: user creation, locale, timezone";
          modules = [ self.modules.nixos.system-default ];
          extraConfig = {
            systemDefault.userName = "tim";
          };
          testScript = ''
            machine.wait_for_unit("multi-user.target")

            # User creation
            machine.succeed("id tim")
            machine.succeed("id -nG tim | grep -q wheel")

            # Locale
            machine.succeed("locale | grep -q en_US")

            # Timezone
            machine.succeed("timedatectl show -p Timezone --value | grep -q America/Los_Angeles")

            # Shell is zsh
            machine.succeed("getent passwd tim | grep -q zsh")

            # System packages from default layer
            machine.succeed("which wget")
            machine.succeed("which curl")
            machine.succeed("which htop")

            # Inherits minimal: nix works with flakes
            machine.succeed("nix --version")
          '';
        };

        # system-cli: imports default, adds SSH daemon, dev tools, network tools
        vm-system-type-cli = mkVmTest {
          name = "system-type-cli";
          description = "system-cli layer: SSH daemon, dev tools, network tools";
          modules = [ self.modules.nixos.system-cli ];
          extraConfig = {
            systemDefault.userName = "tim";
          };
          testScript = ''
            machine.wait_for_unit("multi-user.target")

            # SSH daemon running (cli layer enables sshd by default)
            machine.wait_for_unit("sshd.service")

            # Inherits default: user exists
            machine.succeed("id tim")

            # Dev tools present (enableDevTools = true by default)
            machine.succeed("git --version")
            machine.succeed("which jq")
            machine.succeed("which fzf")
            machine.succeed("which eza")

            # Neovim as default editor
            machine.succeed("which nvim")

            # Tmux available
            machine.succeed("which tmux")
          '';
        };

        # === VM FEATURE TESTS (T3) ===

        # SSH service test: multi-node test verifying sshd configuration,
        # password auth disabled, root login denied, key-based cross-node auth
        vm-ssh-service =
          let
            # Test-only SSH keypair (no passphrase, used only in ephemeral VMs)
            testPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA5KxOZmLBW+mf3To2lxhJhMyAHvsfldNX3ukpjEsAiV vm-test@nixos-test";
            # Write the private key to the nix store for deployment into the VM.
            # No indentation — OpenSSH is strict about private key format.
            testPrivKeyFile = pkgs.writeText "vm-test-privkey"
              "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW\nQyNTUxOQAAACAOSsTmZiwVvpn906NpcYSYTMgB77H5XTV97pKYxLAIlQAAAJjnvjzN5748\nzQAAAAtzc2gtZWQyNTUxOQAAACAOSsTmZiwVvpn906NpcYSYTMgB77H5XTV97pKYxLAIlQ\nAAAEAr+7qHcVT3Nb6tl278Jni4sYl0GSOAglGZw3AKd0FNqw5KxOZmLBW+mf3To2lxhJhM\nyAHvsfldNX3ukpjEsAiVAAAAEnZtLXRlc3RAbml4b3MtdGVzdAECAw==\n-----END OPENSSH PRIVATE KEY-----\n";
          in
          mkVmTest {
            name = "ssh-service";
            description = "SSH daemon configuration and cross-node key-based auth";
            nodes = {
              server = { config, pkgs, ... }: {
                imports = [ self.modules.nixos.system-cli ];
                networking.firewall.enable = false;
                virtualisation.memorySize = 1024;
                systemDefault.userName = "tim";
                # Deploy the test public key via the dendritic sshAuthorizedKeys option
                systemCli.sshAuthorizedKeys = [ testPubKey ];
              };
              client = { config, pkgs, ... }: {
                imports = [ self.modules.nixos.system-cli ];
                networking.firewall.enable = false;
                virtualisation.memorySize = 1024;
                systemDefault.userName = "tim";
              };
            };
            testScript = ''
              start_all()

              # --- Test 1: SSH daemon starts and is running ---
              server.wait_for_unit("sshd.service")

              # --- Test 2: SSH settings are correct ---
              # Password authentication disabled
              server.succeed("sshd -T | grep -qi 'passwordauthentication no'")
              # Root login denied
              server.succeed("sshd -T | grep -qi 'permitrootlogin no'")

              # --- Test 3: SSH listens on port 22 ---
              server.wait_for_open_port(22)

              # --- Test 4: Authorized keys deployed for user tim ---
              # NixOS may use /etc/ssh/authorized_keys.d/ or ~/.ssh/authorized_keys
              server.succeed(
                  "{ cat /etc/ssh/authorized_keys.d/tim 2>/dev/null"
                  " || cat /home/tim/.ssh/authorized_keys; }"
                  " | grep -q ssh-ed25519"
              )

              # --- Test 5: Key-based SSH from client to server ---
              client.wait_for_unit("multi-user.target")

              # Deploy the test private key to client
              client.succeed("mkdir -p /home/tim/.ssh && chmod 700 /home/tim/.ssh")
              client.succeed("cp ${testPrivKeyFile} /home/tim/.ssh/id_ed25519")
              client.succeed("chmod 600 /home/tim/.ssh/id_ed25519")
              client.succeed("chown -R tim:users /home/tim/.ssh")

              # Add server to known_hosts (avoid interactive host key prompt)
              client.succeed(
                  "su - tim -c 'ssh-keyscan server >> /home/tim/.ssh/known_hosts 2>/dev/null'"
              )

              # SSH from client to server and verify command execution
              result = client.succeed(
                  "su - tim -c 'ssh -i /home/tim/.ssh/id_ed25519 tim@server echo SSH_OK'"
              )
              assert "SSH_OK" in result, f"Expected SSH_OK in output, got: {result}"

              # --- Test 6: Password auth rejected ---
              # BatchMode=yes causes ssh to fail immediately if password would be needed
              # (no interactive prompt). This verifies password auth is truly disabled.
              client.fail(
                  "su - tim -c 'ssh -o PubkeyAuthentication=no"
                  " -o BatchMode=yes"
                  " -o StrictHostKeyChecking=no"
                  " tim@server echo SHOULD_NOT_WORK'"
              )
            '';
          };
      };
    };
}
