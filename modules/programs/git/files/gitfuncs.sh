# Add this to your ~/.zshrc or ~/.bashrc
git_review() {
    local commits_back=${1:-1}

    # Handle help argument
    if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
        cat << 'EOF'
git_review - Review and selectively apply changes from previous commits

USAGE:
    git_review [COMMITS_BACK]
    git_review -h|--help|help

PURPOSE:
    Opens vimdiff for each file that changed between your current working
    directory and a previous commit, allowing you to selectively cherry-pick
    changes from the older version back into your current files.

ARGUMENTS:
    COMMITS_BACK    Number of commits to go back (default: 1)
                    Examples: 1, 3, 5

VIMDIFF COMMANDS:
    do              Get (obtain) change from other pane to current pane
    dp              Put change from current pane to other pane
    ]c              Jump to next difference
    [c              Jump to previous difference
    Ctrl+w w        Switch between panes
    :w              Save current file (make sure you're in the right pane)
    :qa             Quit all windows and move to next file

EXAMPLES:
    git_review           # Review changes from 1 commit back
    git_review 3         # Review changes from 3 commits back
    git_review 5         # Review changes from 5 commits back

WORKFLOW:
    1. Function shows each changed file in vimdiff
    2. Left pane: your current file (editable)
    3. Right pane: file from previous commit (read-only reference)
    4. Use 'do' to pull old changes into current file
    5. Save with ':w' when in left pane
    6. Quit with ':qa' to move to next file

NOTE:
    Make sure to commit your changes after reviewing all files.
EOF
        return 0
    fi

    local base_commit="HEAD~$commits_back"

    # Get list of changed files (portable method)
    local changed_files_list
    changed_files_list=$(git diff --name-only "$base_commit" HEAD)

    if [[ -z "$changed_files_list" ]]; then
        echo "No files changed."
        return 0
    fi

    # Count files
    local file_count
    file_count=$(echo "$changed_files_list" | wc -l)
    echo "Changed files: $file_count"

    # Loop through each file
    while IFS= read -r file; do
        if [[ -n "$file" ]] && git show "$base_commit:$file" &>/dev/null && [[ -f "$file" ]]; then
            echo "Processing: $file"
            nvim -d "$file" <(git show "$base_commit:$file")
        fi
    done <<< "$changed_files_list"
}
git_remote_workflow() {
  cat << EOF
Best Practices for Multi-Remote Git Workflows

1. Starting a Branch Workflow

# Ensure you're on the main development branch from your fork
git checkout master  # or main
git pull fork master  # sync with your fork's master

# Create and switch to new feature branch
git checkout -b feature-name

# OR create branch from specific upstream commit/branch
git checkout -b feature-name upstream/master

2. Setting Up Remote Tracking (Recommended)

# When pushing for the first time, set upstream to your fork
git push -u fork feature-name

# This creates tracking: feature-name -> fork/feature-name
# Future pushes can just use: git push

3. Development Workflow Commands

# Make changes, stage, commit
git add .
git commit -m "Descriptive commit message"

# Push to your fork (if tracking is set up)
git push

# OR explicitly specify remote and branch
git push fork feature-name

4. Best Practices for Multi-Remote Setup

Remote Naming Convention:
- origin or fork: Your personal fork (where you push)
- upstream: Original project repository (read-only for you)

Branch Workflow:
# Start work
git checkout master
git pull fork master                    # sync your fork
git pull upstream master               # get latest from original project
git push fork master                   # update your fork's master
git checkout -b feature-fix-something  # create feature branch

# Work and commit
git add -A
git commit -m "Fix something important"

# Push to your fork with tracking
git push -u fork feature-fix-something

# Continue development
git add .
git commit -m "Address review feedback"
git push  # uses tracking to push to fork/feature-fix-something

5. Safety Considerations

Never accidentally push to upstream:
# Check where you're about to push
git remote -v
git branch -vv  # shows tracking relationships

# Always be explicit on first push
git push -u fork feature-name

# If you accidentally set upstream tracking, fix it:
git branch --set-upstream-to=fork/feature-name

6. Example Workflow Summary for a nix home-manager configuration project/repo

For the home-manager repository specifically:

# Starting new work
cd ~/src/home-manager
git checkout master
git pull fork master
git checkout -b feature-new-fix

# Make changes, commit
git add .
git commit -m "Fix new issue"

# Push to fork with tracking
git push -u fork feature-new-fix

# Update flake.nix to point to new branch
# In ~/src/nixcfg/flake.nix:
# url = "git+file:///home/tim/src/home-manager?ref=feature-new-fix";

# Test the fix
nix flake lock --update-input home-manager
sudo nixos-rebuild switch --flake '.#thinky-nixos'

EOF
}
