# Release Process

nixcfg uses [Semantic Versioning](https://semver.org/) with automated release pipelines. The [`VERSION`](VERSION) file in the repository root is the single source of truth for the current version and the sole trigger for the release process.

## Why a VERSION File?

Nix flakes provide a well-defined set of source metadata during evaluation: commit hash (`self.rev`, `self.shortRev`), dirty state (`self.dirtyRev`), commit timestamp (`self.lastModified`), and ancestor count (`self.revCount`). Git tags, however, are not part of this metadata set. There is no `self.tag` or `self.gitDescribe` attribute, and flake evaluation enforces purity — shelling out to `git describe` is not permitted.

This is a deliberate design boundary in Nix's git fetcher, which extracts source content and a minimal set of commit-level metadata without resolving tag references. The sandboxed build environment similarly has no access to the `.git` directory or the network, so derivations cannot query tags either. This is well-documented in [NixOS/nix#7201](https://github.com/NixOS/nix/issues/7201) and has been discussed on [NixOS Discourse](https://discourse.nixos.org/t/git-describe-like-attributes-for-flakes/10805) since 2021.

The [`VERSION`](VERSION) file bridges this gap cleanly. It is a tracked file in the working tree, so it participates in flake evaluation like any other source file. [`modules/flake-parts/version.nix`](modules/flake-parts/version.nix) reads it at eval time and composes a full version string:

```nix
baseVersion = lib.trim (builtins.readFile "${self}/VERSION");
version =
  if self ? rev then "${baseVersion}+${self.shortRev}"
  else "${baseVersion}-dirty";
```

This produces versions like `0.1.0+a1b2c3d` for clean builds and `0.1.0-dirty` for uncommitted working trees — combining the human-meaningful release version with Nix's native commit identity. The [`VERSION`](VERSION) file is also validated at eval time by the [`lint-version`](modules/flake-parts/version.nix) check, which rejects non-semver content via `lib.seq` + `throw` (so `nix flake check --no-build` catches format errors immediately).

The CI pipeline then closes the loop: when [`VERSION`](VERSION) changes on `main`, [`auto-tag.yml`](.github/workflows/auto-tag.yml) creates the corresponding git tag, keeping the file and the tag in permanent agreement.

## How to Release

1. **Create a PR** that bumps the [`VERSION`](VERSION) file to the new version (e.g., `0.1.0` → `0.2.0`)
2. **Merge the PR** to `main`
3. The rest is automatic:
   - [`auto-tag.yml`](.github/workflows/auto-tag.yml) detects the [`VERSION`](VERSION) change and creates an annotated git tag
   - The tag push triggers [`release.yml`](.github/workflows/release.yml)
   - [`release.yml`](.github/workflows/release.yml) builds the WSL tarball, generates release notes from conventional commits, and publishes a GitHub Release with the artifact attached

No manual tag creation or release drafting is required.

## Version Format

Versions must be valid semver: `MAJOR.MINOR.PATCH` with an optional pre-release suffix.

```
0.1.0           # standard release
1.0.0-rc1       # pre-release
```

[`auto-tag.yml`](.github/workflows/auto-tag.yml) validates the format and rejects anything that doesn't match `N.N.N` or `N.N.N-suffix`.

## Release Assets

Each release builds and publishes the dev team WSL distribution image:

| Asset | Description |
|-------|-------------|
| `nixcfg-wsl-dev-team-{version}.wsl` | NixOS-WSL distribution image for dev team onboarding |
| `Import-NixOSWSL.ps1` | PowerShell script for importing the tarball and setting up Windows Terminal |

**Quick install:** See [docs/WSL-TEAM-QUICKSTART.md](docs/WSL-TEAM-QUICKSTART.md) for the full walkthrough.

**Manual install:** `wsl --import nixos-wsl-dev-team <location> nixcfg-wsl-dev-team-{version}.wsl`

## Pipeline Details

### [`auto-tag.yml`](.github/workflows/auto-tag.yml)

- **Trigger**: Push to `main` that changes [`VERSION`](VERSION)
- **Validates**: Semver format, tag doesn't already exist
- **Creates**: Annotated git tag matching [`VERSION`](VERSION) content
- **Auth**: Uses `RELEASE_PAT` secret (not `GITHUB_TOKEN`) because GitHub Actions events created by `GITHUB_TOKEN` don't trigger other workflows

### [`release.yml`](.github/workflows/release.yml)

- **Trigger**: Push of a version tag matching `[0-9]*` + manual `workflow_dispatch`
- **Validates**: Tag matches [`VERSION`](VERSION) file content at the tagged commit
- **Builds**: WSL tarball via `nixos-wsl-tarball-builder`
- **Concurrency**: Only one release runs at a time (`cancel-in-progress: false`)
- **Timeout**: 120 minutes for the tarball build, 10 minutes for the release job

### [`.github/release.yml`](.github/release.yml) (config)

Configures GitHub's auto-generated release notes categories. This is only used if a release is created manually through the GitHub UI — the automated pipeline generates its own notes from git history.

## Setup: `RELEASE_PAT` Secret

The auto-tag workflow requires a Personal Access Token because `GITHUB_TOKEN` events don't trigger downstream workflows.

1. Create a fine-grained PAT at https://github.com/settings/tokens with:
   - **Repository access**: This repository only
   - **Permissions**: Contents (read and write)
2. Add the PAT as a repository secret named `RELEASE_PAT` at:
   `Settings → Secrets and variables → Actions → New repository secret`
