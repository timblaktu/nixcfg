{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.claude-code;

in
{
  options.programs.claude-code.gitCommands = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable git worktree management commands";
    };
  };

  config = mkIf (cfg.enable && cfg.gitCommands.enable) {
    # Deploy git worktree commands to each account's commands directory
    home.file = lib.mkMerge (lib.flatten (mapAttrsToList
      (name: account:
        if account.enable then [{
          # /worktree-create
          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/git/worktree-create.md" = {
            text = ''
              # Create Git Worktree with Standard Naming

              You are a git worktree creation assistant. Create a new worktree following these steps.

              ## Arguments
              - `$ARG1` (required): Suffix for worktree/branch name (e.g., "pro", "spike", "session-20260126")
              - `$ARG2` (optional): Base branch name (defaults to current branch)

              ## Validation Steps

              1. **Verify Git Repository**
                 ```bash
                 git rev-parse --git-dir >/dev/null 2>&1 || { echo "❌ Error: Not in a git repository"; exit 1; }
                 ```

              2. **Check Arguments**
                 ```bash
                 if [[ -z "$ARG1" ]]; then
                   echo "❌ Error: Suffix is required"
                   echo "Usage: /worktree-create <suffix> [base-branch]"
                   exit 1
                 fi
                 ```

              3. **Validate Suffix Characters**
                 - Must be alphanumeric with hyphens/underscores only
                 - No spaces, slashes, or special characters
                 - If invalid, show error: "Suffix contains invalid characters. Use only: a-z A-Z 0-9 - _"

              4. **Check for Uncommitted Changes**
                 ```bash
                 if [[ -n "$(git status --porcelain)" ]]; then
                   echo "⚠️  Warning: You have uncommitted changes in the current worktree"
                   echo "This won't affect worktree creation, but consider committing first"
                 fi
                 ```

              ## Execution Steps

              1. **Determine Base Information**
                 ```bash
                 # Current directory becomes parent worktree directory
                 REPO_DIR=$(basename "$(git rev-parse --show-toplevel)")
                 PARENT_DIR=$(dirname "$(git rev-parse --show-toplevel)")

                 # Base branch: use $ARG2 if provided, otherwise current branch
                 if [[ -n "$ARG2" ]]; then
                   BASE_BRANCH="$ARG2"
                 else
                   BASE_BRANCH=$(git branch --show-current)
                 fi

                 # New branch name: base-branch-suffix
                 NEW_BRANCH="''${BASE_BRANCH}-''${ARG1}"

                 # New worktree path: parent-dir/repo-name-suffix
                 NEW_WORKTREE="''${PARENT_DIR}/''${REPO_DIR}-''${ARG1}"
                 ```

              2. **Check if Worktree Already Exists**
                 ```bash
                 if [[ -d "$NEW_WORKTREE" ]]; then
                   echo "❌ Error: Worktree directory already exists: $NEW_WORKTREE"
                   exit 1
                 fi

                 # Check if branch already exists
                 if git show-ref --verify --quiet "refs/heads/$NEW_BRANCH"; then
                   echo "❌ Error: Branch already exists: $NEW_BRANCH"
                   echo "Use a different suffix or delete the existing branch first"
                   exit 1
                 fi
                 ```

              3. **Create Worktree**
                 ```bash
                 git worktree add -b "$NEW_BRANCH" "$NEW_WORKTREE"
                 ```

              4. **Verify Creation**
                 ```bash
                 if [[ ! -d "$NEW_WORKTREE" ]]; then
                   echo "❌ Error: Worktree creation failed"
                   exit 1
                 fi
                 ```

              ## Output Format

              On success, display:

              ```
              ✅ Worktree Created Successfully

              **Location**: <full-path-to-new-worktree>
              **Branch**: <new-branch-name>
              **Based On**: <base-branch> at commit <short-sha>

              ## Next Steps
              1. cd <path>
              2. Start working on your isolated changes
              3. Use /worktree-status to check sync status
              4. Use /worktree-integrate when ready to merge back

              ## Integration Reminder
              Remember to sync periodically with /worktree-sync to avoid divergence.
              ```

              ## Error Scenarios

              - **Not a git repo**: "❌ Error: Not in a git repository"
              - **Missing suffix**: "❌ Error: Suffix is required. Usage: /worktree-create <suffix> [base-branch]"
              - **Invalid suffix**: "❌ Error: Suffix contains invalid characters. Use only: a-z A-Z 0-9 - _"
              - **Worktree exists**: "❌ Error: Worktree directory already exists: <path>"
              - **Branch exists**: "❌ Error: Branch already exists: <branch-name>"
            '';
          };

          # /worktree-status
          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/git/worktree-status.md" = {
            text = ''
              # Show Git Worktree Status

              You are a git worktree status reporter. Display comprehensive status for all worktrees.

              ## Arguments
              None - this command shows status for all worktrees in the repository.

              ## Validation Steps

              1. **Verify Git Repository**
                 ```bash
                 git rev-parse --git-dir >/dev/null 2>&1 || { echo "❌ Error: Not in a git repository"; exit 1; }
                 ```

              ## Execution Steps

              1. **Get All Worktrees**
                 ```bash
                 git worktree list --porcelain
                 ```

              2. **For Each Worktree, Collect:**
                 - Worktree path
                 - Branch name
                 - Current HEAD commit (short SHA + message)
                 - Whether it's the main/current worktree
                 - Uncommitted changes status
                 - Sync status (ahead/behind parent branch if applicable)

              3. **Determine Sync Status**
                 For branches with naming pattern `parent-branch-suffix`:
                 ```bash
                 # Extract parent branch name
                 PARENT_BRANCH="''${BRANCH%-*}"

                 # Check if parent branch exists
                 if git show-ref --verify --quiet "refs/heads/$PARENT_BRANCH"; then
                   # Compare commits
                   AHEAD=$(git rev-list --count "$PARENT_BRANCH..$BRANCH")
                   BEHIND=$(git rev-list --count "$BRANCH..$PARENT_BRANCH")
                 fi
                 ```

              ## Output Format

              ```
              📋 Git Worktrees Status

              Found <N> worktree(s):

              ┌─────────────────────────────────────────────────────────
              │ 🔹 Worktree #1 [CURRENT]
              ├─────────────────────────────────────────────────────────
              │ Path:       /home/user/projects/repo
              │ Branch:     main
              │ Commit:     abc1234 "Latest commit message"
              │ Changes:    Clean working tree
              └─────────────────────────────────────────────────────────

              ┌─────────────────────────────────────────────────────────
              │ 🔸 Worktree #2
              ├─────────────────────────────────────────────────────────
              │ Path:       /home/user/projects/repo-pro
              │ Branch:     main-pro
              │ Commit:     def5678 "Work in progress"
              │ Changes:    Modified: 3 files, Staged: 1 file
              │ Sync:       ↑ 5 ahead, ↓ 2 behind main
              └─────────────────────────────────────────────────────────

              ┌─────────────────────────────────────────────────────────
              │ 🔸 Worktree #3
              ├─────────────────────────────────────────────────────────
              │ Path:       /home/user/projects/repo-spike
              │ Branch:     feature/unified-platform-spike
              │ Commit:     ghi9012 "Experimental changes"
              │ Changes:    Modified: 12 files
              │ Sync:       (no parent branch detected)
              └─────────────────────────────────────────────────────────

              💡 Tips:
              - Use /worktree-sync to update a worktree from its parent branch
              - Use /worktree-integrate to merge changes back to parent
              - Changes in one worktree don't affect others
              ```

              ## Status Indicators

              - **[CURRENT]**: The worktree you're currently in
              - **Clean working tree**: No uncommitted changes
              - **Modified: N files**: Files with uncommitted changes
              - **Staged: N files**: Changes added to index
              - **↑ N ahead**: Commits in this branch not in parent
              - **↓ N behind**: Commits in parent not in this branch
              - **In sync**: Branch is up-to-date with parent

              ## Error Scenarios

              - **Not a git repo**: "❌ Error: Not in a git repository"
              - **No worktrees**: "📭 No additional worktrees found (only main worktree exists)"
            '';
          };

          # /worktree-sync
          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/git/worktree-sync.md" = {
            text = ''
              # Sync Worktree with Parent Branch

              You are a git worktree synchronization assistant. Guide the user through safely syncing their worktree with the parent branch.

              ## Arguments
              - `$ARG1` (optional): Worktree path (defaults to current directory)
              - `$ARG2` (optional): Strategy - "merge" or "rebase" (asks user if not specified)

              ## Validation Steps

              1. **Verify Git Repository**
                 ```bash
                 git rev-parse --git-dir >/dev/null 2>&1 || { echo "❌ Error: Not in a git repository"; exit 1; }
                 ```

              2. **Determine Target Worktree**
                 ```bash
                 if [[ -n "$ARG1" ]]; then
                   cd "$ARG1" || { echo "❌ Error: Invalid worktree path"; exit 1; }
                 fi

                 # Verify we're in a worktree
                 CURRENT_BRANCH=$(git branch --show-current)
                 if [[ -z "$CURRENT_BRANCH" ]]; then
                   echo "❌ Error: Not on a branch"
                   exit 1
                 fi
                 ```

              3. **Check Working Tree is Clean**
                 ```bash
                 if [[ -n "$(git status --porcelain)" ]]; then
                   echo "❌ Error: Working tree has uncommitted changes"
                   echo "Please commit or stash your changes first:"
                   git status --short
                   exit 1
                 fi
                 ```

              4. **Detect Parent Branch**
                 ```bash
                 # Try to detect parent from branch name pattern: parent-suffix
                 if [[ "$CURRENT_BRANCH" =~ ^(.+)-([^-]+)$ ]]; then
                   PARENT_BRANCH="''${BASH_REMATCH[1]}"
                 else
                   echo "ℹ️  Cannot auto-detect parent branch from name: $CURRENT_BRANCH"
                   echo "Please specify the parent branch to sync with:"
                   # Ask user or exit
                   exit 1
                 fi

                 # Verify parent branch exists
                 if ! git show-ref --verify --quiet "refs/heads/$PARENT_BRANCH"; then
                   echo "❌ Error: Parent branch not found: $PARENT_BRANCH"
                   exit 1
                 fi
                 ```

              ## Execution Steps

              1. **Fetch Latest Changes**
                 ```bash
                 echo "🔄 Fetching latest changes..."
                 git fetch origin "$PARENT_BRANCH"
                 ```

              2. **Show Sync Status**
                 ```bash
                 AHEAD=$(git rev-list --count "$PARENT_BRANCH..$CURRENT_BRANCH")
                 BEHIND=$(git rev-list --count "$CURRENT_BRANCH..$PARENT_BRANCH")

                 echo "📊 Sync Status:"
                 echo "  Current branch: $CURRENT_BRANCH"
                 echo "  Parent branch:  $PARENT_BRANCH"
                 echo "  Commits ahead:  $AHEAD"
                 echo "  Commits behind: $BEHIND"

                 if [[ "$BEHIND" -eq 0 ]]; then
                   echo "✅ Already up-to-date with $PARENT_BRANCH"
                   exit 0
                 fi
                 ```

              3. **Choose Strategy**
                 If $ARG2 not provided, ask user:
                 ```
                 How would you like to sync with $PARENT_BRANCH?

                 1. **merge** - Create a merge commit (preserves history)
                    - Keeps complete history with merge commit
                    - Better for collaborative branches
                    - Shows when sync happened

                 2. **rebase** - Replay your commits on top of parent (cleaner history)
                    - Linear history
                    - Cleaner git log
                    - May require resolving conflicts

                 Which strategy? (merge/rebase):
                 ```

              4. **Execute Sync**
                 ```bash
                 if [[ "$STRATEGY" == "merge" ]]; then
                   echo "🔀 Merging $PARENT_BRANCH into $CURRENT_BRANCH..."
                   git merge "$PARENT_BRANCH"
                 elif [[ "$STRATEGY" == "rebase" ]]; then
                   echo "🔀 Rebasing $CURRENT_BRANCH onto $PARENT_BRANCH..."
                   git rebase "$PARENT_BRANCH"
                 fi
                 ```

              5. **Check for Conflicts**
                 ```bash
                 if git ls-files -u | grep -q .; then
                   echo "⚠️  CONFLICTS DETECTED"
                   echo ""
                   echo "The following files have conflicts:"
                   git diff --name-only --diff-filter=U
                   echo ""
                   echo "Please resolve conflicts manually:"
                   echo "1. Edit conflicted files"
                   echo "2. Stage resolved files: git add <file>"
                   echo "3. Complete the $STRATEGY: git $STRATEGY --continue"
                   echo ""
                   echo "Or abort: git $STRATEGY --abort"
                   exit 1
                 fi
                 ```

              ## Output Format

              **Success:**
              ```
              ✅ Sync Complete

              Updated $CURRENT_BRANCH with changes from $PARENT_BRANCH
              Strategy: $STRATEGY
              New commits applied: $BEHIND

              Your branch is now up-to-date with the parent branch.
              ```

              **With Conflicts:**
              ```
              ⚠️  CONFLICTS DETECTED

              The following files have conflicts:
              - path/to/file1.txt
              - path/to/file2.js

              Please resolve conflicts manually:
              1. Edit conflicted files
              2. Stage resolved files: git add <file>
              3. Complete the merge: git merge --continue

              Or abort: git merge --abort
              ```

              ## Error Scenarios

              - **Not a git repo**: "❌ Error: Not in a git repository"
              - **Uncommitted changes**: "❌ Error: Working tree has uncommitted changes. Commit or stash first."
              - **Parent branch not found**: "❌ Error: Parent branch not found: <branch-name>"
              - **Already up-to-date**: "✅ Already up-to-date with <parent-branch>"

              ## Important Notes

              - **NEVER** use `--force` or `--force-with-lease`
              - **NEVER** automatically resolve conflicts - always ask user
              - **ALWAYS** verify working tree is clean before syncing
              - **ALWAYS** show conflict details if they occur
            '';
          };

          # /worktree-integrate
          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/git/worktree-integrate.md" = {
            text = ''
              # Integrate Worktree Changes to Parent

              You are a git worktree integration assistant. Guide the user through merging or rebasing their worktree changes back to the parent branch.

              ## Arguments
              - `$ARG1` (optional): Strategy - "merge", "rebase", or "cherry-pick" (asks if not specified)
              - `$ARG2` (optional): Specific commits for cherry-pick (comma-separated SHAs)

              ## Validation Steps

              1. **Verify Git Repository**
                 ```bash
                 git rev-parse --git-dir >/dev/null 2>&1 || { echo "❌ Error: Not in a git repository"; exit 1; }
                 ```

              2. **Check Current Branch**
                 ```bash
                 CURRENT_BRANCH=$(git branch --show-current)
                 if [[ -z "$CURRENT_BRANCH" ]]; then
                   echo "❌ Error: Not on a branch"
                   exit 1
                 fi
                 ```

              3. **Detect Parent Branch**
                 ```bash
                 # Try to detect parent from branch name pattern: parent-suffix
                 if [[ "$CURRENT_BRANCH" =~ ^(.+)-([^-]+)$ ]]; then
                   PARENT_BRANCH="''${BASH_REMATCH[1]}"
                 else
                   echo "ℹ️  Cannot auto-detect parent branch from: $CURRENT_BRANCH"
                   echo "Please specify the target branch for integration:"
                   # Ask user or exit
                   exit 1
                 fi

                 # Verify parent branch exists
                 if ! git show-ref --verify --quiet "refs/heads/$PARENT_BRANCH"; then
                   echo "❌ Error: Parent branch not found: $PARENT_BRANCH"
                   exit 1
                 fi
                 ```

              4. **Check for Uncommitted Changes**
                 ```bash
                 if [[ -n "$(git status --porcelain)" ]]; then
                   echo "❌ Error: Current worktree has uncommitted changes"
                   echo "Please commit or stash changes first"
                   exit 1
                 fi
                 ```

              5. **Verify There Are Commits to Integrate**
                 ```bash
                 AHEAD=$(git rev-list --count "$PARENT_BRANCH..$CURRENT_BRANCH")
                 if [[ "$AHEAD" -eq 0 ]]; then
                   echo "ℹ️  No commits to integrate - branch is already merged or has no unique commits"
                   exit 0
                 fi
                 ```

              ## Pre-Integration Summary

              1. **Show Diff Summary**
                 ```bash
                 echo "📊 Integration Summary"
                 echo "════════════════════════════════════════"
                 echo "Source:      $CURRENT_BRANCH"
                 echo "Target:      $PARENT_BRANCH"
                 echo "Commits:     $AHEAD commits to integrate"
                 echo ""
                 echo "Commit Log:"
                 git log --oneline "$PARENT_BRANCH..$CURRENT_BRANCH"
                 echo ""
                 echo "Files Changed:"
                 git diff --stat "$PARENT_BRANCH..$CURRENT_BRANCH"
                 ```

              2. **Choose Integration Strategy**
                 If $ARG1 not provided, present options:
                 ```
                 How would you like to integrate changes?

                 1. **merge** - Merge branch into parent (recommended for collaborative work)
                    ✓ Preserves complete history
                    ✓ Shows when integration happened
                    ✓ Safe for published branches
                    - Creates merge commit

                 2. **rebase** - Rebase branch onto parent, then fast-forward merge
                    ✓ Clean linear history
                    ✓ No merge commits
                    - Rewrites history (only for unpublished branches)
                    - May require conflict resolution

                 3. **cherry-pick** - Select specific commits to apply
                    ✓ Selective integration
                    ✓ Good for partial work
                    - Requires commit selection

                 Which strategy? (merge/rebase/cherry-pick):
                 ```

              ## Execution Steps

              ### Strategy: Merge
              ```bash
              echo "🔀 Integrating via merge..."

              # Switch to parent branch
              git checkout "$PARENT_BRANCH"

              # Update parent branch
              git pull --ff-only || {
                echo "⚠️  Cannot fast-forward $PARENT_BRANCH"
                echo "Please update parent branch manually first"
                git checkout "$CURRENT_BRANCH"  # Switch back
                exit 1
              }

              # Merge worktree branch
              git merge --no-ff "$CURRENT_BRANCH" -m "Integrate changes from $CURRENT_BRANCH"

              # Check for conflicts (handled below)
              ```

              ### Strategy: Rebase
              ```bash
              echo "🔀 Integrating via rebase..."

              # First, update parent branch
              git checkout "$PARENT_BRANCH"
              git pull --ff-only || {
                echo "⚠️  Cannot fast-forward $PARENT_BRANCH"
                exit 1
              }

              # Switch back and rebase
              git checkout "$CURRENT_BRANCH"
              git rebase "$PARENT_BRANCH"

              # If successful, switch to parent and fast-forward merge
              git checkout "$PARENT_BRANCH"
              git merge --ff-only "$CURRENT_BRANCH"
              ```

              ### Strategy: Cherry-Pick
              ```bash
              echo "🔀 Integrating via cherry-pick..."

              # If commits specified in $ARG2
              if [[ -n "$ARG2" ]]; then
                COMMITS="''${ARG2//,/ }"
              else
                # Show commits and ask user to select
                echo "Available commits:"
                git log --oneline "$PARENT_BRANCH..$CURRENT_BRANCH"
                echo ""
                echo "Enter commit SHAs to cherry-pick (space-separated):"
                # Get user input
              fi

              # Switch to parent branch
              git checkout "$PARENT_BRANCH"
              git pull --ff-only

              # Cherry-pick selected commits
              for commit in $COMMITS; do
                git cherry-pick "$commit" || {
                  echo "⚠️  Cherry-pick failed for $commit"
                  echo "Resolve conflicts or abort: git cherry-pick --abort"
                  exit 1
                }
              done
              ```

              ## Conflict Handling

              ```bash
              if git ls-files -u | grep -q .; then
                echo "⚠️  CONFLICTS DETECTED"
                echo ""
                echo "Conflicted files:"
                git diff --name-only --diff-filter=U
                echo ""
                echo "Resolution steps:"
                echo "1. Edit conflicted files to resolve conflicts"
                echo "2. Stage resolved files: git add <file>"
                echo "3. Continue: git $OPERATION --continue"
                echo ""
                echo "Or abort: git $OPERATION --abort"
                echo "         git checkout $CURRENT_BRANCH  # Return to worktree"
                exit 1
              fi
              ```

              ## Post-Integration

              1. **Success Message**
                 ```
                 ✅ Integration Complete

                 Successfully integrated $AHEAD commit(s) from $CURRENT_BRANCH into $PARENT_BRANCH
                 Strategy: $STRATEGY

                 ## Next Steps

                 1. **Test the integration**: Verify everything works in $PARENT_BRANCH
                 2. **Push changes**: git push origin $PARENT_BRANCH
                 3. **Tag integration point** (optional):
                    git tag -a integration-$(date +%Y%m%d) -m "Integrated $CURRENT_BRANCH"
                 4. **Cleanup worktree** (optional, after verifying):
                    git worktree remove <worktree-path>
                    git branch -d $CURRENT_BRANCH
                 ```

              2. **Optional: Create Integration Tag**
                 Ask user: "Would you like to create a tag for this integration point?"
                 ```bash
                 git tag -a "integration-$(date +%Y%m%d-%H%M)" -m "Integrated $CURRENT_BRANCH"
                 ```

              ## Error Scenarios

              - **Not a git repo**: "❌ Error: Not in a git repository"
              - **No parent branch**: "❌ Error: Cannot detect parent branch"
              - **Uncommitted changes**: "❌ Error: Uncommitted changes detected. Commit first."
              - **No commits to integrate**: "ℹ️  No commits to integrate"
              - **Conflicts**: Show conflicted files and resolution instructions
              - **Cannot fast-forward parent**: "⚠️  Parent branch needs manual update"

              ## Important Safety Rules

              - **NEVER** use `--force` or `--force-with-lease`
              - **NEVER** automatically resolve conflicts
              - **ALWAYS** verify working tree is clean
              - **ALWAYS** pull parent branch before integration
              - **ALWAYS** show clear conflict resolution instructions
              - **NEVER** delete worktree/branch automatically after integration
            '';
          };
        }] else [ ]
      )
      cfg.accounts));
  };
}
