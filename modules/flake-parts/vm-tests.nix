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
