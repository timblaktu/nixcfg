# Git configuration
{ config, lib, pkgs, ... }:

{
  programs.git = {
    enable = true;
    lfs.enable = true;
    userName = "Tim Black";
    userEmail = "timblaktu@gmail.com";

    extraConfig = {
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
      # # Add mergetool configuration with cmd workaround for 4-way layout
      # mergetool = {
      #   nvimdiff = {
      #     # Using cmd instead of layout parameter due to Git 2.49.0 bug
      #     cmd = ''nvim -d "$LOCAL" "$BASE" "$REMOTE" "$MERGED" -c "wincmd J"'';
      #   };
      mergetool = {
        prompt = false;
        keepBackup = false;
        "smart-nvimdiff" = {
          cmd = ''smart-nvimdiff "$BASE" "$LOCAL" "$REMOTE" "$MERGED"'';
          trustExitCode = true;
        };
        # Cannot get this to show 4-way layout
        #vimdiff = {
        #  layout = "LOCAL,BASE,REMOTE / MERGED";
        #  # layout = "LOCAL,BASE,REMOTE / MERGED + BASE,LOCAL + BASE,REMOTE + (LOCAL/BASE/REMOTE),MERGED";
        #};
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
        helper = "cache --timeout=3600"; # Cache credentials for 1 hour to avoid frequent prompts
        "https://glab.espressif.cn/customer/esp-idf-for-summit" = {
          helper = "store";
        };
      };
      safe = {
        directory = [

        ];
      };
      status = {
        submodulesummary = 1;
      };
    };

    aliases = {
      st = "status";
      ci = "commit";
      co = "checkout";
      br = "branch";
      lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
      unstage = "reset HEAD --";
      last = "log -1 HEAD";
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

    delta = {
      enable = true;
      options = {
        navigate = true;
        light = false;
        side-by-side = true;
        line-numbers = true;
      };
    };
  };

  # GitHub CLI (settings from existing ~/.config/gh/config.yml)
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https"; # From existing config (not ssh)
      editor = ""; # Blank in existing config - will refer to environment
      prompt = "enabled";
      prefer_editor_prompt = "disabled"; # From existing config
      pager = ""; # Blank - will refer to environment
      # Custom aliases from existing config
      aliases = {
        co = "pr checkout";
      };
    };
  };

  # Install additional Git-related tools
  home.packages = with pkgs; [
    # smart-nvimdiff is now provided by validated-scripts module
    pre-commit # framework for local static analysis before git commit
    gitleaks # scan working tree for accidental secret/PII leaks
    git-crypt # For encrypting sensitive files in git repos
    # gitui      # Terminal UI for git - temporarily disabled due to build failure
    lazygit # Another terminal UI for git
  ];
}
