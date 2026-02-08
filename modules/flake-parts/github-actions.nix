# modules/flake-parts/github-actions.nix
# Configurable GitHub Actions local validation
{ inputs, self, ... }: {
  perSystem = { config, self', inputs', pkgs, system, ... }:
    let
      # Configuration for GitHub Actions validation
      githubActionsConfig = {
        enable = false; # Disabled by default
        jobs = {
          verify-sops = { enable = true; timeout = 30; };
          audit-permissions = { enable = true; timeout = 30; };
          gitleaks = { enable = true; timeout = 120; };
          semgrep = { enable = true; timeout = 120; };
          trufflehog = { enable = true; timeout = 120; };
        };
      };

      # Override with user configuration if it exists
      userConfig =
        if builtins.pathExists ./../../github-actions.nix
        then import ./../../github-actions.nix
        else { };

      finalConfig = pkgs.lib.recursiveUpdate githubActionsConfig userConfig;

      # Helper to create the GitHub Actions validation derivation
      mkGithubActionsCheck = config: pkgs.runCommand "github-actions"
        {
          meta = {
            description = "Run configured GitHub Actions locally using act";
            maintainers = [ ];
            timeout = 600; # 10 minutes max
          };
          nativeBuildInputs = with pkgs; [
            act
            podman
            bash
            coreutils
          ];
        } ''
        echo "🚀 Running GitHub Actions validation..."

        # Check dependencies
        if ! command -v act >/dev/null || ! command -v podman >/dev/null; then
          echo "⚠️  act or podman not available, skipping GitHub Actions validation"
          echo "Install with: nix shell nixpkgs#act nixpkgs#podman"
          touch $out
          exit 0
        fi

        export DOCKER_HOST="unix:///run/podman/podman.sock"
        if [ ! -S "''${DOCKER_HOST#unix://}" ]; then
          echo "⚠️  Podman socket not available at $DOCKER_HOST"
          echo "Start with: systemctl --user start podman.socket"
          touch $out
          exit 0
        fi

        # Change to source directory (act needs .github/workflows/)
        cd ${./../..}

        echo "📋 Available GitHub Actions jobs:"
        act -l || {
          echo "⚠️  No GitHub Actions workflows found, skipping"
          touch $out
          exit 0
        }

        # Run enabled jobs
        failed=0
        total=0
        ${pkgs.lib.concatMapStringsSep "\n" (jobName:
          let jobConfig = config.jobs.${jobName}; in
          pkgs.lib.optionalString jobConfig.enable ''
            total=$((total + 1))
            echo "🏃 Running ${jobName} (timeout: ${toString jobConfig.timeout}s)..."
            if timeout ${toString jobConfig.timeout} act -j "${jobName}" --quiet; then
              echo "✅ ${jobName} passed"
            else
              echo "❌ ${jobName} failed"
              ((failed++))
            fi
          ''
        ) (builtins.attrNames config.jobs)}

        echo ""
        echo "=== GitHub Actions Results ==="
        echo "Total jobs: $total"
        echo "Failed: $failed"

        if [ $failed -eq 0 ]; then
          echo "🎉 All GitHub Actions validation passed!"
          touch $out
        else
          echo "💥 $failed GitHub Actions jobs failed"
          exit 1
        fi
      '';

    in
    {
      checks = pkgs.lib.optionalAttrs finalConfig.enable {
        github-actions = mkGithubActionsCheck finalConfig;
      };

      # Convenience apps for managing configuration
      apps = {
        # Show current github-actions configuration
        show-github-actions-config = {
          type = "app";
          meta.description = "Show current GitHub Actions validation configuration";
          program = "${pkgs.writeShellScriptBin "show-github-actions-config" ''
          echo "GitHub Actions Validation Configuration:"
          echo "======================================"
          echo ""
          echo "Enabled: ${if finalConfig.enable then "✅ YES" else "❌ NO"}"
          echo ""
          echo "Jobs configuration:"
          ${pkgs.lib.concatMapStringsSep "\n" (jobName:
            let jobConfig = finalConfig.jobs.${jobName}; in
            ''echo "  ${jobName}: ${if jobConfig.enable then "✅" else "❌"} (timeout: ${toString jobConfig.timeout}s)"''
          ) (builtins.attrNames finalConfig.jobs)}
          echo ""
          echo "To enable: Create github-actions.nix with { enable = true; }"
          echo "To configure jobs: Edit github-actions.nix jobs.* settings"
          echo "To run: nix build .#checks.${system}.github-actions"
        ''}/bin/show-github-actions-config";
        };

        # Generate example configuration file
        init-github-actions-config = {
          type = "app";
          meta.description = "Generate example github-actions.nix configuration";
          program = "${pkgs.writeShellScriptBin "init-github-actions-config" ''
          if [ -f github-actions.nix ]; then
            echo "⚠️  github-actions.nix already exists"
            exit 1
          fi

          cat > github-actions.nix << 'EOF'
# GitHub Actions local validation configuration
{
  enable = true; # Enable GitHub Actions validation in flake checks

  jobs = {
    # Fast security checks (~30s each)
    verify-sops = { enable = true; timeout = 30; };
    audit-permissions = { enable = true; timeout = 30; };

    # Comprehensive security checks (~2min each)
    gitleaks = { enable = true; timeout = 120; };
    semgrep = { enable = true; timeout = 120; };
    trufflehog = { enable = true; timeout = 120; };
  };
}
EOF

          echo "✅ Created github-actions.nix"
          echo ""
          echo "Next steps:"
          echo "1. Edit github-actions.nix to configure which jobs to run"
          echo "2. Run: nix build .#checks.${system}.github-actions"
          echo "3. GitHub Actions will now be included in: nix flake check"
        ''}/bin/init-github-actions-config";
        };
      };
    };
}
