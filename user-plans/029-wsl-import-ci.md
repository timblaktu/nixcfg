# Plan 029: WSL Import CI on GitHub Actions Windows Runners

## Status: PLANNING

## Context

`Test-WslImport.ps1` (commit `61ff8a4`) validates the full WSL tarball import
pipeline locally. This plan documents the path to running it (or a subset) in
CI using GitHub-hosted `windows-2025` runners.

## Research Findings (2026-03-19)

### GitHub-hosted `windows-2025` WSL support

- **WSL2 works**: Dadsv5 Azure instances (since Jan 2024) provide nested
  virtualization. WSL2 lightweight VM boots successfully.
- **No distro pre-installed**: Must `wsl --install` or use `Vampire/setup-wsl@v6`
  (~40s overhead).
- **Session 0**: Runners execute non-interactively. `wsl --import` behavior in
  this context is not well-tested upstream. May work, may not.
- **No Windows Terminal**: Server runners don't have Terminal installed, so
  fragment GUID validation must be skipped (`-SkipTerminalValidation`).
- **Runner specs**: 4 vCPU, 16 GB RAM. Adequate for import + validation, but
  building a NixOS tarball from scratch would be slow.

### Recommended CI approach

**Hybrid strategy**: Linux runner builds tarball (existing `build-tarball` job),
Windows runner imports and validates it.

```
Linux runner (ubuntu-latest)          Windows runner (windows-2025)
  ├── nix build tarballBuilder          ├── Download tarball artifact
  ├── sudo ./result/bin/...            ├── Install WSL2 + base distro
  ├── Upload artifact ─────────────────├── wsl --import test tarball
  └── (existing job)                    ├── Run validation checks
                                        └── wsl --unregister cleanup
```

### Key marketplace action

**[Vampire/setup-wsl@v6](https://github.com/Vampire/setup-wsl)** (~124 stars):
- Installs distro into WSL (Ubuntu default)
- Provides `wsl-bash` shell wrapper
- Handles WSLv1/v2 differences automatically

### Risk factors

| Risk | Mitigation |
|------|------------|
| `wsl --import` fails in Session 0 | Gate behind `continue-on-error`, mark experimental |
| systemd doesn't converge in CI | Use `--wait` with timeout, accept `degraded` |
| Tarball too large for artifact transfer | Already handled (~1.8 GiB, within 10 GiB limit) |
| WSL install flaky on runners | Retry logic in setup action |
| Runner image changes break WSL | Pin to `windows-2025`, not `windows-latest` |

### What would NOT work in CI

- Terminal fragment GUID validation (no Terminal on server)
- USB/IP or hardware tests (no hardware)
- Full `Test-WslImport.ps1 -All` matrix (too slow, one config is enough)

## Implementation Tasks

| ID | Task | Status |
|----|------|--------|
| T0 | Validate Test-WslImport.ps1 locally on real Windows machine | `TASK:PENDING` |
| T1 | Add `validate-import` job to `ci.yml` (windows-2025 runner) | `TASK:PENDING` |
| T2 | Test CI job on a PR (experimental, continue-on-error) | `TASK:PENDING` |
| T3 | Promote to required check if stable | `TASK:PENDING` |

### T1 Spec: `validate-import` job

```yaml
validate-import:
  name: Validate WSL import
  needs: build-tarball  # from ci.yml, reuse tarball artifact
  runs-on: windows-2025
  timeout-minutes: 30
  continue-on-error: true  # experimental until proven stable
  steps:
    - uses: actions/checkout@v4

    - uses: Vampire/setup-wsl@v6
      with:
        distribution: Ubuntu-24.04
        additional-packages: curl xz-utils

    - name: Install Nix in WSL
      shell: wsl-bash {0}
      run: |
        curl -L https://nixos.org/nix/install | sh -s -- --daemon
        echo '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' >> ~/.bashrc

    - uses: actions/download-artifact@v4
      with:
        name: wsl-tarball

    - name: Run import test
      run: |
        $tarball = Get-ChildItem *.wsl | Select-Object -First 1
        .\docs\tools\Test-WslImport.ps1 `
          -TarballPath $tarball.FullName `
          -SkipBuild `
          -SkipTerminalValidation `
          -BootTimeoutSeconds 180
```

**Note**: This spec is approximate. The Nix-in-WSL step may need adjustment
depending on how `Vampire/setup-wsl` handles the distro lifecycle. The build
distro for discovery phase would be the Ubuntu distro from setup-wsl, but since
we're using `-SkipBuild`, discovery of expectations via `nix eval` is optional.

## Sources

- [runner-images: Windows2025-Readme.md](https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-Readme.md)
- [Vampire/setup-wsl](https://github.com/Vampire/setup-wsl)
- [Blog: WSL2 on Windows 2025 runners](https://dwozny.com/posts/windows-2025-docker-wsl2/)
- [Issue #11265: WSL on windows-2025](https://github.com/actions/runner-images/issues/11265)
- [Ubuntu WSL Actions](https://documentation.ubuntu.com/wsl/stable/reference/actions/)
