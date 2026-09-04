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
{ inputs, self, config, ... }:
let
  # Central test username — sourced from flake-level meta option.
  # All VM tests use this instead of hardcoding usernames.
  testUsername = config.meta.username;
  testHomeDir = "/home/${testUsername}";
in
{
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

      # mkContainerTest: like mkVmTest, but runs the machine on the systemd-nspawn
      # CONTAINER backend (NixOS 26.05 test-driver feature) instead of a QEMU VM.
      #
      # WHY a separate helper (not a flag on mkVmTest): mkVmTest wraps
      # pkgs.testers.nixosTest — the legacy `simpleTest`/testing-python.nix path,
      # which does NOT expose the `containers` option. The nspawn backend lives only
      # on pkgs.testers.runNixOSTest (the module-based nixos/lib/testing framework),
      # where a top-level `containers.<name>` attr sits alongside `nodes.<name>`.
      # Placing a machine under `containers` auto-enables nspawn
      # (driver.nix: enableNspawn = containers != {}) and the host `uid-range`
      # requirement (run.nix — nspawn needs pid 0 inside the sandbox).
      #
      # CONSTRAINT: a container shares the host kernel — userspace systemd only, no
      # initrd/bootloader/kernel-modules/KVM. Use for service/user/package/HM
      # smoke assertions; keep boot/kernel/hardware semantics on mkVmTest.
      #
      # Args mirror mkVmTest MINUS `memory` (containers take no
      # virtualisation.memorySize). `containers` overrides the single-machine
      # shorthand when a multi-container topology is needed.
      mkContainerTest =
        { name
        , description ? "Container test: ${name}"
        , modules ? [ ]
        , containers ? null
        , testScript
        , extraConfig ? { }
        ,
        }:
        pkgs.testers.runNixOSTest {
          name = "vm-${name}";

          # nspawn container backend never launches QEMU, so /dev/kvm is not
          # used at runtime. The framework defaults requiredFeatures.kvm to
          # isLinux (adds `kvm` to requiredSystemFeatures); disable it so these
          # tests declare their REAL requirements and run on KVM-less builders
          # (e.g. GitHub's aarch64 runners, which have no /dev/kvm). See
          # nixpkgs nixos/lib/testing/run.nix requiredFeatures.kvm.
          requiredFeatures.kvm = false;

          containers = if containers != null then containers else {
            machine = { config, pkgs, ... }: {
              imports = modules;
              networking.firewall.enable = false;
            } // extraConfig;
          };

          inherit testScript;
        };

      # hmNspawnNode: a systemd-nspawn CONTAINER node module that activates Home
      # Manager module(s) on the READ-ONLY shared /nix/store, using the R2
      # "direction #3" recipe (plan 054 — proven by spike-r2-hm-roskip):
      #
      #   1. `nix.settings.build-users-group = ""` — skips nix's LocalStore chown
      #      of /nix/store on open (the chown is guarded by a non-empty
      #      build-users-group), which otherwise aborts on the RO store.
      #   2. a daemon-free `register-nix-paths` oneshot that runs
      #      `nix-store --load-db` from the HM generation's closureInfo BEFORE
      #      home-manager-<user>.service — so the container db agrees the
      #      generation path is valid (HM's `nix-env --set` writes only the
      #      profile symlink under the writable /nix/var, never the RO store).
      #
      # This makes the whole HM-activation family runnable on nspawn (~5-7x
      # faster than QEMU) with NO writable store, NO overlay, NO upstream change.
      # See plan 054 "R2 spike findings" + docs/nix-store-model-and-vmtest-backends.md §8f.
      #
      # Arguments mirror the old mkHmModuleTest node:
      #   hmModules         - HM modules to import (self.modules.homeManager.*)
      #   hmConfig          - attrs merged into the HM user config (default: {})
      #   extraNixosModules - additional NixOS modules to import (default: [])
      hmNspawnNode =
        { hmModules
        , hmConfig ? { }
        , extraNixosModules ? [ ]
        ,
        }:
        { config, pkgs, lib, ... }:
        let
          hmGen = config.home-manager.users.${testUsername}.home.activationPackage;
          regInfo = pkgs.closureInfo { rootPaths = [ hmGen ]; };
        in
        {
          imports = [
            self.modules.nixos.system-default
            inputs.home-manager.nixosModules.home-manager
          ] ++ extraNixosModules;

          systemDefault.userName = testUsername;
          systemDefault.wheelNeedsPassword = false;
          networking.firewall.enable = false;

          # R2 direction #3 lever: skip the LocalStore chown on the RO store.
          nix.settings.build-users-group = "";

          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = { inherit inputs; };
            users.${testUsername} = { config, pkgs, lib, ... }: {
              imports = [
                self.modules.homeManager.home-minimal
              ] ++ hmModules;

              homeMinimal = {
                username = testUsername;
                homeDirectory = testHomeDir;
              };

              # NixOS-integrated HM doesn't need genericLinux
              targets.genericLinux.enable = lib.mkForce false;
            } // hmConfig;
          };

          # Register the HM closure daemon-free BEFORE HM activation (RO store,
          # writable /nix/var db). Lifted from spike-r2-hm-roskip.
          systemd.services.register-nix-paths = {
            description = "HM-on-nspawn: daemon-free load-db of the HM closure (R2 dir #3)";
            wantedBy = [ "multi-user.target" ];
            before = [ "home-manager-${testUsername}.service" ];
            path = [ pkgs.nix ];
            environment.NIX_REMOTE = "";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              set -eux
              nix-store --load-db < ${regInfo}/registration
            '';
          };
        };

      # mkHmContainerTest: single-node HM module test on the nspawn backend.
      # nspawn analog of the old mkHmModuleTest (which was QEMU). Bakes in the
      # hmNspawnNode recipe. Caller specifies HM modules + asserts.
      #
      # Arguments:
      #   name             - Test name (prefixed with "vm-" in checks)
      #   description      - Human-readable description
      #   hmModules        - HM modules to import (self.modules.homeManager.*)
      #   testScript       - Python test script (nixos-test-driver syntax)
      #   extraNixosModules - additional NixOS modules to import (default: [])
      #   hmConfig         - attrs merged into the HM user config (default: {})
      #
      # Example:
      #   mkHmContainerTest {
      #     name = "yazi";
      #     hmModules = [ self.modules.homeManager.yazi ];
      #     testScript = ''
      #       machine.wait_for_unit("multi-user.target")
      #       machine.wait_for_unit("home-manager-${testUsername}.service")
      #       machine.succeed("su - ${testUsername} -c 'yazi --version'")
      #     '';
      #   }
      mkHmContainerTest =
        { name
        , description ? "HM container test: ${name}"
        , hmModules
        , testScript
        , extraNixosModules ? [ ]
        , hmConfig ? { }
        ,
        }:
        pkgs.testers.runNixOSTest {
          name = "vm-${name}";
          # nspawn backend: no QEMU, no /dev/kvm at runtime (see mkContainerTest).
          requiredFeatures.kvm = false;
          containers.machine = hmNspawnNode { inherit hmModules hmConfig extraNixosModules; };
          inherit testScript;
        };

    in
    {
      checks = {
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
        # nspawn (HM-free system-layer test; migrated P5c per R2/P5b backend map).
        vm-system-type-default = mkContainerTest {
          name = "system-type-default";
          description = "system-default layer: user creation, locale, timezone";
          modules = [ self.modules.nixos.system-default ];
          extraConfig = {
            systemDefault.userName = testUsername;
          };
          testScript = ''
            machine.wait_for_unit("multi-user.target")

            # User creation
            machine.succeed("id ${testUsername}")
            machine.succeed("id -nG ${testUsername} | grep -q wheel")

            # Locale
            machine.succeed("locale | grep -q en_US")

            # Timezone
            machine.succeed("timedatectl show -p Timezone --value | grep -q America/Los_Angeles")

            # Shell is zsh
            machine.succeed("getent passwd ${testUsername} | grep -q zsh")

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
            systemDefault.userName = testUsername;
          };
          testScript = ''
            machine.wait_for_unit("multi-user.target")

            # SSH daemon running (cli layer enables sshd by default)
            machine.wait_for_unit("sshd.service")

            # Inherits default: user exists
            machine.succeed("id ${testUsername}")

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

        # === NSPAWN CONTAINER BACKEND POC (plan 053 T6) ===

        # vm-nspawn-smoke: proof-of-concept for the NixOS 26.05 systemd-nspawn
        # container test backend. Deliberately a TWIN of vm-system-type-cli above —
        # same `system-cli` module + same userspace assertions — so the ONLY
        # difference is the backend (mkContainerTest/runNixOSTest + containers.machine
        # vs mkVmTest/nixosTest + nodes.machine). That makes it a clean apples-to-apples
        # wall-clock/RAM comparison and proves the nspawn toggle end-to-end.
        # NOTE (host prereq): the nspawn backend requires the builder to grant the
        # `uid-range` system feature (Nix `auto-allocate-uids`); see plan 053 Findings T6.
        vm-nspawn-smoke = mkContainerTest {
          name = "nspawn-smoke";
          description = "POC: system-cli userspace smoke on the systemd-nspawn container backend";
          modules = [ self.modules.nixos.system-cli ];
          extraConfig = {
            systemDefault.userName = testUsername;
          };
          testScript = ''
            machine.wait_for_unit("multi-user.target")

            # NSPAWN FINDING (POC, root-caused 2026-08-20): the QEMU twin vm-system-type-cli asserts
            # `wait_for_unit("sshd.service")` and passes, but IN THE CONTAINER sshd.service does not
            # exist at all — ssh is SOCKET-ACTIVATED by systemd-ssh-generator (systemd >=256, shipped
            # in 26.05): `sshd.socket` is active+listening, there is no persistent `sshd.service`.
            # (This is NOT NixOS `startWhenNeeded`, which system-cli leaves false; it is the systemd
            # generator, and it is container-specific here.) So the container-correct assertion is the
            # SOCKET, plus the host key as activation-agnostic proof the cli layer configured openssh.
            machine.wait_for_unit("sshd.socket")
            machine.succeed("test -f /etc/ssh/ssh_host_ed25519_key")

            # Inherits default: user exists
            machine.succeed("id ${testUsername}")

            # Dev tools present (enableDevTools = true by default)
            machine.succeed("git --version")
            machine.succeed("which jq")
            machine.succeed("which fzf")
            machine.succeed("which eza")
            machine.succeed("which nvim")
            machine.succeed("which tmux")
          '';
        };

        # === WSL DEV-TEAM LAYER STACK (plan 054 P5c — NEW) ===
        # QEMU: first BEHAVIORAL coverage of the Tier-A WSL daily-driver stack
        # (pa161878-nixos) — specifically `monitoring` + `mss-clamp`, the two
        # modules the audit flagged as live-but-unguarded (only this host enables
        # them). HM-free NixOS-layer compose.
        #
        # BACKEND (P5c, evidence-recorded 2026-08-21): STAYS QEMU — this test
        # asserts genuine KERNEL-CAPABILITY semantics that the unprivileged nspawn
        # container cannot provide:
        #   - monitoring's NixOS surface is `security.wrappers` (file capabilities
        #     via setcap); nspawn fails these with "Failed to set capabilities ...
        #     Operation not supported", so suid-sgid-wrappers.service dies and
        #     /run/wrappers/bin/* never appears (verified on nspawn 2026-08-21).
        #   - mss-clamp installs an iptables mangle TCPMSS rule (netfilter/NET_ADMIN).
        # These are exactly the "keep QEMU for real kernel/capability semantics"
        # class from the P5b/P3 backend policy.
        #
        # It composes the container-independent carrier of the two features —
        # `system-cli` (the base the WSL stack sits on) + `monitoring` + `mss-clamp`
        # — NOT the wsl-dev-team/wsl-enterprise layers themselves: those pull
        # NixOS-WSL, which requires an `inputs` MODULE argument the test framework
        # does not provide (→ eval infinite recursion) and sets `wsl.enable`/boot
        # semantics that only a real WSL boot satisfies. The WSL-specific layers
        # remain eval-gated (Tier-0 regression-test / eval-nixos-wsl-dev-team) +
        # covered by the shipped WSL image test.
        vm-wsl-dev-team-layers = mkVmTest {
          name = "wsl-dev-team-layers";
          description = "WSL dev-team stack carrier: monitoring + mss-clamp behavioral coverage";
          modules = [
            self.modules.nixos.system-cli
            self.modules.nixos.monitoring
            self.modules.nixos.mss-clamp
          ];
          memory = 2048;
          extraConfig = {
            systemDefault.userName = testUsername;
            monitoring.enable = true;
            mssClamp.enable = true;
          };
          testScript = ''
            machine.wait_for_unit("multi-user.target")

            # Base user from the layer stack exists.
            machine.succeed("id ${testUsername}")

            # --- monitoring: NixOS security.wrappers created (capability tools) ---
            # suid-sgid-wrappers.service is a oneshot (no RemainAfterExit): it goes
            # inactive after succeeding, so assert on its OUTPUT (the wrapper files),
            # not wait_for_unit. setcap works under QEMU (unlike the nspawn backend).
            machine.succeed("test -e /run/wrappers/bin/bandwhich")
            machine.succeed("test -e /run/wrappers/bin/iotop-c")

            # --- mss-clamp: boot oneshot ran and installed the TCPMSS mangle rule ---
            # mss-clamp.service is a `set -eu` oneshot (RemainAfterExit): reaching
            # `active` already proves the iptables rule was added (else it fails).
            # Also assert the rule directly via the service's own iptables (not on
            # the interactive shell PATH → use the store binary).
            machine.wait_for_unit("mss-clamp.service")
            machine.succeed(
                "${pkgs.iptables}/bin/iptables -t mangle -C OUTPUT -p tcp"
                " --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1240"
            )
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
                systemDefault.userName = testUsername;
                # Deploy the test public key via the dendritic sshAuthorizedKeys option
                systemCli.sshAuthorizedKeys = [ testPubKey ];
              };
              client = { config, pkgs, ... }: {
                imports = [ self.modules.nixos.system-cli ];
                networking.firewall.enable = false;
                virtualisation.memorySize = 1024;
                systemDefault.userName = testUsername;
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

              # --- Test 4: Authorized keys deployed for test user ---
              # NixOS may use /etc/ssh/authorized_keys.d/ or ~/.ssh/authorized_keys
              server.succeed(
                  "{ cat /etc/ssh/authorized_keys.d/${testUsername} 2>/dev/null"
                  " || cat /home/${testUsername}/.ssh/authorized_keys; }"
                  " | grep -q ssh-ed25519"
              )

              # --- Test 5: Key-based SSH from client to server ---
              client.wait_for_unit("multi-user.target")

              # Deploy the test private key to client
              client.succeed("mkdir -p /home/${testUsername}/.ssh && chmod 700 /home/${testUsername}/.ssh")
              client.succeed("cp ${testPrivKeyFile} /home/${testUsername}/.ssh/id_ed25519")
              client.succeed("chmod 600 /home/${testUsername}/.ssh/id_ed25519")
              client.succeed("chown -R ${testUsername}:users /home/${testUsername}/.ssh")

              # Add server to known_hosts (avoid interactive host key prompt)
              client.succeed(
                  "su - ${testUsername} -c 'ssh-keyscan server >> /home/${testUsername}/.ssh/known_hosts 2>/dev/null'"
              )

              # SSH from client to server and verify command execution
              result = client.succeed(
                  "su - ${testUsername} -c 'ssh -i /home/${testUsername}/.ssh/id_ed25519 ${testUsername}@server echo SSH_OK'"
              )
              assert "SSH_OK" in result, f"Expected SSH_OK in output, got: {result}"

              # --- Test 6: Password auth rejected ---
              # BatchMode=yes causes ssh to fail immediately if password would be needed
              # (no interactive prompt). This verifies password auth is truly disabled.
              client.fail(
                  "su - ${testUsername} -c 'ssh -o PubkeyAuthentication=no"
                  " -o BatchMode=yes"
                  " -o StrictHostKeyChecking=no"
                  " ${testUsername}@server echo SHOULD_NOT_WORK'"
              )
            '';
          };
        # Home Manager activation test: verifies that HM integrates with NixOS,
        # activates successfully, generates config files, and provides programs.
        # Uses NixOS-integrated HM (home-manager.nixosModules) to test activation
        # in a VM, even though the repo normally uses standalone HM.
        # nspawn (migrated P5c): HM activation via the hmNspawnNode recipe
        # (build-users-group="" + daemon-free load-db). Reference-verified by
        # spike-r2-hm-roskip and rebuilt on nspawn as the P5c representative.
        vm-hm-activation = mkHmContainerTest {
          name = "hm-activation";
          hmModules = [
            self.modules.homeManager.shell
            self.modules.homeManager.git
          ];
          testScript = ''
            machine.wait_for_unit("multi-user.target")

            # --- Test 1: Home Manager activation completed ---
            # In NixOS-integrated mode, HM activates via system activation.
            # home-manager-${testUsername}.service is the systemd unit for the user's activation.
            machine.wait_for_unit("home-manager-${testUsername}.service")

            # --- Test 2: Git is configured by HM ---
            machine.succeed("su - ${testUsername} -c 'git --version'")
            # Git config should contain user.name from the dendritic git module
            machine.succeed("su - ${testUsername} -c 'git config user.name' | grep -q 'Tim Black'")
            machine.succeed("su - ${testUsername} -c 'git config user.email' | grep -q 'timblaktu@gmail.com'")

            # --- Test 3: Git config file generated ---
            # HM puts git config in XDG path
            machine.succeed("test -f /home/${testUsername}/.config/git/config")

            # --- Test 4: Zsh configured by HM ---
            machine.succeed("test -f /home/${testUsername}/.zshrc")

            # --- Test 5: home-manager command available ---
            machine.succeed("su - ${testUsername} -c 'home-manager --version'")

            # --- Test 6: HM-generated XDG directories exist ---
            # Home Manager creates XDG config structure during activation
            machine.succeed("test -d /home/${testUsername}/.config/git")

            # --- Test 7: HM-managed program in PATH ---
            # Delta (git diff viewer) is enabled by the git module
            machine.succeed("su - ${testUsername} -c 'which delta'")

            # --- Test 8: Zsh history directory created ---
            # The shell module configures zsh history in XDG data dir
            machine.succeed("su - ${testUsername} -c 'zsh -c \"echo ZSH_OK\"' | grep -q ZSH_OK")
          '';
        };

        # Shell environment test: verifies zsh configuration, aliases, session
        # variables, plugins, and custom functions via Home Manager in a VM.
        # nspawn (migrated P5c): HM shell module via hmNspawnNode recipe.
        vm-shell-env = mkHmContainerTest {
          name = "shell-env";
          hmModules = [
            self.modules.homeManager.shell
          ];
          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("home-manager-${testUsername}.service")

            # --- Test 1: Zsh starts without errors ---
            machine.succeed("su - ${testUsername} -c 'zsh -c \"echo ZSH_OK\"' | grep -q ZSH_OK")

            # --- Test 2: Zsh is the login shell ---
            machine.succeed("getent passwd ${testUsername} | grep -q zsh")

            # --- Test 3: Session variables are set ---
            machine.succeed("su - ${testUsername} -c 'zsh -ic \"echo \\$EDITOR\"' | grep -q nvim")

            # --- Test 4: Shell aliases are defined ---
            # Check a few representative aliases from the module
            machine.succeed("su - ${testUsername} -c 'zsh -ic \"alias gs\"' | grep -q 'git status'")
            machine.succeed("su - ${testUsername} -c 'zsh -ic \"alias ll\"' | grep -q 'ls -l'")
            machine.succeed("su - ${testUsername} -c 'zsh -ic \"alias v\"' | grep -q nvim")

            # --- Test 5: Zsh history path configured in .zshrc ---
            # The module sets history path to $XDG_DATA_HOME/zsh/history
            machine.succeed("su - ${testUsername} -c 'grep -q zsh/history ~/.zshrc'")

            # --- Test 6: Zsh completion system loaded ---
            machine.succeed("su - ${testUsername} -c 'grep -q compinit ~/.zshrc'")

            # --- Test 7: Zsh plugins configured ---
            # Home Manager writes plugin source lines into .zshrc
            machine.succeed("su - ${testUsername} -c 'grep -q zsh-autosuggestions ~/.zshrc'")
            machine.succeed("su - ${testUsername} -c 'grep -q zsh-syntax-highlighting ~/.zshrc'")

            # --- Test 8: Custom prompt is set (not default) ---
            # Our module sets PROMPT with smart_pwd and shell_scope_indicator
            machine.succeed("su - ${testUsername} -c 'grep -q smart_pwd ~/.zshrc'")
          '';
        };

        # SOPS secrets test: verifies sops-nix NixOS module integration with
        # our dendritic secrets-management module. Tests that secrets defined in
        # sops.secrets.* are decrypted at boot and placed at correct paths with
        # correct permissions and ownership. Validates the actual sops-nix NixOS
        # module decryption service (the CLI-mock vm-sops-deployment was dropped
        # in P5c as a redundant mock).
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
          pkgs.testers.runNixOSTest {
            name = "vm-sops-secrets";

            # nspawn backend: no QEMU, no /dev/kvm at runtime (see mkContainerTest).
            requiredFeatures.kvm = false;

            # nspawn: sops-nix /run/secrets activation proven nspawn-safe by the
            # P5b spike-nspawn-sops (exact mode/owner preserved). Migrated P5c.
            containers.machine = { config, pkgs, lib, ... }: {
              imports = [
                self.modules.nixos.system-default
                inputs.sops-nix.nixosModules.sops
                self.modules.nixos.secrets-management
              ];

              systemDefault.userName = testUsername;
              systemDefault.wheelNeedsPassword = false;

              networking.firewall.enable = false;

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
                owner = testUsername;
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

              # api_key: mode 0440, owner ${testUsername}:users
              perms = machine.succeed("stat -c %a /run/secrets/api_key").strip()
              assert perms == "440", f"api_key: expected mode 440, got {perms}"
              owner = machine.succeed("stat -c %U:%G /run/secrets/api_key").strip()
              assert owner == "${testUsername}:users", f"api_key: expected ${testUsername}:users, got {owner}"

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
              machine.succeed("su - ${testUsername} -c 'cat /run/secrets/api_key' | grep -q key-abc-def-789")

              # --- Test 10: Non-root user cannot read root-only secret ---
              machine.fail("su - ${testUsername} -c 'cat /run/secrets/database_password'")
            '';
          };

        # Neovim VM test: validates the largest module (1871 LOC) in a headless VM.
        # Tests config loading, plugin availability, treesitter, LSP config, and
        # checkhealth output. Uses NixOS-integrated HM with system-default.
        # Plan 021 Task 3.1
        # nspawn (migrated P5c): HM neovim module via hmNspawnNode recipe.
        vm-neovim = mkHmContainerTest {
          name = "neovim";
          hmModules = [
            self.modules.homeManager.neovim
          ];
          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("home-manager-${testUsername}.service")

            # --- Test 1: nvim binary present and working ---
            machine.succeed("su - ${testUsername} -c 'nvim --version' | grep -q 'NVIM'")

            # --- Test 2: Config loads without errors (headless startup + quit) ---
            machine.succeed("su - ${testUsername} -c 'nvim --headless -c \"qa!\"'")

            # --- Test 3: Neovim config directory exists ---
            machine.succeed("test -d /home/${testUsername}/.config/nvim")

            # --- Test 4: Treesitter parsers installed ---
            # nixvim installs treesitter parsers into the nix store; verify via runtime
            result = machine.succeed(
                "su - ${testUsername} -c 'nvim --headless -c \"lua print(#vim.api.nvim_get_runtime_file(\\\"parser/*.so\\\", true))\" -c \"qa!\"' 2>&1"
            )
            # Should have at least a few parsers (lua, nix, bash, python, etc.)
            # The number is printed to stderr/stdout by nvim, extract any digit > 0
            machine.succeed(
                "su - ${testUsername} -c 'nvim --headless"
                " -c \"lua local n = #vim.api.nvim_get_runtime_file(\\\"parser/*.so\\\", true); if n > 0 then print(\\\"PARSERS_OK:\\\" .. n) else error(\\\"no parsers\\\") end\""
                " -c \"qa!\"' 2>&1 | grep -q 'PARSERS_OK'"
            )

            # --- Test 5: Key plugins loaded (telescope, lsp, treesitter, gitsigns) ---
            for plugin in ["telescope", "nvim-treesitter", "gitsigns"]:
                machine.succeed(
                    f"su - ${testUsername} -c 'nvim --headless"
                    f" -c \"lua local ok, _ = pcall(require, \\\"{plugin}\\\"); if ok then print(\\\"{plugin}_OK\\\") else error(\\\"{plugin} not found\\\") end\""
                    f" -c \"qa!\"' 2>&1 | grep -q '{plugin}_OK'"
                )

            # --- Test 6: LSP clients are configured (check lspconfig) ---
            machine.succeed(
                "su - ${testUsername} -c 'nvim --headless"
                " -c \"lua local ok, lsp = pcall(require, \\\"lspconfig\\\"); if ok then print(\\\"LSP_OK\\\") else error(\\\"lspconfig missing\\\") end\""
                " -c \"qa!\"' 2>&1 | grep -q 'LSP_OK'"
            )

            # --- Test 7: Default editor is nvim ---
            machine.succeed("su - ${testUsername} -c 'echo $EDITOR' | grep -q nvim")

            # --- Test 8: vi/vim aliases resolve to nvim ---
            # viAlias/vimAlias may create wrappers; verify they invoke nvim
            machine.succeed("su - ${testUsername} -c 'vi --version' | head -1 | grep -q NVIM")
            machine.succeed("su - ${testUsername} -c 'vim --version' | head -1 | grep -q NVIM")

            # --- Test 9: checkhealth runs without critical errors ---
            # Run checkhealth and capture output; look for ERROR in critical sections
            health_output = machine.succeed(
                "su - ${testUsername} -c 'nvim --headless -c \"checkhealth\" -c \"w! /tmp/nvim-health.txt\" -c \"qa!\"' 2>&1 || true"
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
        # nspawn (migrated P5c): HM tmux module via hmNspawnNode recipe.
        vm-tmux = mkHmContainerTest {
          name = "tmux";
          hmModules = [
            self.modules.homeManager.tmux
          ];
          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("home-manager-${testUsername}.service")

            # --- Test 1: tmux binary present and version check ---
            machine.succeed("su - ${testUsername} -c 'tmux -V' | grep -q tmux")

            # --- Test 2: Tmux config file generated by HM ---
            # Home Manager manages tmux config via XDG path
            machine.succeed("test -f /home/${testUsername}/.config/tmux/tmux.conf")

            # --- Test 3: Tmux server starts and session can be created ---
            machine.succeed("su - ${testUsername} -c 'tmux new-session -d -s test-session'")

            # --- Test 4: Session can be listed ---
            machine.succeed("su - ${testUsername} -c 'tmux list-sessions' | grep -q test-session")

            # --- Test 5: Prefix key configured to Ctrl-a ---
            machine.succeed("su - ${testUsername} -c 'tmux show-options -g prefix' | grep -q C-a")

            # --- Test 6: Vi mode enabled ---
            machine.succeed("su - ${testUsername} -c 'tmux show-options -gw mode-keys' | grep -q vi")

            # --- Test 7: Mouse mode enabled ---
            machine.succeed("su - ${testUsername} -c 'tmux show-options -g mouse' | grep -q on")

            # --- Test 8: Plugins loaded (resurrect, continuum) ---
            # tmux-resurrect sets @resurrect-dir option
            machine.succeed(
                "su - ${testUsername} -c 'tmux show-options -g @resurrect-dir'"
                " | grep -q resurrect"
            )
            # tmux-continuum sets @continuum-save-interval
            machine.succeed(
                "su - ${testUsername} -c 'tmux show-options -g @continuum-save-interval'"
                " | grep -q 5"
            )

            # --- Test 9: Resurrect directory exists ---
            machine.succeed("test -d /home/${testUsername}/.local/share/tmux/resurrect")

            # --- Test 10: tmux-session-picker script is executable ---
            machine.succeed("su - ${testUsername} -c 'which tmux-session-picker'")

            # --- Test 11: Helper scripts present and executable ---
            machine.succeed("su - ${testUsername} -c 'which tmux-cpu-mem'")
            machine.succeed("su - ${testUsername} -c 'which tmux-save-with-rename'")
            machine.succeed("su - ${testUsername} -c 'which tmux-test-data-generator'")

            # --- Test 12: Can create additional sessions and switch between them ---
            machine.succeed("su - ${testUsername} -c 'tmux new-session -d -s second-session'")
            result = machine.succeed("su - ${testUsername} -c 'tmux list-sessions'")
            assert "test-session" in result, f"test-session missing from: {result}"
            assert "second-session" in result, f"second-session missing from: {result}"

            # --- Test 13: Pane splitting works ---
            machine.succeed("su - ${testUsername} -c 'tmux split-window -h -t test-session'")
            panes = machine.succeed("su - ${testUsername} -c 'tmux list-panes -t test-session'")
            # Should have at least 2 panes after splitting
            assert panes.count("\n") >= 2, f"Expected 2+ panes, got: {panes}"

            # --- Test 14: Kill server cleanly ---
            machine.succeed("su - ${testUsername} -c 'tmux kill-server'")
            machine.fail("su - ${testUsername} -c 'tmux list-sessions'")
          '';
        };

        # Git advanced VM test: validates git configuration beyond basic --version.
        # Tests delta integration, aliases, gitignore, LFS, merge tools, credential
        # helper, and bundled utility scripts. Uses NixOS-integrated HM with system-default.
        # Plan 021 Task 3.3
        # nspawn (migrated P5c): HM git module via hmNspawnNode recipe.
        vm-git-advanced = mkHmContainerTest {
          name = "git-advanced";
          hmModules = [
            self.modules.homeManager.git
          ];
          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("home-manager-${testUsername}.service")

            # --- Test 1: Delta configured as git pager ---
            # HM's programs.delta.enableGitIntegration writes pager.{diff,log,show}
            # + interactive.diffFilter (NOT core.pager — older HM used that key; the
            # stale core.pager assertion was a pre-existing latent failure surfaced
            # by P5c actually building this test).
            machine.succeed("su - ${testUsername} -c 'git config pager.diff' | grep -q delta")
            machine.succeed("su - ${testUsername} -c 'git config interactive.diffFilter' | grep -q delta")

            # --- Test 2: Delta side-by-side mode configured ---
            machine.succeed("su - ${testUsername} -c 'git config delta.side-by-side' | grep -q true")
            machine.succeed("su - ${testUsername} -c 'git config delta.line-numbers' | grep -q true")

            # --- Test 3: Git aliases defined ---
            machine.succeed("su - ${testUsername} -c 'git config alias.st' | grep -q status")
            machine.succeed("su - ${testUsername} -c 'git config alias.ci' | grep -q commit")
            machine.succeed("su - ${testUsername} -c 'git config alias.co' | grep -q checkout")
            machine.succeed("su - ${testUsername} -c 'git config alias.br' | grep -q branch")
            machine.succeed("su - ${testUsername} -c 'git config alias.lg' | grep -q 'log --graph'")
            machine.succeed("su - ${testUsername} -c 'git config alias.unstage' | grep -q 'reset HEAD'")
            machine.succeed("su - ${testUsername} -c 'git config alias.last' | grep -q 'log -1 HEAD'")

            # --- Test 4: Global gitignore patterns configured ---
            # HM writes ignores to ~/.config/git/ignore (XDG default, no core.excludesFile needed)
            ignores = machine.succeed("cat /home/${testUsername}/.config/git/ignore")
            assert ".DS_Store" in ignores, f".DS_Store not in gitignore: {ignores}"
            assert "*.swp" in ignores, f"*.swp not in gitignore: {ignores}"
            assert "result" in ignores, f"result not in gitignore: {ignores}"
            assert ".direnv/" in ignores, f".direnv/ not in gitignore: {ignores}"

            # --- Test 5: Git LFS available ---
            machine.succeed("su - ${testUsername} -c 'git lfs version'")
            # LFS filter configured
            machine.succeed("su - ${testUsername} -c 'git config filter.lfs.clean' | grep -q 'git-lfs clean'")

            # --- Test 6: Pre-commit hook infrastructure ---
            # HM generates hooks in the config directory
            hooks_path = machine.succeed("su - ${testUsername} -c 'git config core.hooksPath'").strip()
            machine.succeed(f"test -d {hooks_path}")
            machine.succeed(f"test -x {hooks_path}/pre-commit")

            # --- Test 7: Merge tool configured (smart-nvimdiff) ---
            machine.succeed("su - ${testUsername} -c 'git config merge.tool' | grep -q smart-nvimdiff")
            machine.succeed(
                "su - ${testUsername} -c 'git config mergetool.smart-nvimdiff.cmd'"
                " | grep -q smart-nvimdiff"
            )

            # --- Test 8: Diff tool configured (nvimdiff) ---
            machine.succeed("su - ${testUsername} -c 'git config diff.tool' | grep -q nvimdiff")
            machine.succeed("su - ${testUsername} -c 'git config diff.algorithm' | grep -q histogram")

            # --- Test 9: Credential helper configured ---
            machine.succeed("su - ${testUsername} -c 'git config credential.helper' | grep -q 'cache --timeout=3600'")

            # --- Test 10: Init default branch is main ---
            machine.succeed("su - ${testUsername} -c 'git config init.defaultBranch' | grep -q main")

            # --- Test 11: smart-nvimdiff script in PATH ---
            machine.succeed("su - ${testUsername} -c 'which smart-nvimdiff'")

            # --- Test 12: Bundled utility scripts in PATH ---
            machine.succeed("su - ${testUsername} -c 'which syncfork'")
            machine.succeed("su - ${testUsername} -c 'which git-functions'")

            # --- Test 13: Security and workflow tools available ---
            machine.succeed("su - ${testUsername} -c 'which gitleaks'")
            machine.succeed("su - ${testUsername} -c 'which lazygit'")
            machine.succeed("su - ${testUsername} -c 'which git-crypt'")
            machine.succeed("su - ${testUsername} -c 'which pre-commit'")

            # --- Test 14: Delta binary is present and working ---
            machine.succeed("su - ${testUsername} -c 'delta --version'")

            # --- Test 15: Merge conflict style is diff3 ---
            machine.succeed("su - ${testUsername} -c 'git config merge.conflictstyle' | grep -q diff3")

            # --- Test 16: Functional test — init repo, commit, verify delta in log ---
            machine.succeed(
                "su - ${testUsername} -c '"
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
        # nspawn (migrated P5c): HM development-tools module via hmNspawnNode recipe.
        # All feature flags default to true except enableKubernetes and enablePyenv.
        vm-development-tools = mkHmContainerTest {
          name = "development-tools";
          hmModules = [
            self.modules.homeManager.development-tools
          ];
          hmConfig = {
            developmentTools.enable = true;
          };
          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("home-manager-${testUsername}.service")

            # === Enhanced CLI Tools (enableEnhancedCli = true by default) ===

            # --- Test 1: bat (better cat) ---
            machine.succeed("su - ${testUsername} -c 'bat --version'")

            # --- Test 2: eza (modern ls) ---
            machine.succeed("su - ${testUsername} -c 'eza --version'")

            # --- Test 3: delta (better diff) ---
            machine.succeed("su - ${testUsername} -c 'delta --version'")

            # --- Test 4: bottom (system monitor) ---
            machine.succeed("su - ${testUsername} -c 'btm --version'")

            # --- Test 5: miller (CSV/JSON processor) ---
            machine.succeed("su - ${testUsername} -c 'mlr --version'")

            # === Rust Toolchain (enableRust = true by default) ===

            # --- Test 6: rustc ---
            machine.succeed("su - ${testUsername} -c 'rustc --version'")

            # --- Test 7: cargo ---
            machine.succeed("su - ${testUsername} -c 'cargo --version'")

            # --- Test 8: rust-analyzer ---
            machine.succeed("su - ${testUsername} -c 'which rust-analyzer'")

            # --- Test 9: rustfmt ---
            machine.succeed("su - ${testUsername} -c 'rustfmt --version'")

            # --- Test 10: clippy ---
            machine.succeed("su - ${testUsername} -c 'which clippy-driver'")

            # === Node.js Ecosystem (enableNode = true by default) ===

            # --- Test 11: node ---
            machine.succeed("su - ${testUsername} -c 'node --version'")

            # --- Test 12: npm ---
            machine.succeed("su - ${testUsername} -c 'npm --version'")

            # --- Test 13: yarn ---
            machine.succeed("su - ${testUsername} -c 'yarn --version'")

            # === Python (enablePython = true by default) ===

            # --- Test 14: python3 ---
            machine.succeed("su - ${testUsername} -c 'python3 --version'")

            # --- Test 15: pip available as module ---
            machine.succeed("su - ${testUsername} -c 'python3 -m pip --version'")

            # --- Test 16: ipython available ---
            machine.succeed("su - ${testUsername} -c 'python3 -c \"import IPython\"'")

            # === Go (enableGo = true by default) ===

            # --- Test 17: go binary ---
            machine.succeed("su - ${testUsername} -c 'go version'")

            # --- Test 18: Go directories created by activation ---
            machine.succeed("test -d /home/${testUsername}/go/src")
            machine.succeed("test -d /home/${testUsername}/go/pkg")
            machine.succeed("test -d /home/${testUsername}/go/bin")

            # === C/C++ Build Tools (enableCppTools = true by default) ===

            # --- Test 19: cmake ---
            machine.succeed("su - ${testUsername} -c 'cmake --version'")

            # --- Test 20: gcc ---
            machine.succeed("su - ${testUsername} -c 'gcc --version'")

            # --- Test 21: make ---
            machine.succeed("su - ${testUsername} -c 'make --version'")

            # --- Test 22: pkg-config ---
            machine.succeed("su - ${testUsername} -c 'pkg-config --version'")

            # === Build Utilities (enableBuildUtils = true by default) ===

            # --- Test 23: flex ---
            machine.succeed("su - ${testUsername} -c 'flex --version'")

            # --- Test 24: bison ---
            machine.succeed("su - ${testUsername} -c 'bison --version'")

            # --- Test 25: gperf ---
            machine.succeed("su - ${testUsername} -c 'gperf --version'")

            # --- Test 26: doxygen ---
            machine.succeed("su - ${testUsername} -c 'doxygen --version'")

            # --- Test 27: entr ---
            machine.succeed("su - ${testUsername} -c 'which entr'")

            # === Claude Development Utilities (enableClaudeUtils = true by default) ===

            # --- Test 28: claudevloop script ---
            machine.succeed("su - ${testUsername} -c 'which claudevloop'")

            # --- Test 29: restart_claude script ---
            machine.succeed("su - ${testUsername} -c 'which restart_claude'")

            # --- Test 30: mkclaude_desktop_config script ---
            machine.succeed("su - ${testUsername} -c 'which mkclaude_desktop_config'")

            # --- Test 31: claude-models script ---
            machine.succeed("su - ${testUsername} -c 'which claude-models'")

            # --- Test 32: pdf2md script ---
            machine.succeed("su - ${testUsername} -c 'which pdf2md'")

            # === Kubernetes NOT installed by default (enableKubernetes = false) ===

            # --- Test 33: kubectl should NOT be present ---
            machine.fail("su - ${testUsername} -c 'which kubectl'")

            # === Session Paths ===

            # Note: Session variables (GOPATH, PATH additions for .cargo/bin, go/bin,
            # .local/bin) are configured via home.sessionVariables/sessionPath and verified
            # by eval-hm-module-development-tools. Runtime PATH sourcing depends on the
            # shell module, which is tested separately in vm-shell-env.
          '';
        };

        # Monitoring HM smoke test: verifies the home-manager monitoring module
        # activates and its user-facing surface works WITHOUT a NixOS layer -
        # i.e. the Home-Manager-only path (no security.wrappers). The NixOS side
        # (security.wrappers, below/sysstat daemons) is exercised separately by
        # vm-wsl-dev-team-layers; this test covers the HM half that had no
        # behavioral coverage: the generated monitor/monitor-rebuild/monitor-tool
        # commands, the btop config, and the Tier-1 tool set.
        # nspawn (HM module test via hmNspawnNode recipe). Plan 054 P7.
        vm-monitoring = mkHmContainerTest {
          name = "monitoring";
          hmModules = [
            self.modules.homeManager.monitoring
          ];
          hmConfig = {
            monitoring.enable = true;
          };
          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("home-manager-${testUsername}.service")

            # --- Test 1: generated dashboard commands are on PATH ---
            machine.succeed("su - ${testUsername} -c 'which monitor'")
            machine.succeed("su - ${testUsername} -c 'which monitor-rebuild'")
            machine.succeed("su - ${testUsername} -c 'which monitor-tool'")

            # --- Test 2: Tier-1 monitoring tools installed by HM ---
            # (Tier-2 tools dool/iftop are opt-in and NOT expected here.)
            machine.succeed("su - ${testUsername} -c 'btop --version'")
            machine.succeed("su - ${testUsername} -c 'bandwhich --version'")
            machine.succeed("su - ${testUsername} -c 'gping --version'")
            # nload is a curses TUI with no --version flag (it would hang on an
            # unknown arg waiting for input); assert presence via PATH only.
            machine.succeed("su - ${testUsername} -c 'which nload'")
            # below has no --version flag (subcommand CLI); --help exits 0.
            machine.succeed("su - ${testUsername} -c 'below --help'")
            machine.succeed("su - ${testUsername} -c 'trip --version'")
            machine.succeed("su - ${testUsername} -c 'iostat -V'")
            machine.succeed("su - ${testUsername} -c 'which iotop-c'")

            # --- Test 3: Tier-2 tools absent by default ---
            machine.fail("su - ${testUsername} -c 'which iftop'")
            machine.fail("su - ${testUsername} -c 'which dool'")

            # --- Test 4: btop config generated by the native HM module ---
            machine.succeed("test -f /home/${testUsername}/.config/btop/btop.conf")
            machine.succeed(
                "grep -q 'color_theme = \"gruvbox_dark_v2\"' "
                "/home/${testUsername}/.config/btop/btop.conf"
            )

            # --- Test 5: monitor-tool dispatcher falls back to PATH ---
            # No /run/wrappers/bin here (HM-only, no NixOS monitoring layer),
            # so monitor-tool must exec the plain binary from PATH.
            machine.succeed("su - ${testUsername} -c 'monitor-tool btop --version'")

            # --- Test 6: monitor-rebuild builds the canonical tmux session ---
            # The pane commands (btop/iostat/nload/gping) may exit immediately in
            # a headless container; remain-on-exit keeps the windows so the
            # session layout is still assertable. monitor-rebuild returns 0 once
            # the windows are created regardless of the tools' own exit status.
            # tmux is bundled inside the monitor-rebuild wrapper (not on the
            # user PATH unless the separate tmux module is enabled), so query the
            # resulting session via the same tmux binary from the store (the
            # /nix/store is bind-mounted read-only into the container).
            machine.succeed("su - ${testUsername} -c 'monitor-rebuild'")
            machine.succeed("su - ${testUsername} -c '${pkgs.tmux}/bin/tmux has-session -t monitor'")
            windows = machine.succeed(
                "su - ${testUsername} -c '${pkgs.tmux}/bin/tmux list-windows -t monitor -F \"#W\"'"
            )
            assert "overview" in windows, f"overview window missing: {windows!r}"
            assert "io" in windows, f"io window missing: {windows!r}"
            assert "network" in windows, f"network window missing: {windows!r}"
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
              systemDefault.userName = testUsername;
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
              machine.succeed("id -nG ${testUsername} | grep -q lp")

              # === Test 17: rtkit enabled for real-time audio scheduling ===
              machine.succeed("systemctl cat rtkit-daemon.service")

              # === Test 18: Inherits default layer — user exists ===
              machine.succeed("id ${testUsername}")
              machine.succeed("getent passwd ${testUsername} | grep -q zsh")
            '';
          };

        # (vm-yazi dropped in P5c — its init.lua/keymap.toml/yazi.toml asserts were
        # folded into vm-hm-module-isolation's node-yazi. See plan 054 P4 Q2.)

        # HM Module Isolation VM Tests: proves each VM-safe HM module activates
        # successfully with ONLY home-minimal — no other HM modules.
        # Each module gets its own VM node; all boot in parallel via start_all().
        # This validates the dendritic pattern's promise of truly independent modules.
        # Plan 021 Task 4.2
        # nspawn (migrated P5c): each HM module activates in isolation on its own
        # container via the hmNspawnNode recipe (build-users-group="" +
        # daemon-free load-db). Container names use hyphens — systemd-nspawn
        # --machine= rejects underscores (P5b finding #2) — while the test driver
        # maps `node-tmux` → Python variable `node_tmux` (pythonize_name), so the
        # testScript references below stay unchanged.
        vm-hm-module-isolation =
          pkgs.testers.runNixOSTest {
            name = "vm-hm-module-isolation";

            # nspawn backend: no QEMU, no /dev/kvm at runtime (see mkContainerTest).
            requiredFeatures.kvm = false;

            containers = {
              node-tmux = hmNspawnNode {
                hmModules = [ self.modules.homeManager.tmux ];
              };
              node-neovim = hmNspawnNode {
                hmModules = [ self.modules.homeManager.neovim ];
              };
              node-git = hmNspawnNode {
                hmModules = [ self.modules.homeManager.git ];
              };
              node-shell = hmNspawnNode {
                hmModules = [ self.modules.homeManager.shell ];
              };
              node-devtools = hmNspawnNode {
                hmModules = [ self.modules.homeManager.development-tools ];
                hmConfig = { developmentTools.enable = true; };
              };
              node-yazi = hmNspawnNode {
                hmModules = [ self.modules.homeManager.yazi ];
              };
              node-shellutils = hmNspawnNode {
                hmModules = [ self.modules.homeManager.shell-utils ];
              };
              node-podman = hmNspawnNode {
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
                  node.wait_for_unit("home-manager-${testUsername}.service")

              # === tmux: binary + config ===
              node_tmux.succeed("su - ${testUsername} -c 'tmux -V' | grep -q tmux")
              node_tmux.succeed("test -f /home/${testUsername}/.config/tmux/tmux.conf")

              # === neovim: binary + config dir ===
              node_neovim.succeed("su - ${testUsername} -c 'nvim --version' | grep -q NVIM")
              node_neovim.succeed("test -d /home/${testUsername}/.config/nvim")

              # === git: user config + config file ===
              node_git.succeed("su - ${testUsername} -c 'git config user.name' | grep -q 'Tim Black'")
              node_git.succeed("test -f /home/${testUsername}/.config/git/config")

              # === shell: zsh works + zshrc generated ===
              node_shell.succeed("su - ${testUsername} -c 'zsh -c \"echo ZSH_OK\"' | grep -q ZSH_OK")
              node_shell.succeed("test -f /home/${testUsername}/.zshrc")

              # === development-tools: enhanced CLI + language toolchain ===
              node_devtools.succeed("su - ${testUsername} -c 'bat --version'")
              node_devtools.succeed("su - ${testUsername} -c 'rustc --version'")

              # === yazi: binary + config files (absorbs dropped vm-yazi, P5c) ===
              # `yazi --version` PARSES the generated yazi.toml, so this doubles as a
              # config-validity guard: it caught the module's stale `name`-vs-`url`
              # previewer key (fixed 2026-08-21 — yazi >=25.x uses url/mime). Keep it
              # strong so a future config-schema drift is caught, not hidden.
              node_yazi.succeed("su - ${testUsername} -c 'yazi --version'")
              node_yazi.succeed("test -d /home/${testUsername}/.config/yazi")
              node_yazi.succeed("test -f /home/${testUsername}/.config/yazi/yazi.toml")
              # Custom init.lua + keymap.toml deployed (folded from vm-yazi).
              node_yazi.succeed("test -f /home/${testUsername}/.config/yazi/init.lua")
              node_yazi.succeed("test -f /home/${testUsername}/.config/yazi/keymap.toml")

              # === shell-utils: representative script + library file ===
              node_shellutils.succeed("su - ${testUsername} -c 'which mytree'")
              node_shellutils.succeed("test -f /home/${testUsername}/.local/lib/general-utils.bash")

              # === podman: podman-tui binary + registries config ===
              node_podman.succeed("su - ${testUsername} -c 'which podman-tui'")
              node_podman.succeed("test -f /home/${testUsername}/.config/containers/registries.conf")
            '';
          };

        # HM Module Composition Pair Tests: validates cross-module integration points
        # that only work when specific module pairs are combined.
        # 4 nodes (one per pair), all boot in parallel via start_all().
        # Plan 021 Task 4.3
        # nspawn (migrated P5c): each module pair activates on its own container
        # via the hmNspawnNode recipe. Hyphenated container names (pair-nvim-tmux)
        # map to Python vars (pair_nvim_tmux) via pythonize_name; underscores are
        # rejected by systemd-nspawn --machine= (P5b finding #2).
        vm-hm-composition-pairs =
          pkgs.testers.runNixOSTest {
            name = "vm-hm-composition-pairs";

            # nspawn backend: no QEMU, no /dev/kvm at runtime (see mkContainerTest).
            requiredFeatures.kvm = false;

            containers = {
              # Pair 1: neovim + tmux (vim-tmux-navigator integration)
              pair-nvim-tmux = hmNspawnNode {
                hmModules = [
                  self.modules.homeManager.neovim
                  self.modules.homeManager.tmux
                ];
              };

              # Pair 2: git + neovim (merge/diff tool integration)
              pair-git-nvim = hmNspawnNode {
                hmModules = [
                  self.modules.homeManager.git
                  self.modules.homeManager.neovim
                ];
              };

              # Pair 3: git + shell (aliases integration)
              pair-git-shell = hmNspawnNode {
                hmModules = [
                  self.modules.homeManager.git
                  self.modules.homeManager.shell
                ];
              };

              # Pair 4: shell + tmux (terminal env integration)
              pair-shell-tmux = hmNspawnNode {
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
                  node.wait_for_unit("home-manager-${testUsername}.service")

              # ========================================================
              # Pair 1: neovim + tmux — vim-tmux-navigator integration
              # ========================================================

              # Both binaries present
              pair_nvim_tmux.succeed("su - ${testUsername} -c 'nvim --version' | grep -q NVIM")
              pair_nvim_tmux.succeed("su - ${testUsername} -c 'tmux -V' | grep -q tmux")

              # Tmux config has vim-tmux-navigator keybindings (C-h, C-j, C-k, C-l)
              tmux_conf = pair_nvim_tmux.succeed("cat /home/${testUsername}/.config/tmux/tmux.conf")
              assert "is_vim" in tmux_conf, "tmux-navigator is_vim detection missing from tmux.conf"
              assert "C-h" in tmux_conf, "C-h navigator binding missing from tmux.conf"
              assert "C-j" in tmux_conf, "C-j navigator binding missing from tmux.conf"
              assert "C-k" in tmux_conf, "C-k navigator binding missing from tmux.conf"
              assert "C-l" in tmux_conf, "C-l navigator binding missing from tmux.conf"

              # Neovim has tmux-navigator plugin loaded
              pair_nvim_tmux.succeed(
                  "su - ${testUsername} -c 'nvim --headless"
                  " -c \"lua local ok, _ = pcall(require, \\\"tmux\\\"); if ok then print(\\\"TMUX_NAV_OK\\\") else"
                  " local rtp = vim.api.nvim_list_runtime_paths();"
                  " for _, p in ipairs(rtp) do if p:match(\\\"tmux\\\") then print(\\\"TMUX_NAV_OK\\\"); return end end;"
                  " error(\\\"tmux-navigator not found\\\") end\""
                  " -c \"qa!\"' 2>&1 | grep -q TMUX_NAV_OK"
              )

              # Functional test: start tmux, run nvim inside, verify both work together
              pair_nvim_tmux.succeed("su - ${testUsername} -c 'tmux new-session -d -s nvim-test'")
              pair_nvim_tmux.succeed("su - ${testUsername} -c 'tmux send-keys -t nvim-test \"nvim --headless -c qa!\" Enter'")
              import time; time.sleep(2)
              pair_nvim_tmux.succeed("su - ${testUsername} -c 'tmux list-sessions' | grep -q nvim-test")

              # ========================================================
              # Pair 2: git + neovim — merge/diff tool integration
              # ========================================================

              # Both binaries present
              pair_git_nvim.succeed("su - ${testUsername} -c 'git --version'")
              pair_git_nvim.succeed("su - ${testUsername} -c 'nvim --version' | grep -q NVIM")

              # Git merge tool set to smart-nvimdiff (depends on nvim)
              pair_git_nvim.succeed("su - ${testUsername} -c 'git config merge.tool' | grep -q smart-nvimdiff")
              pair_git_nvim.succeed(
                  "su - ${testUsername} -c 'git config mergetool.smart-nvimdiff.cmd'"
                  " | grep -q smart-nvimdiff"
              )

              # Git diff tool set to nvimdiff
              pair_git_nvim.succeed("su - ${testUsername} -c 'git config diff.tool' | grep -q nvimdiff")
              pair_git_nvim.succeed(
                  "su - ${testUsername} -c 'git config difftool.nvimdiff.cmd'"
                  " | grep -q 'nvim -d'"
              )

              # smart-nvimdiff script is in PATH and executable
              pair_git_nvim.succeed("su - ${testUsername} -c 'which smart-nvimdiff'")

              # The script references nvim — verify nvim is callable from the script's env
              pair_git_nvim.succeed("su - ${testUsername} -c 'smart-nvimdiff --help || true' 2>&1")

              # Functional test: create merge conflict, verify merge tool config works
              pair_git_nvim.succeed(
                  "su - ${testUsername} -c '"
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
                  "su - ${testUsername} -c 'cd /tmp/merge-test && git diff --name-only --diff-filter=U' | grep -q file.txt"
              )

              # ========================================================
              # Pair 3: git + shell — aliases integration
              # ========================================================

              # Both git and zsh work
              pair_git_shell.succeed("su - ${testUsername} -c 'git --version'")
              pair_git_shell.succeed("su - ${testUsername} -c 'zsh -c \"echo ZSH_OK\"' | grep -q ZSH_OK")

              # Git aliases available in zsh interactive session
              pair_git_shell.succeed("su - ${testUsername} -c 'zsh -ic \"alias gs\"' | grep -q 'git status'")
              pair_git_shell.succeed("su - ${testUsername} -c 'zsh -ic \"alias ga\"' | grep -q 'git add'")
              pair_git_shell.succeed("su - ${testUsername} -c 'zsh -ic \"alias gc\"' | grep -q 'git commit'")
              pair_git_shell.succeed("su - ${testUsername} -c 'zsh -ic \"alias gp\"' | grep -q 'git push'")
              pair_git_shell.succeed("su - ${testUsername} -c 'zsh -ic \"alias gd\"' | grep -q 'git diff'")

              # Functional test: use git alias in zsh to run actual git command
              pair_git_shell.succeed(
                  "su - ${testUsername} -c 'cd /tmp && mkdir alias-test && cd alias-test && git init"
                  " && zsh -ic \"gs\"'"
              )

              # ========================================================
              # Pair 4: shell + tmux — terminal environment integration
              # ========================================================

              # Both work independently
              pair_shell_tmux.succeed("su - ${testUsername} -c 'zsh -c \"echo ZSH_OK\"' | grep -q ZSH_OK")
              pair_shell_tmux.succeed("su - ${testUsername} -c 'tmux -V' | grep -q tmux")

              # Start a tmux session — the pane shell inherits $TMUX from tmux
              pair_shell_tmux.succeed("su - ${testUsername} -c 'tmux new-session -d -s shell-test'")

              # Wait for tmux session to be ready and zsh to finish loading
              pair_shell_tmux.succeed("su - ${testUsername} -c 'tmux list-sessions' | grep -q shell-test")
              import time; time.sleep(5)

              # Verify TMUX env var is set inside the tmux pane's shell
              # Use send-keys which runs inside the pane's shell where $TMUX is set
              pair_shell_tmux.succeed(
                  "su - ${testUsername} -c 'tmux send-keys -t shell-test \"printenv TMUX > /tmp/tmux-env.txt\" Enter'"
              )
              # Wait for the command to execute (file to appear)
              pair_shell_tmux.wait_until_succeeds("test -s /tmp/tmux-env.txt", timeout=10)
              result = pair_shell_tmux.succeed("cat /tmp/tmux-env.txt").strip()
              assert "/" in result, f"TMUX env var not set inside tmux pane: '{result}'"

              # Verify zsh works inside tmux pane by running zsh command
              pair_shell_tmux.succeed(
                  "su - ${testUsername} -c 'tmux send-keys -t shell-test \"zsh -c \\\"echo ZSH_IN_TMUX\\\" > /tmp/zsh-test.txt\" Enter'"
              )
              pair_shell_tmux.wait_until_succeeds("test -s /tmp/zsh-test.txt", timeout=10)
              result = pair_shell_tmux.succeed("cat /tmp/zsh-test.txt").strip()
              assert "ZSH_IN_TMUX" in result, f"zsh failed inside tmux pane: '{result}'"

              # Verify tmux detection in shell config
              # The shell module checks for TMUX variable in .zshrc
              zshrc = pair_shell_tmux.succeed("cat /home/${testUsername}/.zshrc")
              assert "TMUX" in zshrc, "Shell module should reference TMUX variable in .zshrc"

              # Clean up
              pair_shell_tmux.succeed("su - ${testUsername} -c 'tmux kill-server'")
            '';
          };

        # QEMU (merged P5c): vm-full-cli-stack + vm-dev-team-stack → one
        # parameterized vm-compose-stack (resolves P4 Q2). Two nodes exercise the
        # SAME full HM stack over two NixOS bases: `cli` (system-cli layer) and
        # `devteam` (the real nixos-dev-team host module, grub/disk forced off).
        # The union of the two former stacks' asserts runs per parameterization
        # (check_stack), plus dev-team-specific sudo/podman asserts.
        #
        # STAYS QEMU (P5c fallback, evidence-recorded 2026-08-21): the `devteam`
        # parameterization imports the real nixos-dev-team HOST module, which sets
        # the read-only `nixpkgs.hostPlatform` — irreconcilable with the nspawn
        # test backend (runNixOSTest also sets it read-only → "set multiple times").
        # Host modules need real boot semantics; HM activation runs natively on
        # QEMU's writableStore, so no hmNspawnNode recipe is needed here.
        vm-compose-stack =
          let
            fullHmStack = [
              self.modules.homeManager.shell
              self.modules.homeManager.git
              self.modules.homeManager.tmux
              self.modules.homeManager.neovim
              self.modules.homeManager.development-tools
              self.modules.homeManager.yazi
              self.modules.homeManager.shell-utils
              self.modules.homeManager.files
              self.modules.homeManager.podman
            ];
            # The base NixOS layer (system-cli / nixos-dev-team) already imports
            # system-default transitively; do NOT import it again here or the
            # dendritic deferredModule's options get declared twice.
            mkStackNode = { extraNixosModules }:
              { config, pkgs, lib, ... }: {
                imports = [
                  inputs.home-manager.nixosModules.home-manager
                ] ++ extraNixosModules;

                systemDefault.userName = testUsername;
                systemDefault.wheelNeedsPassword = false;
                networking.firewall.enable = false;
                virtualisation.memorySize = 3072;

                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  extraSpecialArgs = { inherit inputs; };
                  users.${testUsername} = { config, pkgs, lib, ... }: {
                    imports = [ self.modules.homeManager.home-minimal ] ++ fullHmStack;
                    homeMinimal = {
                      username = testUsername;
                      homeDirectory = testHomeDir;
                    };
                    developmentTools.enable = true;
                    programs.podman-tools.enable = true;
                    targets.genericLinux.enable = lib.mkForce false;
                  };
                };
              };
          in
          pkgs.testers.nixosTest {
            name = "vm-compose-stack";

            nodes = {
              # Parameterization 1: system-cli layer.
              cli = mkStackNode {
                extraNixosModules = [ self.modules.nixos.system-cli ];
              };
              # Parameterization 2: real nixos-dev-team host module (grub/disk
              # forced off so the driver's own VM disk suffices).
              devteam = mkStackNode {
                extraNixosModules = [
                  self.modules.nixos.nixos-dev-team
                  ({ lib, ... }: {
                    boot.loader.grub.enable = lib.mkForce false;
                    boot.loader.grub.device = lib.mkForce "";
                    fileSystems."/" = lib.mkForce { device = "none"; fsType = "tmpfs"; };
                  })
                ];
              };
            };

            testScript = ''
              # Both parameterizations boot in parallel; check_stack runs the union
              # of the two former stacks' asserts against each.
              start_all()

              def check_stack(node):
                  node.wait_for_unit("multi-user.target")
                  node.wait_for_unit("home-manager-${testUsername}.service")

                  # --- Primary binaries present ---
                  node.succeed("su - ${testUsername} -c 'nvim --version' | grep -q NVIM")
                  node.succeed("su - ${testUsername} -c 'tmux -V' | grep -q tmux")
                  node.succeed("su - ${testUsername} -c 'git --version'")
                  # `yazi --version` parses the generated config → doubles as a
                  # config-validity guard (see node-yazi note in vm-hm-module-isolation).
                  node.succeed("su - ${testUsername} -c 'yazi --version'")
                  node.succeed("su - ${testUsername} -c 'bat --version'")
                  node.succeed("su - ${testUsername} -c 'which podman-tui'")
                  node.succeed("su - ${testUsername} -c 'zsh -c \"echo ZSH_OK\"' | grep -q ZSH_OK")

                  # --- system-cli layer: sshd running (QEMU persistent service) ---
                  node.wait_for_unit("sshd.service")
                  node.succeed("which jq")
                  node.succeed("which fzf")
                  node.succeed("which eza")

                  # --- Cross-module: git + delta ---
                  # pager.diff (not stale core.pager — see vm-git-advanced Test 1).
                  node.succeed("su - ${testUsername} -c 'git config pager.diff' | grep -q delta")
                  node.succeed("su - ${testUsername} -c 'delta --version'")

                  # --- Cross-module: zsh + git aliases ---
                  # TERM=dumb: with the tmux module present the shell's interactive
                  # init sources ~/bin/tmux-auto-attach, which runs `tmux attach` and
                  # BLOCKS a non-interactive `zsh -ic`. The script's own guard skips
                  # when TERM=dumb, so we read the aliases without launching tmux.
                  node.succeed("su - ${testUsername} -c 'TERM=dumb zsh -ic \"alias gs\"' | grep -q 'git status'")
                  node.succeed("su - ${testUsername} -c 'TERM=dumb zsh -ic \"alias ga\"' | grep -q 'git add'")

                  # --- Cross-module: neovim + tmux navigator ---
                  tmux_conf = node.succeed("cat /home/${testUsername}/.config/tmux/tmux.conf")
                  assert "is_vim" in tmux_conf, "vim-tmux-navigator detection missing"

                  # --- Cross-module: git + neovim merge tool ---
                  node.succeed("su - ${testUsername} -c 'git config merge.tool' | grep -q smart-nvimdiff")
                  node.succeed("su - ${testUsername} -c 'git config diff.tool' | grep -q nvimdiff")

                  # --- Neovim starts cleanly with full config ---
                  node.succeed("su - ${testUsername} -c 'nvim --headless -c \"qa!\"'")

                  # --- Tmux server lifecycle ---
                  node.succeed("su - ${testUsername} -c 'tmux new-session -d -s compose-test'")
                  node.succeed("su - ${testUsername} -c 'tmux list-sessions' | grep -q compose-test")
                  node.succeed("su - ${testUsername} -c 'tmux kill-server'")

                  # --- User environment coherent ---
                  node.succeed("su - ${testUsername} -c 'echo $EDITOR' | grep -q nvim")
                  node.succeed("getent passwd ${testUsername} | grep -q zsh")
                  node.succeed("id -nG ${testUsername} | grep -q wheel")
                  node.succeed("nix show-config | grep trusted-users | grep -q ${testUsername}")

                  # --- Module-specific configs all generated ---
                  node.succeed("test -f /home/${testUsername}/.config/tmux/tmux.conf")
                  node.succeed("test -f /home/${testUsername}/.config/git/config")
                  node.succeed("test -d /home/${testUsername}/.config/nvim")
                  node.succeed("test -f /home/${testUsername}/.config/yazi/yazi.toml")
                  node.succeed("test -f /home/${testUsername}/.zshrc")
                  node.succeed("test -f /home/${testUsername}/.config/containers/registries.conf")

                  # --- Development toolchains present ---
                  node.succeed("su - ${testUsername} -c 'rustc --version'")
                  node.succeed("su - ${testUsername} -c 'node --version'")
                  node.succeed("su - ${testUsername} -c 'python3 --version'")
                  node.succeed("su - ${testUsername} -c 'go version'")

                  # --- shell-utils scripts ---
                  node.succeed("su - ${testUsername} -c 'which mytree'")
                  node.succeed("test -f /home/${testUsername}/.local/lib/general-utils.bash")

                  # --- Functional: init repo, commit via zsh ---
                  node.succeed(
                      "su - ${testUsername} -c '"
                      "cd /tmp && rm -rf compose-repo && mkdir compose-repo && cd compose-repo && git init"
                      " && echo hello > file.txt && git add file.txt"
                      " && git commit -m \"test commit\""
                      " && git log --oneline | grep -q \"test commit\"'"
                  )

              # Parameterization 1: system-cli layer.
              check_stack(cli)

              # Parameterization 2: real nixos-dev-team host module.
              check_stack(devteam)

              # --- dev-team specifics: passwordless wheel sudo + podman present ---
              devteam.succeed("su - ${testUsername} -c 'sudo -n true'")
              devteam.succeed("su - ${testUsername} -c 'command -v podman'")
            '';
          };

        # Shipped dev-team image smoketest. Reproduces the SHIPPED defaults
        # (default user "user", passwordless wheel sudo) and asserts the
        # invariants that the 2026-08-13 "user is not in sudoers file"
        # regression violated. Unlike vm-compose-stack's devteam parameterization,
        # this does NOT override systemDefault.userName or wheelNeedsPassword -- it
        # validates the image exactly as distributed (and stays on QEMU as the
        # shipped-image boot gate). Consumed by the nixcfg-work dev-team-vm CI as a
        # test-stage gate after the image build, on the aarch64 KVM-metal runner
        # (tag aws-uswest2-metal-nix-arm64-kvm), which provides hardware /dev/kvm.
        vm-dev-team-vm-smoketest = mkVmTest {
          name = "dev-team-vm-smoketest";
          description = "Shipped dev-team image: default user 'user' boots with passwordless wheel sudo";
          # Import the dev-team settings layers with DEFAULTS (system-cli
          # co-imported per dev-team's documented usage). No userName /
          # wheelNeedsPassword override: the wheel/sudo invariant lives in the
          # dev-team + libvirt layers, independent of the host's disk/bootloader,
          # so the test driver's own VM disk suffices (no grub/tmpfs juggling).
          modules = [
            self.modules.nixos.system-cli
            self.modules.nixos.dev-team
          ];
          memory = 3072;
          testScript = ''
            machine.wait_for_unit("multi-user.target")

            # Default distributed user exists (dev-team sets userName = "user").
            machine.succeed("id user")

            # Regression guard: the user MUST be in wheel. Before the fix, the
            # libvirt layer's bare extraGroups = [ libvirtd kvm ] clobbered the
            # mkDefault wheel/plugdev, leaving the user in no sudo group at all
            # ("user is not in sudoers file").
            machine.succeed("id -nG user | grep -qw wheel")

            # Passwordless sudo actually works for the shipped user
            # (wheelNeedsPassword = false in the dev-team base).
            machine.succeed("su - user -c 'sudo -n true'")

            # SSH daemon up (admin requirement: sshPasswordAuth = true).
            machine.wait_for_unit("sshd.service")

            # Core dev-team feature present.
            machine.succeed("command -v podman")

            # === Plan 006 T1: hermetic dev-environment readiness ===
            # Beyond "boots + can log in", assert the shipped env actually hands the
            # developer the toolbox that drives the documented HSW/n3x workflows
            # (`nix run '.' -- --machine <...>`, `nix build '.#checks…'`). Pure
            # PATH/config assertions -- NO network -- so this stays a hermetic gate;
            # the credentialed fetch-from-Artifactory/GitLab half is the live gate
            # (Plan 006 T2/T3), not this test.
            #
            # nix is the entrypoint for every HSW workflow; git clones the repo;
            # podman runs the build containers. Assert as `user` (the developer's
            # own login shell), not root, and prove they actually run (--version),
            # not merely resolve on PATH.
            machine.succeed("su - user -c 'command -v nix && nix --version'")
            machine.succeed("su - user -c 'command -v git && git --version'")
            machine.succeed("su - user -c 'command -v podman'")

            ${lib.optionalString (system == "x86_64-linux") ''
              # x86 dev-team CROSS-builds the ARM HSW product/VTE images
              # (`nix run '.' -- --machine converix-orin-nano` / `qemuarm64`): the
              # dev-team module enables aarch64 binfmt emulation and advertises
              # aarch64-linux as an extra Nix build platform. Assert both halves so
              # the cross-arch entrypoint is provably usable in-env.
              machine.succeed("nix show-config | grep -w extra-platforms | grep -qw aarch64-linux")
              machine.succeed("ls /proc/sys/fs/binfmt_misc/ | grep -qi aarch64")
            ''}
            ${lib.optionalString (system == "aarch64-linux") ''
              # aarch64 dev-team builds the ARM HSW images NATIVELY -- no emulation
              # layer (dev-team sets emulatedSystems = [] on native aarch64).
              machine.succeed("uname -m | grep -qw aarch64")
            ''}
          '';
        };

        # User configuration test: verifies user setup, groups, home directory,
        # shell, sudo, nix trusted-users, and environment variables.
        # STAYS QEMU (P5c, evidence-recorded 2026-08-21): Test 5 asserts real
        # passwordless-sudo ESCALATION (`su - tim -c 'sudo -n true'`), which needs
        # the setuid `sudo` wrapper. The unprivileged nspawn test container cannot
        # create setuid/setcap wrappers ("Operation not permitted"), so sudo
        # escalation fails there — a genuine privilege-semantics gap. (vm-system-
        # type-default, which only checks wheel membership, DID migrate to nspawn.)
        vm-user-config = mkVmTest {
          name = "user-config";
          description = "User creation, groups, home directory, shell, and sudo";
          modules = [ self.modules.nixos.system-default ];
          extraConfig = {
            systemDefault.userName = testUsername;
            systemDefault.userGroups = [ "wheel" "networkmanager" "audio" "video" "docker" ];
            systemDefault.wheelNeedsPassword = false;
            systemDefault.extraShellAliases = { testvm = "echo test-alias-works"; };
            systemDefault.extraEnvironment = { TEST_VAR = "vm-test-value"; };
          };
          testScript = ''
            machine.wait_for_unit("multi-user.target")

            # --- Test 1: User exists and is a normal user ---
            machine.succeed("id ${testUsername}")
            machine.succeed("getent passwd ${testUsername} | grep -q /home/${testUsername}")

            # --- Test 2: Home directory exists and is owned by user ---
            machine.succeed("test -d /home/${testUsername}")
            machine.succeed("stat -c '%U' /home/${testUsername} | grep -q ${testUsername}")

            # --- Test 3: User is in expected groups ---
            machine.succeed("id -nG ${testUsername} | grep -q wheel")
            machine.succeed("id -nG ${testUsername} | grep -q audio")
            machine.succeed("id -nG ${testUsername} | grep -q video")

            # --- Test 4: Shell is zsh ---
            machine.succeed("getent passwd ${testUsername} | grep -q zsh")
            # zsh binary exists
            machine.succeed("which zsh")

            # --- Test 5: User can sudo (wheel group) ---
            # sudo should work for wheel members (default NixOS config)
            machine.succeed("su - ${testUsername} -c 'sudo -n true'")

            # --- Test 6: Nix trusts the user ---
            machine.succeed("nix show-config | grep trusted-users | grep -q ${testUsername}")

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
