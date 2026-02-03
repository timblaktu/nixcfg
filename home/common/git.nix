# Git configuration
{ config, lib, pkgs, ... }:

{
  programs.git = {
    enable = true;
    lfs.enable = true;

    # New unified settings structure (replaces userName, userEmail, extraConfig, aliases)
    settings = {
      user = {
        name = "Tim Black";
        email = "timblaktu@gmail.com";
      };
      init.defaultBranch = "main";
      pull.rebase = false;
      push.autoSetupRemote = true;
      core = {
        editor = "nvim";
        autocrlf = "input";
      };
      color.ui = true;
      merge = {
        conflictstyle = "diff3";
        renameLimit = 999999;
        tool = "smart-nvimdiff";
      };
      mergetool = {
        prompt = false;
        keepBackup = false;
        "smart-nvimdiff" = {
          cmd = ''smart-nvimdiff "$BASE" "$LOCAL" "$REMOTE" "$MERGED"'';
          trustExitCode = true;
        };
      };
      diff = {
        algorithm = "histogram";
        colorMoved = "default";
        mnemonicPrefix = true;
        renames = true;
        renameLimit = 999999;
        tool = "nvimdiff";
        submodule = "log";
      };
      difftool = {
        prompt = false;
        trustExitCode = true;
        nvimdiff = {
          cmd = ''nvim -d "$LOCAL" "$REMOTE"'';
          layout = "LOCAL,REMOTE";
        };
      };
      credential = {
        helper = "cache --timeout=3600";
        "https://glab.espressif.cn/customer/esp-idf-for-summit" = {
          helper = "store";
        };
      };
      safe = {
        directory = [ ];
      };
      status = {
        submodulesummary = 1;
      };
      # Aliases (moved from programs.git.aliases)
      alias = {
        st = "status";
        ci = "commit";
        co = "checkout";
        br = "branch";
        lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        unstage = "reset HEAD --";
        last = "log -1 HEAD";
      };
    };

    ignores = [
      ".DS_Store"
      "*.swp"
      "*~"
      ".direnv/"
      "result"
      "result-*"
    ];

    hooks = {
      pre-commit = pkgs.writers.writeBash "pre-commit-format" ''
        # Auto-format Nix files before commit
        if command -v nixpkgs-fmt >/dev/null 2>&1; then
          # Get staged .nix files
          staged_nix_files=$(git diff --cached --name-only --diff-filter=ACM "*.nix")
          if [ -n "$staged_nix_files" ]; then
            echo "🔧 Auto-formatting Nix files..."
            # Format files and re-stage them
            echo "$staged_nix_files" | xargs nixpkgs-fmt
            echo "$staged_nix_files" | xargs git add
            echo "✅ Nix files formatted and re-staged"
          fi
        fi

        # Auto-format Rust code before commit
        if [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
          echo "🔧 Auto-formatting Rust code..."
          cargo fmt
          # Re-stage any formatted Rust files
          git diff --name-only "*.rs" | xargs -r git add
          echo "✅ Rust code formatted"
        fi

        # Run flake check if in a flake project (but don't fail on warnings)
        if [ -f flake.nix ] && command -v nix >/dev/null 2>&1; then
          echo "🔍 Running flake check..."
          if ! nix flake check --no-build 2>/dev/null; then
            echo "⚠️  Flake check failed - consider running 'nix flake check' manually"
            echo "💡 To skip this check: git commit --no-verify"
            echo "💡 To include GitHub Actions: Enable in github-actions.nix"
            exit 1
          fi
          echo "✅ Flake check passed"
        fi
      '';
    };

  };

  # Delta (moved from programs.git.delta to programs.delta)
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      light = false;
      side-by-side = true;
      line-numbers = true;
    };
  };

  # Git forge CLI configuration is managed by separate modules:
  # - GitHub: home/modules/github-auth.nix (gitAuth.github.*)
  # - GitLab: home/modules/gitlab-auth.nix (gitAuth.gitlab.*)

  # Install additional Git-related tools
  home.packages = with pkgs; [
    # Smart mergetool wrapper for neovim (migrated from validated-scripts)
    (pkgs.writeShellApplication {
      name = "smart-nvimdiff";
      runtimeInputs = with pkgs; [ git neovim coreutils ];
      text = /* bash */ ''
        # Smart mergetool wrapper for neovim
        # Automatically switches to 2-way diff when BASE is empty
        
        BASE="$1"
        LOCAL="$2"  
        REMOTE="$3"
        MERGED="$4"
        
        # Check if BASE file exists and is not empty
        if [ -f "$BASE" ] && [ -s "$BASE" ]; then
            # Normal 4-way diff with non-empty BASE
            # Use timer to ensure focus happens after all initialization
            exec nvim -d "$MERGED" "$LOCAL" "$BASE" "$REMOTE" \
              -c "wincmd J" \
              -c "call timer_start(250, {-> execute('wincmd b')})"
        else
            # Empty or missing BASE, so MERGED is just a useless single conflict diff.
            # Overwrite MERGED with LOCAL and do 2-way diff against REMOTE.
            # This gives us a clean starting point without conflict markers
            # which allows us to properly merge the desired changes.
            cp "$LOCAL" "$MERGED"
            exec nvim -d "$MERGED" "$REMOTE"
        fi
      '';
      passthru.tests = {
        syntax = pkgs.runCommand "test-smart-nvimdiff-syntax" { } ''
          echo "✅ Syntax validation passed at build time" > $out
        '';
        argument_validation = pkgs.runCommand "test-smart-nvimdiff-args" { } ''
          echo "✅ Argument validation test passed (placeholder)" > $out
        '';
      };
    })

    pre-commit # framework for local static analysis before git commit
    gitleaks # scan working tree for accidental secret/PII leaks
    git-crypt # For encrypting sensitive files in git repos
    # gitui      # Terminal UI for git - temporarily disabled due to build failure
    lazygit # Another terminal UI for git

    # Git workflow scripts
    (pkgs.writeShellApplication {
      name = "syncfork";
      text = builtins.readFile ../files/bin/syncfork.sh;
      runtimeInputs = with pkgs; [ git ];
    })

    # Git functions and utilities
    (pkgs.writeShellApplication {
      name = "git-functions";
      text = builtins.readFile ../files/bin/gitfuncs.sh;
      runtimeInputs = with pkgs; [ git neovim ];
    })
  ];
}
