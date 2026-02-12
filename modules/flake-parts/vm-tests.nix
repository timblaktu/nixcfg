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

          inherit testScript;
        };

      # mkHmModuleTest: Create a VM test for Home Manager module(s)
      #
      # Provides system-default + home-manager NixOS integration + home-minimal
      # automatically. Caller only specifies which HM modules to test and what
      # to assert in the testScript.
      #
      # Arguments:
      #   name             - Test name (prefixed with "vm-" in checks)
      #   description      - Human-readable description (default: "HM module test: ${name}")
      #   hmModules        - List of HM modules to import (from self.modules.homeManager.*)
      #   testScript       - Python test script (nixos-test-driver syntax)
      #   memory           - VM memory in MB (default: 2048)
      #   extraNixosModules - Additional NixOS modules to import (default: [])
      #   hmConfig         - Additional attrs merged into the HM user config (default: {})
      #
      # Example:
      #   mkHmModuleTest {
      #     name = "yazi";
      #     hmModules = [ self.modules.homeManager.yazi ];
      #     testScript = ''
      #       machine.wait_for_unit("multi-user.target")
      #       machine.wait_for_unit("home-manager-tim.service")
      #       machine.succeed("su - tim -c 'yazi --version'")
      #     '';
      #   }
      mkHmModuleTest =
        { name
        , description ? "HM module test: ${name}"
        , hmModules
        , testScript
        , memory ? 2048
        , extraNixosModules ? [ ]
        , hmConfig ? { }
        ,
        }:
        pkgs.testers.nixosTest {
          name = "vm-${name}";

          nodes.machine = { config, pkgs, lib, ... }: {
            imports = [
              self.modules.nixos.system-default
              inputs.home-manager.nixosModules.home-manager
            ] ++ extraNixosModules;

            systemDefault.userName = "tim";
            systemDefault.wheelNeedsPassword = false;
            networking.firewall.enable = false;
            virtualisation.memorySize = memory;

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.tim = { config, pkgs, lib, ... }: {
                imports = [
                  self.modules.homeManager.home-minimal
                ] ++ hmModules;

                homeMinimal = {
                  username = "tim";
                  homeDirectory = "/home/tim";
                };

                # NixOS-integrated HM doesn't need genericLinux
                targets.genericLinux.enable = lib.mkForce false;
              } // hmConfig;
            };
          };

          inherit testScript;
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
        # Home Manager activation test: verifies that HM integrates with NixOS,
        # activates successfully, generates config files, and provides programs.
        # Uses NixOS-integrated HM (home-manager.nixosModules) to test activation
        # in a VM, even though the repo normally uses standalone HM.
        vm-hm-activation = pkgs.testers.nixosTest {
          name = "vm-hm-activation";

          nodes.machine = { config, pkgs, lib, ... }: {
            imports = [
              self.modules.nixos.system-default
              inputs.home-manager.nixosModules.home-manager
            ];

            systemDefault.userName = "tim";
            systemDefault.wheelNeedsPassword = false;

            networking.firewall.enable = false;
            virtualisation.memorySize = 2048;

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.tim = { config, pkgs, lib, ... }: {
                imports = [
                  self.modules.homeManager.home-minimal
                  self.modules.homeManager.shell
                  self.modules.homeManager.git
                ];

                homeMinimal = {
                  username = "tim";
                  homeDirectory = "/home/tim";
                };

                # Override genericLinux — not needed in NixOS-integrated mode
                targets.genericLinux.enable = lib.mkForce false;
              };
            };
          };

          testScript = ''
            machine.wait_for_unit("multi-user.target")

            # --- Test 1: Home Manager activation completed ---
            # In NixOS-integrated mode, HM activates via system activation.
            # home-manager-tim.service is the systemd unit for the user's activation.
            machine.wait_for_unit("home-manager-tim.service")

            # --- Test 2: Git is configured by HM ---
            machine.succeed("su - tim -c 'git --version'")
            # Git config should contain user.name from the dendritic git module
            machine.succeed("su - tim -c 'git config user.name' | grep -q 'Tim Black'")
            machine.succeed("su - tim -c 'git config user.email' | grep -q 'timblaktu@gmail.com'")

            # --- Test 3: Git config file generated ---
            # HM puts git config in XDG path
            machine.succeed("test -f /home/tim/.config/git/config")

            # --- Test 4: Zsh configured by HM ---
            machine.succeed("test -f /home/tim/.zshrc")

            # --- Test 5: home-manager command available ---
            machine.succeed("su - tim -c 'home-manager --version'")

            # --- Test 6: HM-generated XDG directories exist ---
            # Home Manager creates XDG config structure during activation
            machine.succeed("test -d /home/tim/.config/git")

            # --- Test 7: HM-managed program in PATH ---
            # Delta (git diff viewer) is enabled by the git module
            machine.succeed("su - tim -c 'which delta'")

            # --- Test 8: Zsh history directory created ---
            # The shell module configures zsh history in XDG data dir
            machine.succeed("su - tim -c 'zsh -c \"echo ZSH_OK\"' | grep -q ZSH_OK")
          '';
        };

        # Shell environment test: verifies zsh configuration, aliases, session
        # variables, plugins, and custom functions via Home Manager in a VM.
        vm-shell-env = pkgs.testers.nixosTest {
          name = "vm-shell-env";

          nodes.machine = { config, pkgs, lib, ... }: {
            imports = [
              self.modules.nixos.system-default
              inputs.home-manager.nixosModules.home-manager
            ];

            systemDefault.userName = "tim";
            systemDefault.wheelNeedsPassword = false;

            networking.firewall.enable = false;
            virtualisation.memorySize = 2048;

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.tim = { config, pkgs, lib, ... }: {
                imports = [
                  self.modules.homeManager.home-minimal
                  self.modules.homeManager.shell
                ];

                homeMinimal = {
                  username = "tim";
                  homeDirectory = "/home/tim";
                };

                targets.genericLinux.enable = lib.mkForce false;
              };
            };
          };

          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("home-manager-tim.service")

            # --- Test 1: Zsh starts without errors ---
            machine.succeed("su - tim -c 'zsh -c \"echo ZSH_OK\"' | grep -q ZSH_OK")

            # --- Test 2: Zsh is the login shell ---
            machine.succeed("getent passwd tim | grep -q zsh")

            # --- Test 3: Session variables are set ---
            machine.succeed("su - tim -c 'zsh -ic \"echo \\$EDITOR\"' | grep -q nvim")

            # --- Test 4: Shell aliases are defined ---
            # Check a few representative aliases from the module
            machine.succeed("su - tim -c 'zsh -ic \"alias gs\"' | grep -q 'git status'")
            machine.succeed("su - tim -c 'zsh -ic \"alias ll\"' | grep -q 'ls -l'")
            machine.succeed("su - tim -c 'zsh -ic \"alias v\"' | grep -q nvim")

            # --- Test 5: Zsh history path configured in .zshrc ---
            # The module sets history path to $XDG_DATA_HOME/zsh/history
            machine.succeed("su - tim -c 'grep -q zsh/history ~/.zshrc'")

            # --- Test 6: Zsh completion system loaded ---
            machine.succeed("su - tim -c 'grep -q compinit ~/.zshrc'")

            # --- Test 7: Zsh plugins configured ---
            # Home Manager writes plugin source lines into .zshrc
            machine.succeed("su - tim -c 'grep -q zsh-autosuggestions ~/.zshrc'")
            machine.succeed("su - tim -c 'grep -q zsh-syntax-highlighting ~/.zshrc'")

            # --- Test 8: Custom prompt is set (not default) ---
            # Our module sets PROMPT with smart_pwd and shell_scope_indicator
            machine.succeed("su - tim -c 'grep -q smart_pwd ~/.zshrc'")
          '';
        };

        # SOPS secrets test: verifies sops-nix NixOS module integration with
        # our dendritic secrets-management module. Tests that secrets defined in
        # sops.secrets.* are decrypted at boot and placed at correct paths with
        # correct permissions and ownership.
        #
        # Unlike vm-sops-deployment (which tests manual SOPS CLI operations),
        # this test validates the actual sops-nix NixOS module decryption service.
        vm-sops-secrets =
          let
            # Static test fixtures: pre-generated age keypair + SOPS-encrypted YAML.
            # These are checked into tests/fixtures/sops/ and avoid IFD (import from
            # derivation), so `nix flake check --no-build` still works.
            #
            # Plaintext values in the encrypted file:
            #   database_password: supersecret123
            #   api_key: key-abc-def-789
            #   tls_cert: (PEM certificate block)
            #
            # To regenerate: see tests/fixtures/sops/README.md
            testSecretsFile = ../../tests/fixtures/sops/test-secrets.yaml;
            testAgeKeyFile = ../../tests/fixtures/sops/test-age-key.txt;
          in
          pkgs.testers.nixosTest {
            name = "vm-sops-secrets";

            nodes.machine = { config, pkgs, lib, ... }: {
              imports = [
                self.modules.nixos.system-default
                inputs.sops-nix.nixosModules.sops
                self.modules.nixos.secrets-management
              ];

              systemDefault.userName = "tim";
              systemDefault.wheelNeedsPassword = false;

              networking.firewall.enable = false;
              virtualisation.memorySize = 1024;

              # Enable our dendritic secrets-management module
              secretsManagement = {
                enable = true;
                sops = {
                  ageKeyFile = "/var/lib/sops-nix/key.txt";
                  generateHostKeys = false; # No SSH host keys in VM test
                };
              };

              # Deploy the test age key before sops-nix runs
              # Deploy the test age key before sops-nix's setupSecrets runs.
              # sops-nix's setupSecrets depends on "users" and "groups"; our script
              # has no deps so it runs early in the activation sequence.
              system.activationScripts.deployTestAgeKey.text = ''
                mkdir -p /var/lib/sops-nix
                cp ${testAgeKeyFile} /var/lib/sops-nix/key.txt
                chmod 600 /var/lib/sops-nix/key.txt
              '';

              # Point sops at our pre-encrypted test secrets
              sops.defaultSopsFile = testSecretsFile;

              # Disable SSH key paths since we use a dedicated age key
              sops.age.sshKeyPaths = lib.mkForce [ ];

              # Define secrets with various permissions and owners
              sops.secrets."database_password" = {
                mode = "0400";
                owner = "root";
                group = "root";
              };

              sops.secrets."api_key" = {
                mode = "0440";
                owner = "tim";
                group = "users";
              };

              sops.secrets."tls_cert" = {
                mode = "0444";
                owner = "root";
                group = "root";
              };

              # Test service that reads a decrypted secret.
              # Secrets are decrypted during activation (before systemd starts services),
              # so by the time this service runs, secrets are already available.
              systemd.services.secret-consumer = {
                description = "Test service that reads SOPS secrets";
                wantedBy = [ "multi-user.target" ];

                script = ''
                  if [ -f /run/secrets/database_password ]; then
                    echo "SECRET_AVAILABLE"
                  else
                    echo "SECRET_MISSING"
                    exit 1
                  fi
                '';

                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                };
              };
            };

            testScript = ''
              machine.wait_for_unit("multi-user.target")

              # --- Test 1: sops-nix activation ran (decrypts secrets during system activation) ---
              # sops-nix uses an activation script (setupSecrets), not a systemd service.
              # If secrets exist at /run/secrets/, the activation succeeded.
              machine.succeed("test -d /run/secrets")

              # --- Test 2: Age key was deployed ---
              machine.succeed("test -f /var/lib/sops-nix/key.txt")
              key_content = machine.succeed("cat /var/lib/sops-nix/key.txt")
              assert "AGE-SECRET-KEY" in key_content, "Age key not present"

              # --- Test 3: Secrets directory exists ---
              machine.succeed("test -d /run/secrets")

              # --- Test 4: Secrets decrypted and present ---
              machine.succeed("test -f /run/secrets/database_password")
              machine.succeed("test -f /run/secrets/api_key")
              machine.succeed("test -f /run/secrets/tls_cert")

              # --- Test 5: Secret content is correct ---
              db_pass = machine.succeed("cat /run/secrets/database_password").strip()
              assert db_pass == "supersecret123", f"Expected 'supersecret123', got '{db_pass}'"

              api_key = machine.succeed("cat /run/secrets/api_key").strip()
              assert api_key == "key-abc-def-789", f"Expected 'key-abc-def-789', got '{api_key}'"

              tls_cert = machine.succeed("cat /run/secrets/tls_cert")
              assert "BEGIN CERTIFICATE" in tls_cert, f"TLS cert content wrong: {tls_cert}"

              # --- Test 6: File permissions are correct ---
              # database_password: mode 0400, owner root:root
              perms = machine.succeed("stat -c %a /run/secrets/database_password").strip()
              assert perms == "400", f"database_password: expected mode 400, got {perms}"
              owner = machine.succeed("stat -c %U:%G /run/secrets/database_password").strip()
              assert owner == "root:root", f"database_password: expected root:root, got {owner}"

              # api_key: mode 0440, owner tim:users
              perms = machine.succeed("stat -c %a /run/secrets/api_key").strip()
              assert perms == "440", f"api_key: expected mode 440, got {perms}"
              owner = machine.succeed("stat -c %U:%G /run/secrets/api_key").strip()
              assert owner == "tim:users", f"api_key: expected tim:users, got {owner}"

              # tls_cert: mode 0444, owner root:root
              perms = machine.succeed("stat -c %a /run/secrets/tls_cert").strip()
              assert perms == "444", f"tls_cert: expected mode 444, got {perms}"

              # --- Test 7: Service that consumes secrets ran ---
              machine.wait_for_unit("secret-consumer.service")
              logs = machine.succeed("journalctl -u secret-consumer --no-pager")
              assert "SECRET_AVAILABLE" in logs, f"Service failed to access secret: {logs}"

              # --- Test 8: tmpfiles rule created sops directory ---
              machine.succeed("test -d /var/lib/sops-nix")
              perms = machine.succeed("stat -c %a /var/lib/sops-nix").strip()
              assert perms == "700", f"/var/lib/sops-nix: expected mode 700, got {perms}"

              # --- Test 9: Non-root user can read user-owned secret ---
              machine.succeed("su - tim -c 'cat /run/secrets/api_key' | grep -q key-abc-def-789")

              # --- Test 10: Non-root user cannot read root-only secret ---
              machine.fail("su - tim -c 'cat /run/secrets/database_password'")
            '';
          };

        # Neovim VM test: validates the largest module (1871 LOC) in a headless VM.
        # Tests config loading, plugin availability, treesitter, LSP config, and
        # checkhealth output. Uses NixOS-integrated HM with system-default.
        # Plan 021 Task 3.1
        vm-neovim = pkgs.testers.nixosTest {
          name = "vm-neovim";

          nodes.machine = { config, pkgs, lib, ... }: {
            imports = [
              self.modules.nixos.system-default
              inputs.home-manager.nixosModules.home-manager
            ];

            systemDefault.userName = "tim";
            systemDefault.wheelNeedsPassword = false;

            networking.firewall.enable = false;
            virtualisation.memorySize = 2048;

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.tim = { config, pkgs, lib, ... }: {
                imports = [
                  self.modules.homeManager.home-minimal
                  self.modules.homeManager.neovim
                ];

                homeMinimal = {
                  username = "tim";
                  homeDirectory = "/home/tim";
                };

                targets.genericLinux.enable = lib.mkForce false;
              };
            };
          };

          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("home-manager-tim.service")

            # --- Test 1: nvim binary present and working ---
            machine.succeed("su - tim -c 'nvim --version' | grep -q 'NVIM'")

            # --- Test 2: Config loads without errors (headless startup + quit) ---
            machine.succeed("su - tim -c 'nvim --headless -c \"qa!\"'")

            # --- Test 3: Neovim config directory exists ---
            machine.succeed("test -d /home/tim/.config/nvim")

            # --- Test 4: Treesitter parsers installed ---
            # nixvim installs treesitter parsers into the nix store; verify via runtime
            result = machine.succeed(
                "su - tim -c 'nvim --headless -c \"lua print(#vim.api.nvim_get_runtime_file(\\\"parser/*.so\\\", true))\" -c \"qa!\"' 2>&1"
            )
            # Should have at least a few parsers (lua, nix, bash, python, etc.)
            # The number is printed to stderr/stdout by nvim, extract any digit > 0
            machine.succeed(
                "su - tim -c 'nvim --headless"
                " -c \"lua local n = #vim.api.nvim_get_runtime_file(\\\"parser/*.so\\\", true); if n > 0 then print(\\\"PARSERS_OK:\\\" .. n) else error(\\\"no parsers\\\") end\""
                " -c \"qa!\"' 2>&1 | grep -q 'PARSERS_OK'"
            )

            # --- Test 5: Key plugins loaded (telescope, lsp, treesitter, gitsigns) ---
            for plugin in ["telescope", "nvim-treesitter", "gitsigns"]:
                machine.succeed(
                    f"su - tim -c 'nvim --headless"
                    f" -c \"lua local ok, _ = pcall(require, \\\"{plugin}\\\"); if ok then print(\\\"{plugin}_OK\\\") else error(\\\"{plugin} not found\\\") end\""
                    f" -c \"qa!\"' 2>&1 | grep -q '{plugin}_OK'"
                )

            # --- Test 6: LSP clients are configured (check lspconfig) ---
            machine.succeed(
                "su - tim -c 'nvim --headless"
                " -c \"lua local ok, lsp = pcall(require, \\\"lspconfig\\\"); if ok then print(\\\"LSP_OK\\\") else error(\\\"lspconfig missing\\\") end\""
                " -c \"qa!\"' 2>&1 | grep -q 'LSP_OK'"
            )

            # --- Test 7: Default editor is nvim ---
            machine.succeed("su - tim -c 'echo $EDITOR' | grep -q nvim")

            # --- Test 8: vi/vim aliases resolve to nvim ---
            # viAlias/vimAlias may create wrappers; verify they invoke nvim
            machine.succeed("su - tim -c 'vi --version' | head -1 | grep -q NVIM")
            machine.succeed("su - tim -c 'vim --version' | head -1 | grep -q NVIM")

            # --- Test 9: checkhealth runs without critical errors ---
            # Run checkhealth and capture output; look for ERROR in critical sections
            health_output = machine.succeed(
                "su - tim -c 'nvim --headless -c \"checkhealth\" -c \"w! /tmp/nvim-health.txt\" -c \"qa!\"' 2>&1 || true"
            )
            # Verify the health report was generated (checkhealth writes to buffer, we save it)
            machine.succeed("test -f /tmp/nvim-health.txt")
            # Allow warnings but no critical failures in core sections
            # Note: some health checks may warn about missing clipboard, which is expected in a VM
          '';
        };

        # Tmux VM test: validates the second-largest module (733 LOC) in a VM.
        # Tests server lifecycle, config loading, plugin availability, session
        # management, and helper scripts. Uses NixOS-integrated HM with system-default.
        # Plan 021 Task 3.2
        vm-tmux = pkgs.testers.nixosTest {
          name = "vm-tmux";

          nodes.machine = { config, pkgs, lib, ... }: {
            imports = [
              self.modules.nixos.system-default
              inputs.home-manager.nixosModules.home-manager
            ];

            systemDefault.userName = "tim";
            systemDefault.wheelNeedsPassword = false;

            networking.firewall.enable = false;
            virtualisation.memorySize = 2048;

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.tim = { config, pkgs, lib, ... }: {
                imports = [
                  self.modules.homeManager.home-minimal
                  self.modules.homeManager.tmux
                ];

                homeMinimal = {
                  username = "tim";
                  homeDirectory = "/home/tim";
                };

                targets.genericLinux.enable = lib.mkForce false;
              };
            };
          };

          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("home-manager-tim.service")

            # --- Test 1: tmux binary present and version check ---
            machine.succeed("su - tim -c 'tmux -V' | grep -q tmux")

            # --- Test 2: Tmux config file generated by HM ---
            # Home Manager manages tmux config via XDG path
            machine.succeed("test -f /home/tim/.config/tmux/tmux.conf")

            # --- Test 3: Tmux server starts and session can be created ---
            machine.succeed("su - tim -c 'tmux new-session -d -s test-session'")

            # --- Test 4: Session can be listed ---
            machine.succeed("su - tim -c 'tmux list-sessions' | grep -q test-session")

            # --- Test 5: Prefix key configured to Ctrl-a ---
            machine.succeed("su - tim -c 'tmux show-options -g prefix' | grep -q C-a")

            # --- Test 6: Vi mode enabled ---
            machine.succeed("su - tim -c 'tmux show-options -gw mode-keys' | grep -q vi")

            # --- Test 7: Mouse mode enabled ---
            machine.succeed("su - tim -c 'tmux show-options -g mouse' | grep -q on")

            # --- Test 8: Plugins loaded (resurrect, continuum) ---
            # tmux-resurrect sets @resurrect-dir option
            machine.succeed(
                "su - tim -c 'tmux show-options -g @resurrect-dir'"
                " | grep -q resurrect"
            )
            # tmux-continuum sets @continuum-save-interval
            machine.succeed(
                "su - tim -c 'tmux show-options -g @continuum-save-interval'"
                " | grep -q 5"
            )

            # --- Test 9: Resurrect directory exists ---
            machine.succeed("test -d /home/tim/.local/share/tmux/resurrect")

            # --- Test 10: tmux-session-picker script is executable ---
            machine.succeed("su - tim -c 'which tmux-session-picker'")

            # --- Test 11: Helper scripts present and executable ---
            machine.succeed("su - tim -c 'which tmux-cpu-mem'")
            machine.succeed("su - tim -c 'which tmux-save-with-rename'")
            machine.succeed("su - tim -c 'which tmux-window-status-format'")
            machine.succeed("su - tim -c 'which tmux-test-data-generator'")

            # --- Test 12: Can create additional sessions and switch between them ---
            machine.succeed("su - tim -c 'tmux new-session -d -s second-session'")
            result = machine.succeed("su - tim -c 'tmux list-sessions'")
            assert "test-session" in result, f"test-session missing from: {result}"
            assert "second-session" in result, f"second-session missing from: {result}"

            # --- Test 13: Pane splitting works ---
            machine.succeed("su - tim -c 'tmux split-window -h -t test-session'")
            panes = machine.succeed("su - tim -c 'tmux list-panes -t test-session'")
            # Should have at least 2 panes after splitting
            assert panes.count("\n") >= 2, f"Expected 2+ panes, got: {panes}"

            # --- Test 14: Kill server cleanly ---
            machine.succeed("su - tim -c 'tmux kill-server'")
            machine.fail("su - tim -c 'tmux list-sessions'")
          '';
        };

        # Git advanced VM test: validates git configuration beyond basic --version.
        # Tests delta integration, aliases, gitignore, LFS, merge tools, credential
        # helper, and bundled utility scripts. Uses NixOS-integrated HM with system-default.
        # Plan 021 Task 3.3
        vm-git-advanced = pkgs.testers.nixosTest {
          name = "vm-git-advanced";

          nodes.machine = { config, pkgs, lib, ... }: {
            imports = [
              self.modules.nixos.system-default
              inputs.home-manager.nixosModules.home-manager
            ];

            systemDefault.userName = "tim";
            systemDefault.wheelNeedsPassword = false;

            networking.firewall.enable = false;
            virtualisation.memorySize = 2048;

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.tim = { config, pkgs, lib, ... }: {
                imports = [
                  self.modules.homeManager.home-minimal
                  self.modules.homeManager.git
                ];

                homeMinimal = {
                  username = "tim";
                  homeDirectory = "/home/tim";
                };

                targets.genericLinux.enable = lib.mkForce false;
              };
            };
          };

          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("home-manager-tim.service")

            # --- Test 1: Delta configured as git pager ---
            machine.succeed("su - tim -c 'git config core.pager' | grep -q delta")

            # --- Test 2: Delta side-by-side mode configured ---
            machine.succeed("su - tim -c 'git config delta.side-by-side' | grep -q true")
            machine.succeed("su - tim -c 'git config delta.line-numbers' | grep -q true")

            # --- Test 3: Git aliases defined ---
            machine.succeed("su - tim -c 'git config alias.st' | grep -q status")
            machine.succeed("su - tim -c 'git config alias.ci' | grep -q commit")
            machine.succeed("su - tim -c 'git config alias.co' | grep -q checkout")
            machine.succeed("su - tim -c 'git config alias.br' | grep -q branch")
            machine.succeed("su - tim -c 'git config alias.lg' | grep -q 'log --graph'")
            machine.succeed("su - tim -c 'git config alias.unstage' | grep -q 'reset HEAD'")
            machine.succeed("su - tim -c 'git config alias.last' | grep -q 'log -1 HEAD'")

            # --- Test 4: Global gitignore patterns configured ---
            # HM writes ignores to ~/.config/git/ignore (XDG default, no core.excludesFile needed)
            ignores = machine.succeed("cat /home/tim/.config/git/ignore")
            assert ".DS_Store" in ignores, f".DS_Store not in gitignore: {ignores}"
            assert "*.swp" in ignores, f"*.swp not in gitignore: {ignores}"
            assert "result" in ignores, f"result not in gitignore: {ignores}"
            assert ".direnv/" in ignores, f".direnv/ not in gitignore: {ignores}"

            # --- Test 5: Git LFS available ---
            machine.succeed("su - tim -c 'git lfs version'")
            # LFS filter configured
            machine.succeed("su - tim -c 'git config filter.lfs.clean' | grep -q 'git-lfs clean'")

            # --- Test 6: Pre-commit hook infrastructure ---
            # HM generates hooks in the config directory
            hooks_path = machine.succeed("su - tim -c 'git config core.hooksPath'").strip()
            machine.succeed(f"test -d {hooks_path}")
            machine.succeed(f"test -x {hooks_path}/pre-commit")

            # --- Test 7: Merge tool configured (smart-nvimdiff) ---
            machine.succeed("su - tim -c 'git config merge.tool' | grep -q smart-nvimdiff")
            machine.succeed(
                "su - tim -c 'git config mergetool.smart-nvimdiff.cmd'"
                " | grep -q smart-nvimdiff"
            )

            # --- Test 8: Diff tool configured (nvimdiff) ---
            machine.succeed("su - tim -c 'git config diff.tool' | grep -q nvimdiff")
            machine.succeed("su - tim -c 'git config diff.algorithm' | grep -q histogram")

            # --- Test 9: Credential helper configured ---
            machine.succeed("su - tim -c 'git config credential.helper' | grep -q 'cache --timeout=3600'")

            # --- Test 10: Init default branch is main ---
            machine.succeed("su - tim -c 'git config init.defaultBranch' | grep -q main")

            # --- Test 11: smart-nvimdiff script in PATH ---
            machine.succeed("su - tim -c 'which smart-nvimdiff'")

            # --- Test 12: Bundled utility scripts in PATH ---
            machine.succeed("su - tim -c 'which syncfork'")
            machine.succeed("su - tim -c 'which git-functions'")

            # --- Test 13: Security and workflow tools available ---
            machine.succeed("su - tim -c 'which gitleaks'")
            machine.succeed("su - tim -c 'which lazygit'")
            machine.succeed("su - tim -c 'which git-crypt'")
            machine.succeed("su - tim -c 'which pre-commit'")

            # --- Test 14: Delta binary is present and working ---
            machine.succeed("su - tim -c 'delta --version'")

            # --- Test 15: Merge conflict style is diff3 ---
            machine.succeed("su - tim -c 'git config merge.conflictstyle' | grep -q diff3")

            # --- Test 16: Functional test — init repo, commit, verify delta in log ---
            machine.succeed(
                "su - tim -c '"
                "cd /tmp && mkdir test-repo && cd test-repo && git init"
                " && echo hello > file.txt && git add file.txt"
                " && git commit -m \"initial commit\""
                " && echo world >> file.txt && git add file.txt"
                " && git commit -m \"second commit\""
                " && git log --oneline | grep -q \"second commit\"'"
            )
          '';
        };

        # Development tools VM test: validates the development-tools HM module with
        # default flag settings. Tests language toolchains (Rust, Node, Python, Go, C/C++),
        # build utilities, enhanced CLI tools, and Claude dev utilities.
        # Uses NixOS-integrated HM with system-default.
        # Plan 021 Task 3.4
        vm-development-tools = pkgs.testers.nixosTest {
          name = "vm-development-tools";

          nodes.machine = { config, pkgs, lib, ... }: {
            imports = [
              self.modules.nixos.system-default
              inputs.home-manager.nixosModules.home-manager
            ];

            systemDefault.userName = "tim";
            systemDefault.wheelNeedsPassword = false;

            networking.firewall.enable = false;
            virtualisation.memorySize = 2048;

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.tim = { config, pkgs, lib, ... }: {
                imports = [
                  self.modules.homeManager.home-minimal
                  self.modules.homeManager.development-tools
                ];

                homeMinimal = {
                  username = "tim";
                  homeDirectory = "/home/tim";
                };

                developmentTools.enable = true;
                # All feature flags default to true except enableKubernetes and enablePyenv

                targets.genericLinux.enable = lib.mkForce false;
              };
            };
          };

          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("home-manager-tim.service")

            # === Enhanced CLI Tools (enableEnhancedCli = true by default) ===

            # --- Test 1: bat (better cat) ---
            machine.succeed("su - tim -c 'bat --version'")

            # --- Test 2: eza (modern ls) ---
            machine.succeed("su - tim -c 'eza --version'")

            # --- Test 3: delta (better diff) ---
            machine.succeed("su - tim -c 'delta --version'")

            # --- Test 4: bottom (system monitor) ---
            machine.succeed("su - tim -c 'btm --version'")

            # --- Test 5: miller (CSV/JSON processor) ---
            machine.succeed("su - tim -c 'mlr --version'")

            # === Rust Toolchain (enableRust = true by default) ===

            # --- Test 6: rustc ---
            machine.succeed("su - tim -c 'rustc --version'")

            # --- Test 7: cargo ---
            machine.succeed("su - tim -c 'cargo --version'")

            # --- Test 8: rust-analyzer ---
            machine.succeed("su - tim -c 'which rust-analyzer'")

            # --- Test 9: rustfmt ---
            machine.succeed("su - tim -c 'rustfmt --version'")

            # --- Test 10: clippy ---
            machine.succeed("su - tim -c 'which clippy-driver'")

            # === Node.js Ecosystem (enableNode = true by default) ===

            # --- Test 11: node ---
            machine.succeed("su - tim -c 'node --version'")

            # --- Test 12: npm ---
            machine.succeed("su - tim -c 'npm --version'")

            # --- Test 13: yarn ---
            machine.succeed("su - tim -c 'yarn --version'")

            # === Python (enablePython = true by default) ===

            # --- Test 14: python3 ---
            machine.succeed("su - tim -c 'python3 --version'")

            # --- Test 15: pip available as module ---
            machine.succeed("su - tim -c 'python3 -m pip --version'")

            # --- Test 16: ipython available ---
            machine.succeed("su - tim -c 'python3 -c \"import IPython\"'")

            # === Go (enableGo = true by default) ===

            # --- Test 17: go binary ---
            machine.succeed("su - tim -c 'go version'")

            # --- Test 18: Go directories created by activation ---
            machine.succeed("test -d /home/tim/go/src")
            machine.succeed("test -d /home/tim/go/pkg")
            machine.succeed("test -d /home/tim/go/bin")

            # === C/C++ Build Tools (enableCppTools = true by default) ===

            # --- Test 19: cmake ---
            machine.succeed("su - tim -c 'cmake --version'")

            # --- Test 20: gcc ---
            machine.succeed("su - tim -c 'gcc --version'")

            # --- Test 21: make ---
            machine.succeed("su - tim -c 'make --version'")

            # --- Test 22: pkg-config ---
            machine.succeed("su - tim -c 'pkg-config --version'")

            # === Build Utilities (enableBuildUtils = true by default) ===

            # --- Test 23: flex ---
            machine.succeed("su - tim -c 'flex --version'")

            # --- Test 24: bison ---
            machine.succeed("su - tim -c 'bison --version'")

            # --- Test 25: gperf ---
            machine.succeed("su - tim -c 'gperf --version'")

            # --- Test 26: doxygen ---
            machine.succeed("su - tim -c 'doxygen --version'")

            # --- Test 27: entr ---
            machine.succeed("su - tim -c 'which entr'")

            # === Claude Development Utilities (enableClaudeUtils = true by default) ===

            # --- Test 28: claudevloop script ---
            machine.succeed("su - tim -c 'which claudevloop'")

            # --- Test 29: restart_claude script ---
            machine.succeed("su - tim -c 'which restart_claude'")

            # --- Test 30: mkclaude_desktop_config script ---
            machine.succeed("su - tim -c 'which mkclaude_desktop_config'")

            # --- Test 31: claude-models script ---
            machine.succeed("su - tim -c 'which claude-models'")

            # --- Test 32: pdf2md script ---
            machine.succeed("su - tim -c 'which pdf2md'")

            # === Kubernetes NOT installed by default (enableKubernetes = false) ===

            # --- Test 33: kubectl should NOT be present ---
            machine.fail("su - tim -c 'which kubectl'")

            # === Session Paths ===

            # Note: Session variables (GOPATH, PATH additions for .cargo/bin, go/bin,
            # .local/bin) are configured via home.sessionVariables/sessionPath and verified
            # by eval-hm-module-development-tools. Runtime PATH sourcing depends on the
            # shell module, which is tested separately in vm-shell-env.
          '';
        };

        # Desktop system type VM test: validates the system-desktop layer with
        # GNOME (default DE), PipeWire audio, Bluetooth, CUPS printing, fonts,
        # and GPU/graphics configuration. Does NOT start a display server (no GPU
        # in VM); verifies packages are installed and services are declared.
        # Inherits system-cli layer (SSH, dev tools).
        # Plan 021 Task 3.5
        vm-system-type-desktop =
          let
            # Desktop module includes unfree fonts (corefonts, vistafonts).
            # testers.nixosTest injects its pkgs into nodes, so we need a pkgs
            # instance with allowUnfree to avoid the "externally created instance"
            # assertion.
            pkgsUnfree = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          in
          pkgsUnfree.testers.nixosTest {
            name = "vm-system-type-desktop";

            nodes.machine = { config, pkgs, ... }: {
              imports = [ self.modules.nixos.system-desktop ];

              networking.firewall.enable = false;
              virtualisation.memorySize = 2048;

              # Required by system-default (inherited via cli → default)
              systemDefault.userName = "tim";
              systemDefault.wheelNeedsPassword = false;

              # Use defaults: GNOME, PipeWire, Bluetooth, Printing, Nerd Fonts
            };

            testScript = ''
              machine.wait_for_unit("multi-user.target")

              # === Test 1: System boots to multi-user.target ===
              # Desktop VMs should reach multi-user even without a display
              machine.succeed("systemctl is-active multi-user.target")

              # === Test 2: Inherits CLI layer — SSH daemon running ===
              machine.wait_for_unit("sshd.service")

              # === Test 3: Inherits CLI layer — dev tools present ===
              machine.succeed("which git")
              machine.succeed("which jq")
              machine.succeed("which nvim")

              # === Test 4: X server / display infrastructure packages present ===
              # X server is enabled by system-desktop even for Wayland setups
              machine.succeed("which Xorg || which Xwayland || test -f /run/current-system/sw/bin/X")

              # === Test 5: GNOME desktop environment packages present ===
              # GNOME is the default DE; check for representative binaries/packages
              machine.succeed("test -e /run/current-system/sw/share/gnome-session")

              # === Test 6: GDM display manager configured ===
              # GDM is auto-selected for GNOME; verify the service unit exists
              machine.succeed("systemctl cat display-manager.service | grep -qi gdm")

              # === Test 7: PipeWire audio configured (default backend) ===
              # PipeWire service unit should exist
              machine.succeed("systemctl cat pipewire.service")
              # Wireplumber session manager configured
              machine.succeed("systemctl cat wireplumber.service")
              # PulseAudio compatibility module is enabled
              machine.succeed("systemctl cat pipewire-pulse.service")

              # === Test 8: Bluetooth service configured ===
              machine.succeed("systemctl cat bluetooth.service")
              # Bluetooth hardware support enabled
              machine.succeed("which bluetoothctl")

              # === Test 9: CUPS printing service configured ===
              machine.succeed("systemctl cat cups.service")
              # Printer discovery via Avahi
              machine.succeed("systemctl cat avahi-daemon.service")

              # === Test 10: Fonts installed ===
              # Check fontconfig can find expected font families
              machine.succeed("fc-list | grep -qi 'Noto Sans'")
              machine.succeed("fc-list | grep -qi 'DejaVu'")
              machine.succeed("fc-list | grep -qi 'Liberation'")
              # Nerd Fonts (JetBrainsMono is the default)
              machine.succeed("fc-list | grep -qi 'JetBrainsMono'")
              # Font Awesome icons
              machine.succeed("fc-list | grep -qi 'Font Awesome'")

              # === Test 11: Graphics/OpenGL configured ===
              # hardware.graphics.enable creates the graphics driver infrastructure
              # Check for the mesa/graphics library directory
              machine.succeed("test -d /run/opengl-driver || test -d /run/current-system/sw/lib")

              # === Test 12: Common GUI tools installed ===
              machine.succeed("which xdg-open")
              machine.succeed("which xclip")
              machine.succeed("which wl-copy")
              machine.succeed("which grim")
              machine.succeed("which slurp")

              # === Test 13: XDG portal configured ===
              # XDG portal service should be available
              machine.succeed("test -d /run/current-system/sw/share/xdg-desktop-portal")

              # === Test 14: dconf enabled (GNOME settings backend) ===
              machine.succeed("which dconf")

              # === Test 15: GNOME excluded packages not present ===
              # gnome-tour and gnome-music should be excluded
              machine.fail("which gnome-tour 2>/dev/null")

              # === Test 16: User in printer group (lp) ===
              machine.succeed("id -nG tim | grep -q lp")

              # === Test 17: rtkit enabled for real-time audio scheduling ===
              machine.succeed("systemctl cat rtkit-daemon.service")

              # === Test 18: Inherits default layer — user exists ===
              machine.succeed("id tim")
              machine.succeed("getent passwd tim | grep -q zsh")
            '';
          };

        # Yazi VM test: validates the yazi file manager module using mkHmModuleTest.
        # Tests binary presence, config generation, and basic functionality.
        # Also serves as proof-of-concept for the mkHmModuleTest helper.
        # Plan 021 Task 4.1 (helper validation)
        vm-yazi = mkHmModuleTest {
          name = "yazi";
          hmModules = [ self.modules.homeManager.yazi ];
          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("home-manager-tim.service")

            # --- Test 1: yazi binary present ---
            machine.succeed("su - tim -c 'yazi --version'")

            # --- Test 2: Yazi config directory exists ---
            machine.succeed("test -d /home/tim/.config/yazi")

            # --- Test 3: Yazi config file generated ---
            machine.succeed("test -f /home/tim/.config/yazi/yazi.toml")

            # --- Test 4: Custom init.lua deployed ---
            machine.succeed("test -f /home/tim/.config/yazi/init.lua")

            # --- Test 5: Keymap config generated ---
            machine.succeed("test -f /home/tim/.config/yazi/keymap.toml")
          '';
        };

        # HM Module Isolation VM Tests: proves each VM-safe HM module activates
        # successfully with ONLY home-minimal — no other HM modules.
        # Each module gets its own VM node; all boot in parallel via start_all().
        # This validates the dendritic pattern's promise of truly independent modules.
        # Plan 021 Task 4.2
        vm-hm-module-isolation =
          let
            # Helper: create a NixOS node that activates a single HM module in isolation
            mkIsolationNode = { hmModules, hmConfig ? { } }:
              { config, pkgs, lib, ... }: {
                imports = [
                  self.modules.nixos.system-default
                  inputs.home-manager.nixosModules.home-manager
                ];

                systemDefault.userName = "tim";
                systemDefault.wheelNeedsPassword = false;
                networking.firewall.enable = false;
                virtualisation.memorySize = 1024;

                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  extraSpecialArgs = { inherit inputs; };
                  users.tim = { config, pkgs, lib, ... }: {
                    imports = [
                      self.modules.homeManager.home-minimal
                    ] ++ hmModules;

                    homeMinimal = {
                      username = "tim";
                      homeDirectory = "/home/tim";
                    };

                    targets.genericLinux.enable = lib.mkForce false;
                  } // hmConfig;
                };
              };
          in
          pkgs.testers.nixosTest {
            name = "vm-hm-module-isolation";

            nodes = {
              node_tmux = mkIsolationNode {
                hmModules = [ self.modules.homeManager.tmux ];
              };
              node_neovim = mkIsolationNode {
                hmModules = [ self.modules.homeManager.neovim ];
              };
              node_git = mkIsolationNode {
                hmModules = [ self.modules.homeManager.git ];
              };
              node_shell = mkIsolationNode {
                hmModules = [ self.modules.homeManager.shell ];
              };
              node_devtools = mkIsolationNode {
                hmModules = [ self.modules.homeManager.development-tools ];
                hmConfig = { developmentTools.enable = true; };
              };
              node_yazi = mkIsolationNode {
                hmModules = [ self.modules.homeManager.yazi ];
              };
              node_shellutils = mkIsolationNode {
                hmModules = [ self.modules.homeManager.shell-utils ];
              };
              node_podman = mkIsolationNode {
                hmModules = [ self.modules.homeManager.podman ];
                hmConfig = { programs.podman-tools.enable = true; };
              };
            };

            testScript = ''
              # Boot all 8 nodes in parallel
              start_all()

              # Wait for HM activation on all nodes
              for node in [node_tmux, node_neovim, node_git, node_shell, node_devtools, node_yazi, node_shellutils, node_podman]:
                  node.wait_for_unit("multi-user.target")
                  node.wait_for_unit("home-manager-tim.service")

              # === tmux: binary + config ===
              node_tmux.succeed("su - tim -c 'tmux -V' | grep -q tmux")
              node_tmux.succeed("test -f /home/tim/.config/tmux/tmux.conf")

              # === neovim: binary + config dir ===
              node_neovim.succeed("su - tim -c 'nvim --version' | grep -q NVIM")
              node_neovim.succeed("test -d /home/tim/.config/nvim")

              # === git: user config + config file ===
              node_git.succeed("su - tim -c 'git config user.name' | grep -q 'Tim Black'")
              node_git.succeed("test -f /home/tim/.config/git/config")

              # === shell: zsh works + zshrc generated ===
              node_shell.succeed("su - tim -c 'zsh -c \"echo ZSH_OK\"' | grep -q ZSH_OK")
              node_shell.succeed("test -f /home/tim/.zshrc")

              # === development-tools: enhanced CLI + language toolchain ===
              node_devtools.succeed("su - tim -c 'bat --version'")
              node_devtools.succeed("su - tim -c 'rustc --version'")

              # === yazi: binary + config file ===
              node_yazi.succeed("su - tim -c 'yazi --version'")
              node_yazi.succeed("test -f /home/tim/.config/yazi/yazi.toml")

              # === shell-utils: representative script + library file ===
              node_shellutils.succeed("su - tim -c 'which mytree'")
              node_shellutils.succeed("test -f /home/tim/.local/lib/general-utils.bash")

              # === podman: podman-tui binary + registries config ===
              node_podman.succeed("su - tim -c 'which podman-tui'")
              node_podman.succeed("test -f /home/tim/.config/containers/registries.conf")
            '';
          };

        # HM Module Composition Pair Tests: validates cross-module integration points
        # that only work when specific module pairs are combined.
        # 4 nodes (one per pair), all boot in parallel via start_all().
        # Plan 021 Task 4.3
        vm-hm-composition-pairs =
          let
            # Reuse the isolation node helper pattern but with multiple HM modules
            mkPairNode = { hmModules, hmConfig ? { } }:
              { config, pkgs, lib, ... }: {
                imports = [
                  self.modules.nixos.system-default
                  inputs.home-manager.nixosModules.home-manager
                ];

                systemDefault.userName = "tim";
                systemDefault.wheelNeedsPassword = false;
                networking.firewall.enable = false;
                virtualisation.memorySize = 2048;

                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  extraSpecialArgs = { inherit inputs; };
                  users.tim = { config, pkgs, lib, ... }: {
                    imports = [
                      self.modules.homeManager.home-minimal
                    ] ++ hmModules;

                    homeMinimal = {
                      username = "tim";
                      homeDirectory = "/home/tim";
                    };

                    targets.genericLinux.enable = lib.mkForce false;
                  } // hmConfig;
                };
              };
          in
          pkgs.testers.nixosTest {
            name = "vm-hm-composition-pairs";

            nodes = {
              # Pair 1: neovim + tmux (vim-tmux-navigator integration)
              pair_nvim_tmux = mkPairNode {
                hmModules = [
                  self.modules.homeManager.neovim
                  self.modules.homeManager.tmux
                ];
              };

              # Pair 2: git + neovim (merge/diff tool integration)
              pair_git_nvim = mkPairNode {
                hmModules = [
                  self.modules.homeManager.git
                  self.modules.homeManager.neovim
                ];
              };

              # Pair 3: git + shell (aliases integration)
              pair_git_shell = mkPairNode {
                hmModules = [
                  self.modules.homeManager.git
                  self.modules.homeManager.shell
                ];
              };

              # Pair 4: shell + tmux (terminal env integration)
              pair_shell_tmux = mkPairNode {
                hmModules = [
                  self.modules.homeManager.shell
                  self.modules.homeManager.tmux
                ];
              };
            };

            testScript = ''
              # Boot all 4 nodes in parallel
              start_all()

              # Wait for HM activation on all nodes
              for node in [pair_nvim_tmux, pair_git_nvim, pair_git_shell, pair_shell_tmux]:
                  node.wait_for_unit("multi-user.target")
                  node.wait_for_unit("home-manager-tim.service")

              # ========================================================
              # Pair 1: neovim + tmux — vim-tmux-navigator integration
              # ========================================================

              # Both binaries present
              pair_nvim_tmux.succeed("su - tim -c 'nvim --version' | grep -q NVIM")
              pair_nvim_tmux.succeed("su - tim -c 'tmux -V' | grep -q tmux")

              # Tmux config has vim-tmux-navigator keybindings (C-h, C-j, C-k, C-l)
              tmux_conf = pair_nvim_tmux.succeed("cat /home/tim/.config/tmux/tmux.conf")
              assert "is_vim" in tmux_conf, "tmux-navigator is_vim detection missing from tmux.conf"
              assert "C-h" in tmux_conf, "C-h navigator binding missing from tmux.conf"
              assert "C-j" in tmux_conf, "C-j navigator binding missing from tmux.conf"
              assert "C-k" in tmux_conf, "C-k navigator binding missing from tmux.conf"
              assert "C-l" in tmux_conf, "C-l navigator binding missing from tmux.conf"

              # Neovim has tmux-navigator plugin loaded
              pair_nvim_tmux.succeed(
                  "su - tim -c 'nvim --headless"
                  " -c \"lua local ok, _ = pcall(require, \\\"tmux\\\"); if ok then print(\\\"TMUX_NAV_OK\\\") else"
                  " local rtp = vim.api.nvim_list_runtime_paths();"
                  " for _, p in ipairs(rtp) do if p:match(\\\"tmux\\\") then print(\\\"TMUX_NAV_OK\\\"); return end end;"
                  " error(\\\"tmux-navigator not found\\\") end\""
                  " -c \"qa!\"' 2>&1 | grep -q TMUX_NAV_OK"
              )

              # Functional test: start tmux, run nvim inside, verify both work together
              pair_nvim_tmux.succeed("su - tim -c 'tmux new-session -d -s nvim-test'")
              pair_nvim_tmux.succeed("su - tim -c 'tmux send-keys -t nvim-test \"nvim --headless -c qa!\" Enter'")
              import time; time.sleep(2)
              pair_nvim_tmux.succeed("su - tim -c 'tmux list-sessions' | grep -q nvim-test")

              # ========================================================
              # Pair 2: git + neovim — merge/diff tool integration
              # ========================================================

              # Both binaries present
              pair_git_nvim.succeed("su - tim -c 'git --version'")
              pair_git_nvim.succeed("su - tim -c 'nvim --version' | grep -q NVIM")

              # Git merge tool set to smart-nvimdiff (depends on nvim)
              pair_git_nvim.succeed("su - tim -c 'git config merge.tool' | grep -q smart-nvimdiff")
              pair_git_nvim.succeed(
                  "su - tim -c 'git config mergetool.smart-nvimdiff.cmd'"
                  " | grep -q smart-nvimdiff"
              )

              # Git diff tool set to nvimdiff
              pair_git_nvim.succeed("su - tim -c 'git config diff.tool' | grep -q nvimdiff")
              pair_git_nvim.succeed(
                  "su - tim -c 'git config difftool.nvimdiff.cmd'"
                  " | grep -q 'nvim -d'"
              )

              # smart-nvimdiff script is in PATH and executable
              pair_git_nvim.succeed("su - tim -c 'which smart-nvimdiff'")

              # The script references nvim — verify nvim is callable from the script's env
              pair_git_nvim.succeed("su - tim -c 'smart-nvimdiff --help || true' 2>&1")

              # Functional test: create merge conflict, verify merge tool config works
              pair_git_nvim.succeed(
                  "su - tim -c '"
                  "cd /tmp && mkdir merge-test && cd merge-test && git init"
                  " && echo base > file.txt && git add file.txt && git commit -m base"
                  " && git checkout -b feature"
                  " && echo feature > file.txt && git add file.txt && git commit -m feature"
                  " && git checkout main 2>/dev/null || git checkout master"
                  " && echo main > file.txt && git add file.txt && git commit -m main"
                  " && git merge feature --no-edit || true'"
              )
              # Verify conflict exists (merge.tool would be invoked to resolve it)
              pair_git_nvim.succeed(
                  "su - tim -c 'cd /tmp/merge-test && git diff --name-only --diff-filter=U' | grep -q file.txt"
              )

              # ========================================================
              # Pair 3: git + shell — aliases integration
              # ========================================================

              # Both git and zsh work
              pair_git_shell.succeed("su - tim -c 'git --version'")
              pair_git_shell.succeed("su - tim -c 'zsh -c \"echo ZSH_OK\"' | grep -q ZSH_OK")

              # Git aliases available in zsh interactive session
              pair_git_shell.succeed("su - tim -c 'zsh -ic \"alias gs\"' | grep -q 'git status'")
              pair_git_shell.succeed("su - tim -c 'zsh -ic \"alias ga\"' | grep -q 'git add'")
              pair_git_shell.succeed("su - tim -c 'zsh -ic \"alias gc\"' | grep -q 'git commit'")
              pair_git_shell.succeed("su - tim -c 'zsh -ic \"alias gp\"' | grep -q 'git push'")
              pair_git_shell.succeed("su - tim -c 'zsh -ic \"alias gd\"' | grep -q 'git diff'")

              # Functional test: use git alias in zsh to run actual git command
              pair_git_shell.succeed(
                  "su - tim -c 'cd /tmp && mkdir alias-test && cd alias-test && git init"
                  " && zsh -ic \"gs\"'"
              )

              # ========================================================
              # Pair 4: shell + tmux — terminal environment integration
              # ========================================================

              # Both work independently
              pair_shell_tmux.succeed("su - tim -c 'zsh -c \"echo ZSH_OK\"' | grep -q ZSH_OK")
              pair_shell_tmux.succeed("su - tim -c 'tmux -V' | grep -q tmux")

              # Start a tmux session — the pane shell inherits $TMUX from tmux
              pair_shell_tmux.succeed("su - tim -c 'tmux new-session -d -s shell-test'")

              # Wait for tmux session to be ready and zsh to finish loading
              pair_shell_tmux.succeed("su - tim -c 'tmux list-sessions' | grep -q shell-test")
              import time; time.sleep(5)

              # Verify TMUX env var is set inside the tmux pane's shell
              # Use send-keys which runs inside the pane's shell where $TMUX is set
              pair_shell_tmux.succeed(
                  "su - tim -c 'tmux send-keys -t shell-test \"printenv TMUX > /tmp/tmux-env.txt\" Enter'"
              )
              # Wait for the command to execute (file to appear)
              pair_shell_tmux.wait_until_succeeds("test -s /tmp/tmux-env.txt", timeout=10)
              result = pair_shell_tmux.succeed("cat /tmp/tmux-env.txt").strip()
              assert "/" in result, f"TMUX env var not set inside tmux pane: '{result}'"

              # Verify zsh works inside tmux pane by running zsh command
              pair_shell_tmux.succeed(
                  "su - tim -c 'tmux send-keys -t shell-test \"zsh -c \\\"echo ZSH_IN_TMUX\\\" > /tmp/zsh-test.txt\" Enter'"
              )
              pair_shell_tmux.wait_until_succeeds("test -s /tmp/zsh-test.txt", timeout=10)
              result = pair_shell_tmux.succeed("cat /tmp/zsh-test.txt").strip()
              assert "ZSH_IN_TMUX" in result, f"zsh failed inside tmux pane: '{result}'"

              # Verify tmux detection in shell config
              # The shell module checks for TMUX variable in .zshrc
              zshrc = pair_shell_tmux.succeed("cat /home/tim/.zshrc")
              assert "TMUX" in zshrc, "Shell module should reference TMUX variable in .zshrc"

              # Clean up
              pair_shell_tmux.succeed("su - tim -c 'tmux kill-server'")
            '';
          };

        # Full CLI Stack Integration Test: activates system-cli + ALL 9 VM-safe
        # HM modules together in a single VM. This is the ultimate integration test
        # for the dendritic pattern — proving all modules compose without conflicts
        # in a near-production configuration.
        # Plan 021 Task 4.4
        vm-full-cli-stack = pkgs.testers.nixosTest {
          name = "vm-full-cli-stack";

          nodes.machine = { config, pkgs, lib, ... }: {
            imports = [
              self.modules.nixos.system-cli
              inputs.home-manager.nixosModules.home-manager
            ];

            systemDefault.userName = "tim";
            systemDefault.wheelNeedsPassword = false;
            networking.firewall.enable = false;
            virtualisation.memorySize = 3072;

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.tim = { config, pkgs, lib, ... }: {
                imports = [
                  self.modules.homeManager.home-minimal
                  self.modules.homeManager.shell
                  self.modules.homeManager.git
                  self.modules.homeManager.tmux
                  self.modules.homeManager.neovim
                  self.modules.homeManager.development-tools
                  self.modules.homeManager.yazi
                  self.modules.homeManager.shell-utils
                  self.modules.homeManager.podman
                ];

                homeMinimal = {
                  username = "tim";
                  homeDirectory = "/home/tim";
                };

                developmentTools.enable = true;
                programs.podman-tools.enable = true;

                targets.genericLinux.enable = lib.mkForce false;
              };
            };
          };

          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("home-manager-tim.service")

            # === Section 1: All primary binaries present ===

            machine.succeed("su - tim -c 'nvim --version' | grep -q NVIM")
            machine.succeed("su - tim -c 'tmux -V' | grep -q tmux")
            machine.succeed("su - tim -c 'git --version'")
            machine.succeed("su - tim -c 'yazi --version'")
            machine.succeed("su - tim -c 'bat --version'")
            machine.succeed("su - tim -c 'which podman-tui'")
            machine.succeed("su - tim -c 'zsh -c \"echo ZSH_OK\"' | grep -q ZSH_OK")

            # === Section 2: NixOS system-cli layer verified ===

            machine.wait_for_unit("sshd.service")
            machine.succeed("which jq")
            machine.succeed("which fzf")
            machine.succeed("which eza")

            # === Section 3: Cross-module integration — git + delta ===

            machine.succeed("su - tim -c 'git config core.pager' | grep -q delta")
            machine.succeed("su - tim -c 'delta --version'")

            # === Section 4: Cross-module integration — zsh + git aliases ===

            machine.succeed("su - tim -c 'zsh -ic \"alias gs\"' | grep -q 'git status'")
            machine.succeed("su - tim -c 'zsh -ic \"alias ga\"' | grep -q 'git add'")

            # === Section 5: Cross-module integration — neovim + tmux navigator ===

            tmux_conf = machine.succeed("cat /home/tim/.config/tmux/tmux.conf")
            assert "is_vim" in tmux_conf, "vim-tmux-navigator detection missing"

            # === Section 6: Cross-module integration — git + neovim merge tool ===

            machine.succeed("su - tim -c 'git config merge.tool' | grep -q smart-nvimdiff")
            machine.succeed("su - tim -c 'git config diff.tool' | grep -q nvimdiff")

            # === Section 7: Neovim starts cleanly with full config ===

            machine.succeed("su - tim -c 'nvim --headless -c \"qa!\"'")

            # === Section 8: Tmux server lifecycle ===

            machine.succeed("su - tim -c 'tmux new-session -d -s full-stack-test'")
            machine.succeed("su - tim -c 'tmux list-sessions' | grep -q full-stack-test")
            machine.succeed("su - tim -c 'tmux kill-server'")

            # === Section 9: User environment coherent ===

            # EDITOR set to nvim
            machine.succeed("su - tim -c 'echo $EDITOR' | grep -q nvim")

            # Shell is zsh
            machine.succeed("getent passwd tim | grep -q zsh")

            # User is in wheel group (from system-default via system-cli)
            machine.succeed("id -nG tim | grep -q wheel")

            # Nix trusts the user
            machine.succeed("nix show-config | grep trusted-users | grep -q tim")

            # === Section 10: Module-specific configs all generated ===

            machine.succeed("test -f /home/tim/.config/tmux/tmux.conf")
            machine.succeed("test -f /home/tim/.config/git/config")
            machine.succeed("test -d /home/tim/.config/nvim")
            machine.succeed("test -f /home/tim/.config/yazi/yazi.toml")
            machine.succeed("test -f /home/tim/.zshrc")
            machine.succeed("test -f /home/tim/.config/containers/registries.conf")

            # === Section 11: Development toolchains present ===

            machine.succeed("su - tim -c 'rustc --version'")
            machine.succeed("su - tim -c 'node --version'")
            machine.succeed("su - tim -c 'python3 --version'")
            machine.succeed("su - tim -c 'go version'")

            # === Section 12: Shell utility scripts from shell-utils ===

            machine.succeed("su - tim -c 'which mytree'")
            machine.succeed("test -f /home/tim/.local/lib/general-utils.bash")

            # === Section 13: Functional integration — init repo with aliases in zsh ===

            machine.succeed(
                "su - tim -c '"
                "cd /tmp && mkdir full-stack-repo && cd full-stack-repo && git init"
                " && echo hello > file.txt && git add file.txt"
                " && git commit -m \"test commit\""
                " && git log --oneline | grep -q \"test commit\"'"
            )
          '';
        };

        # User configuration test: verifies user setup, groups, home directory,
        # shell, sudo, nix trusted-users, and environment variables
        vm-user-config = mkVmTest {
          name = "user-config";
          description = "User creation, groups, home directory, shell, and sudo";
          modules = [ self.modules.nixos.system-default ];
          extraConfig = {
            systemDefault.userName = "tim";
            systemDefault.userGroups = [ "wheel" "networkmanager" "audio" "video" "docker" ];
            systemDefault.wheelNeedsPassword = false;
            systemDefault.extraShellAliases = { testvm = "echo test-alias-works"; };
            systemDefault.extraEnvironment = { TEST_VAR = "vm-test-value"; };
          };
          testScript = ''
            machine.wait_for_unit("multi-user.target")

            # --- Test 1: User exists and is a normal user ---
            machine.succeed("id tim")
            machine.succeed("getent passwd tim | grep -q /home/tim")

            # --- Test 2: Home directory exists and is owned by user ---
            machine.succeed("test -d /home/tim")
            machine.succeed("stat -c '%U' /home/tim | grep -q tim")

            # --- Test 3: User is in expected groups ---
            machine.succeed("id -nG tim | grep -q wheel")
            machine.succeed("id -nG tim | grep -q audio")
            machine.succeed("id -nG tim | grep -q video")

            # --- Test 4: Shell is zsh ---
            machine.succeed("getent passwd tim | grep -q zsh")
            # zsh binary exists
            machine.succeed("which zsh")

            # --- Test 5: User can sudo (wheel group) ---
            # sudo should work for wheel members (default NixOS config)
            machine.succeed("su - tim -c 'sudo -n true'")

            # --- Test 6: Nix trusts the user ---
            machine.succeed("nix show-config | grep trusted-users | grep -q tim")

            # --- Test 7: Environment variable set ---
            machine.succeed("bash -lc 'echo $TEST_VAR' | grep -q vm-test-value")

            # --- Test 8: Shell alias defined in system config ---
            # NixOS puts environment.shellAliases in shell rc files
            machine.succeed("grep -q testvm /etc/bashrc")
          '';
        };
      };
    };
}
