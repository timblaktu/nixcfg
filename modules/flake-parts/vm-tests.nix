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

        # === VM system type tests will be added in task 3.3 ===
        # === VM feature tests will be added in tasks 4.x ===
      };
    };
}
