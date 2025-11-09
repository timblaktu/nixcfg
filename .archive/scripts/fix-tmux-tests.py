#!/usr/bin/env python3
"""
Script to fix all tmux-session-picker tests by adding library dependencies
"""

import re

# Read the file
with open('/home/tim/src/nixcfg/flake-modules/tests.nix', 'r') as f:
    content = f.read()

# Define the library setup code
library_setup = '''            
            # Set up library dependencies in test environment
            export HOME="$PWD/test-home"
            mkdir -p $HOME/.local/lib
            cp ${../home/files/lib/terminal-utils.bash} $HOME/.local/lib/terminal-utils.bash
            cp ${../home/files/lib/color-utils.bash} $HOME/.local/lib/color-utils.bash
            cp ${../home/files/lib/path-utils.bash} $HOME/.local/lib/path-utils.bash
'''

# Pattern to match test sections that need fixing
pattern = r'(\s+} \'\')\n(\s+echo "Testing tmux-session-picker[^"]*"\.\.\.)\n(\s+\n\s+#[^\n]*\n\s+#[^\n]*\n\s+echo "[^"]*"\.\.\.)'

def replacement(match):
    start = match.group(1)
    echo_line = match.group(2) 
    rest = match.group(3)
    
    # Only add library setup if it's not already there
    if 'Set up library dependencies' not in echo_line:
        return start + '\n' + echo_line + library_setup + rest
    else:
        return match.group(0)  # Return unchanged if already fixed

# Apply the fix
content = re.sub(pattern, replacement, content)

# For tests that have different patterns, use a more flexible approach
patterns_to_fix = [
    r'(\s+echo "Testing tmux-session-picker[^"]*"\.\.\.)\n(\s+\n\s+# Test [0-9]+\.[0-9]+:)',
    r'(\s+echo "Testing tmux-session-picker[^"]*"\.\.\.)\n(\s+\n\s+# Create)',
    r'(\s+echo "Testing tmux-session-picker[^"]*"\.\.\.)\n(\s+\n\s+echo "[^"]*")',
    r'(\s+echo "Testing tmux-session-picker[^"]*"\.\.\.)\n(\s+\n\s+if \[)',
]

for pattern in patterns_to_fix:
    def replacement_flexible(match):
        echo_line = match.group(1)
        rest = match.group(2)
        
        # Only add library setup if it's not already there
        if 'Set up library dependencies' not in echo_line and 'export HOME="$PWD/test-home"' not in echo_line:
            return echo_line + library_setup + rest
        else:
            return match.group(0)  # Return unchanged if already fixed
    
    content = re.sub(pattern, replacement_flexible, content)

# Write the fixed content
with open('/home/tim/src/nixcfg/flake-modules/tests.nix', 'w') as f:
    f.write(content)

print("Applied library dependency fixes to all tmux tests")