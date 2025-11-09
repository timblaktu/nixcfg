#!/bin/bash

# List of test names that still need fixing
tests=(
    "tmux-picker-session-file-validation" 
    "tmux-picker-integration-ifs-robustness"
    "tmux-picker-session-discovery"
    "tmux-picker-preview-generation"
)

# For each test, add the library setup function and calls where needed
for test in "${tests[@]}"; do
    echo "Fixing test: $test"
    
    # Find the test and add setup function after the echo line
    sed -i "/echo \"Testing tmux-session-picker.*$test.*/a\\
                      \\
                      # Set up library dependencies function for multiple HOME directories\\
                      setup_libraries() {\\
                        mkdir -p \"\$1/.local/lib\"\\
                        cp \${../home/files/lib/terminal-utils.bash} \"\$1/.local/lib/terminal-utils.bash\"\\
                        cp \${../home/files/lib/color-utils.bash} \"\$1/.local/lib/color-utils.bash\"\\
                        cp \${../home/files/lib/path-utils.bash} \"\$1/.local/lib/path-utils.bash\"\\
                      }" /home/tim/src/nixcfg/flake-modules/tests.nix
    
    echo "Added setup function for $test"
done

# Also add setup_libraries calls after HOME directory creation
# This pattern catches: export HOME=... followed by mkdir -p $HOME
sed -i '/export HOME="[^"]*"/,/mkdir -p "$HOME/a\
                      setup_libraries "$HOME"' /home/tim/src/nixcfg/flake-modules/tests.nix

echo "Applied library setup calls to all HOME directory creations"
echo "Fix complete!"