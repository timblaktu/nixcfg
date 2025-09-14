#!/usr/bin/env bash
# Setup script for secret scanning and pre-commit hooks

set -euo pipefail

echo "Setting up secret scanning for nixcfg repository..."

# Check if we're in the right directory
if [ ! -f "flake.nix" ] || [ ! -d ".git" ]; then
    echo "ERROR: Must be run from nixcfg repository root"
    exit 1
fi

# Install pre-commit if not already installed
if ! command -v pre-commit &> /dev/null; then
    echo "Installing pre-commit..."
    nix-shell -p pre-commit --run "pre-commit --version"
fi

# Install pre-commit hooks
echo "Installing pre-commit hooks..."
nix-shell -p pre-commit --run "pre-commit install"

# Run initial scan
echo "Running initial security scan..."
nix-shell -p pre-commit --run "pre-commit run --all-files" || true

# Setup additional git config for safety
echo "Configuring git safety settings..."

# Prevent commits to main branch
git config --local branch.main.pushRemote no_push

# Add custom pre-push hook
cat > .git/hooks/pre-push << 'EOF'
#!/usr/bin/env bash
# Pre-push hook to prevent accidental secret pushes

# Check for common secret patterns in staged files
patterns=(
    'BEGIN.*PRIVATE KEY'
    'ghp_[a-zA-Z0-9]{36}'
    'github_pat_[a-zA-Z0-9]{22}_[a-zA-Z0-9]{59}'
    'sk-[a-zA-Z0-9]{48}'
    'npm_[a-zA-Z0-9]{36}'
)

for pattern in "${patterns[@]}"; do
    if git diff --cached | grep -E "$pattern" > /dev/null 2>&1; then
        echo "ERROR: Potential secret detected! Pattern: $pattern"
        echo "Please review your changes and remove any secrets."
        exit 1
    fi
done

# Verify SOPS files are encrypted
for file in $(git diff --cached --name-only | grep -E 'secrets/.*\.ya?ml$' | grep -v template); do
    if [ -f "$file" ] && ! grep -q '"sops":\|sops:' "$file" 2>/dev/null; then
        echo "ERROR: $file is not encrypted with SOPS!"
        echo "Use 'sops $file' to edit secrets files."
        exit 1
    fi
done

exit 0
EOF

chmod +x .git/hooks/pre-push

echo "✅ Secret scanning setup complete!"
echo ""
echo "Security measures now in place:"
echo "  • Gitleaks pre-commit hook installed"
echo "  • Custom pre-push hook for additional validation"
echo "  • Git safety settings configured"
echo ""
echo "To manually scan for secrets:"
echo "  nix-shell -p pre-commit --run 'pre-commit run --all-files'"
echo ""
echo "To bypass hooks in emergency (NOT RECOMMENDED):"
echo "  git commit --no-verify"
echo "  git push --no-verify"