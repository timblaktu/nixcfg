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
    local changed_files_list=$(git diff --name-only "$base_commit" HEAD)
    
    if [[ -z "$changed_files_list" ]]; then
        echo "No files changed."
        return 0
    fi
    
    # Count files
    local file_count=$(echo "$changed_files_list" | wc -l)
    echo "Changed files: $file_count"
    
    # Loop through each file
    while IFS= read -r file; do
        if [[ -n "$file" ]] && git show "$base_commit:$file" &>/dev/null && [[ -f "$file" ]]; then
            echo "Processing: $file"
            nvim -d "$file" <(git show "$base_commit:$file")
        fi
    done <<< "$changed_files_list"
}
