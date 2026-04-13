Analyze all explicitly-pinned package versions in this nixcfg repository, check upstream for newer releases, research changelogs, and write a comprehensive update analysis report to `package-update-analysis.md` at the repo root (overwriting any existing file).

## Instructions

### Step 1: Inventory all version pins

Scan these locations for explicitly-pinned package versions:

1. **`overlays/default.nix`** -- `builtins.fetchTarball` pins (e.g., claude-code, opencode)
2. **`pkgs/*/default.nix`** -- `version = "..."`, `fetchFromGitHub` with `rev`/`tag`, `fetchPypi` with hash
3. **`modules/programs/shell/shell.nix`** -- zsh plugin `fetchFromGitHub` with `rev`
4. **`modules/programs/*/`** -- any other `fetchFromGitHub` or version pins
5. **`flake.lock`** -- check staleness of rolling inputs (sops-nix, home-manager, nixvim, disko, flake-parts, nixpkgs)

For each pin, record: package name, current version/rev, pin file and line number.

### Step 2: Check upstream versions (parallel subagents)

Launch parallel subagents to check latest upstream versions:

- **npm packages**: `npm view <pkg> version`
- **GitHub repos**: `gh release list -R <owner/repo> -L 3` or `gh api repos/<owner/repo>/releases/latest`
- **PyPI packages**: `curl -s https://pypi.org/pypi/<pkg>/json | jq -r '.info.version'`
- **Flake inputs**: Compare `flake.lock` dates against `gh api repos/<owner/repo>/commits/<branch> --jq '.commit.committer.date'`

Only report packages where an upgrade is available.

### Step 3: Research release notes (parallel subagents)

For each package with an available upgrade, launch a parallel subagent to research:

- Release notes / changelogs between current and latest version
- Breaking changes, deprecations, behavioral changes
- New features worth noting
- Config format changes that affect our Nix modules

Use `gh release view`, CHANGELOG.md files, commit history, and PyPI metadata as sources.

### Step 4: Write the report

Write `package-update-analysis.md` at the repo root with this structure:

```markdown
# Package Update Analysis

> Generated: YYYY-MM-DD HH:MM TZ
> Branch: `<current branch>`

## Summary

| Package | Current | Latest | Risk | Pin Location |
|---------|---------|--------|------|-------------|
| ... | ... | ... | Low/Medium/High | file:line |

**Already current:** list of packages at latest version

---

## <package>: <current> -> <latest>

### Breaking / Behavioral Changes
### Key New Features
### Notable Bug Fixes
### Risk Assessment

(repeat for each package)

---

## Recommended Upgrade Order
## Flake Inputs Worth Refreshing
```

**Risk levels**:
- **Low**: Bugfixes only, no behavioral changes, drop-in replacement
- **Medium**: New features with some behavioral changes, config-compatible but may need validation
- **High**: Breaking changes to config format, API, or core behavior requiring code changes

### Step 5: Report completion

After writing the file, report a concise summary to the user: how many packages checked, how many upgradeable, highest risk level found.
