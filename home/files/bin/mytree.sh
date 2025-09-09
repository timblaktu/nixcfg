#!/usr/bin/env bash
# This script accepts a list of file paths, groups them by immediate parent directory,
# and runs the 'tree' command for each group, using a pattern to show only the specified files.
#
# Usage: ./mytree.sh FILE1 [FILE2 ...]
# Usage (if sourced): mytree FILE1 [FILE2 ...]

mytree() {
    if [ $# -eq 0 ]; then
        echo "Usage: mytree FILE1 [FILE2 ...]"
        return 1
    fi

    # Group files by their immediate parent directory
    declare -A groups
    for path in "$@"; do
        parent=$(dirname "$path")
        filename=$(basename "$path")
        groups[$parent]+="$filename|"
    done

    # For each group, run tree with a pattern to show only the files in the group
    for parent in "${!groups[@]}"; do
        # Remove trailing '|' and build the pattern
        pattern=${groups[$parent]%|}
        # Count the depth needed: number of '/' in the relative path from the group's parent to the file
        # Since we're grouping by parent, depth is always 1 (files are directly under parent)
        # But if you want to include subdirs, this would need to be adjusted
        # Here, we use -L 1 to show only the files directly under the parent
        tree "$parent" --noreport --prune -P "$pattern" -L 1
        echo
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    mytree "$@"
fi

export -f mytree

