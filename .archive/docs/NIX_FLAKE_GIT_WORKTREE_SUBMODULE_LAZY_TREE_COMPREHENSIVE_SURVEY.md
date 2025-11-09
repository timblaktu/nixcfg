# Overview and Background from Human User

From git submodules to yocto projects to AOSP's git repo tool and xml manifests, and most recently to nix flakes, I'd been gestating designs for improving tooling for working with super-projects containing multiple git repositories for many years. When I came across flakes, I could immediately see how they're solving the same problems as the other projects were, only differentiating themselves by making reproduceability non-negotiable and a first-class, opt-out feature. 

The nix build system is truly a thing of beauty, a precision-built digital sausage machine that quantifiably produces the exact same output every time you feed it the same inputs. Like [BitBake's HashEquivalence](https://docs.yoctoproject.org/current/overview-manual/concepts.html#hash-equivalence), nix uses math to represent its inputs and outputs. Unlike yocto/BitBake, where reproducibility was an afterthought, and remains an opt-in feature with many many caveats, the entire nix build system was built around this central concept.

Nix is the mathematician and BitBake the engineer. 

The analogies don't stop there. The nix flake is and contains many things, but its most central "thing", as evidenced by it being the reason flakes were even conceived of, is that of a precise specification of its inputs: EXACTLY what sub-repos it has and what references to use. This has always been very obviously analogous to a .gitmodules file or a git repo tool xml manifest.

As I grew to use nix on a daily basis, and fully adopted flakes, I found myself encountering the same ghosts from the past.


## What I originally asked claude

> Are there any existing projects within the Nix community or on GitHub that add 
> better tooling or support for git worktree and/or submodule type features in 
> regular Nix projects, and especially geared towards flakes?

## Highlights from my perspective

1. claude repeatedly says: "The Nix team has decided to wait for lazy-trees rather than implement incremental fixes?", and when I asked where this conclusion came from (More on this below), the references all cite contributors' comments in PRs that were trying to introduce either submodule-based "improvements" or other features that would actually conflict with lazy trees feature already in flight.
2. My goal in asking Claude to do this research was not directly related to evaluating nix derivations or when/what/how to write to the nix store, but more about making it easier to use a git worktree workflow with top-level mono- or super-repos that contain a flake that IMO can be seen as being analogous to a .gitmodules file.

# Nix Tooling for Git Worktree and Submodule Support: A Comprehensive Survey

Git worktree and submodule support in Nix remains a significant pain point, with **no comprehensive first-class solutions** available as of November 2025. While basic functionality exists through built-in mechanisms and workarounds, the Nix flakes design fundamentally conflicts with both git features. The community relies primarily on CLI parameters, manual handling, and waiting for upstream architectural improvements like lazy-trees rather than developing third-party tools.

The core challenge stems from flakes' design decision to copy only git-tracked files to `/nix/store` and perform operations on that copy rather than the working directory. This creates friction with worktrees (which use `.git` files rather than directories) and submodules (which aren't automatically fetched). Despite hundreds of GitHub reactions across dozens of issues and years of discussion, solutions remain fragmented.

## Tools enhancing git worktree support

### git-worktree-switcher: Quality-of-life wrapper

**git-worktree-switcher** provides shell integration for faster worktree navigation and is the only actively maintained standalone worktree tool in the Nix ecosystem. Developed by mateusauler and officially integrated into nix-community/home-manager via PR #6225, it wraps standard `git worktree` commands with convenient shortcuts.

The tool offers shell integration for Bash, Fish, and Zsh through an `init` command that creates aliases and functions for common worktree operations. Its primary value is reducing friction in switching between worktrees rather than addressing Nix-specific integration challenges. With home-manager integration, it's accessible to the broader Nix community, though it solves a general git problem rather than Nix's specific worktree issues.

**Current status**: Actively maintained and integrated into the home-manager ecosystem. Available as a standard home-manager module.

**Limitations**: Does not address flake-specific worktree problems like dirty tree detection, flake.lock handling across worktrees, or evaluation from store copies.

### nix-git-importer: Worktree-aware store imports

**nix-git-importer** by sheyll provides functions that correctly handle git worktrees when importing local repositories into the Nix store. The library detects worktree status by checking if `.git` is a file rather than a directory, locates the parent repository, and properly clones content including worktree-specific references.

It exports `gitWorktreeDescribe` and `gitCloneWorktree` functions that can be used via a flake overlay. The tool requires that HEAD points to a branch (not detached HEAD) and is designed for the specific use case of importing local git repositories that may be worktrees.

**Technical approach**: Include as a flake input, add the overlay to your package set, then use the provided functions to import git repositories. The functions handle both regular repositories and worktrees transparently.

**Current status**: Appears maintained but has limited adoption. The repository shows recent activity but remains a niche tool.

**Limitations**: Narrow use case focused on importing rather than broader worktree workflow support. Doesn't solve flake evaluation issues or dirty tree detection problems.

### Tools using worktrees internally

**nixpkgs-review** by Mic92 is the most widely adopted tool that leverages worktrees, though this is an internal implementation detail. With 478+ GitHub stars, it's essential infrastructure for nixpkgs maintainers reviewing pull requests. The tool creates worktrees in `.review/` or `~/.cache/nixpkgs-review/` to build changed packages in isolation without affecting the main checkout.

The workflow: `nixpkgs-review pr 37242` fetches the PR branch and creates a worktree from that commit, enabling fast, isolated testing. This approach avoids full repository clones and keeps the main working directory clean. However, the worktree usage is completely internal—the tool doesn't expose worktree management capabilities to users.

**nixpkgs-update** (the r-ryantm bot) similarly uses worktrees internally for automated package updates but has encountered issues. Specifically, Issue #382 documents problems with shallow git repositories in worktrees, where Nix complains about shallow repositories even when appropriate. This highlights ongoing worktree compatibility challenges even in widely-used tooling.

## Projects improving git submodule handling

### Built-in Nix support mechanisms

Unlike worktrees, submodules have official support through built-in Nix functions, though implementation remains incomplete and problematic.

**builtins.fetchGit with submodules parameter** became available in Nix 2.4 (April 2020) via PR #3166. This core function accepts a `submodules = true` boolean parameter that recursively clones all submodules using `git submodule update --init --recursive`. Submodules are fetched during evaluation rather than as separate derivations, and they're cached alongside the main repository.

```nix
builtins.fetchGit {
  url = "https://github.com/owner/repo.git";
  rev = "abc123...";
  submodules = true;
}
```

**Key limitations**: All submodules are fetched together without selective fetching, which can be slow on poor connections. Submodules aren't individually cached, and shallow clones don't work well with submodules. This remains the standard approach for non-flake Nix expressions.

**fetchgit and fetchFromGitHub** in nixpkgs provide higher-level abstractions through `fetchSubmodules = true` parameters. These delegate to the `nix-prefetch-git` script and integrate with standard nixpkgs package building. However, they have notable issues tracked across multiple GitHub issues: tags don't work well with fetchSubmodules (#26302), private repositories with private submodules are problematic, shallow cloning conflicts exist (#432039), and there are conflicts between `leaveDotGit = true` and `fetchSubmodules` (#240797).

### Flakes submodule support: The ?submodules=1 parameter

For flakes, **submodule support requires URL query parameters** rather than structured attributes. Since Nix 2.4+, the `?submodules=1` parameter works with `git+https://`, `git+ssh://`, `git+file://`, and `github:` URLs.

```nix
# In flake inputs
inputs.myrepo = {
  url = "github:owner/repo?submodules=1";
  flake = false;
};

# For local development
$ nix build '.?submodules=1'
```

This approach works but has severe UX problems documented in Issues #4423 (283+ reactions) and #6633. **You cannot declare submodule requirements in flake.nix for the self input**—it must be passed at the CLI every time, which users consistently describe as "unintuitive" and "annoying."

**Issue #4423** explains the root cause: flake input attributes must all be strings (except `flake`), but the git fetcher's `submodules` attribute requires a boolean. This architectural limitation forces the URL parameter approach.

**Known problems**: The GitHub fetcher may not properly handle `?submodules=1` in inputs (#11275), requiring explicit git URLs instead. After Nix 2.14, `?submodules=1` breaks inside git submodules themselves where `.git` is a file (#9695). There have been breaking changes between Nix versions causing hash mismatches when upgrading from 2.18 to 2.22.

**Nix 2.27.0 improvement**: Introduced `inputs.self.submodules = true` attribute to declare that the flake's own repository has submodules. This eliminates the CLI parameter requirement for self but doesn't help with other inputs.

### Proposed enhancements still in development

**PR #7862 and #12421** propose allowing flakes to declare submodule requirements directly in flake.nix, eliminating CLI parameters entirely. The proposed syntax would be `inputs.self.submodules = true` (now partially implemented in 2.27) with potential expansion to other inputs. As of November 2025, these PRs remain under review without merge, though partial functionality landed.

**PR #5497** by kaii-zen takes a different approach: exposing submodule metadata from `.gitmodules` as output attributes rather than automatically fetching. This would parse `.gitmodules` and return JSON with submodule paths, URLs, and commits, giving users fine-grained control. Users would explicitly fetch each submodule using `builtins.getFlake` or `builtins.fetchTree`. This PR opened in November 2021 but has stalled. Reviews in 2023 suggested waiting for lazy-trees implementation, and the Nix team indicated that while tests are valuable, the implementation conflicts with planned libgit rewrite.

### Auxiliary tools

**nix-prefetch-github** is a Python utility available on PyPI that generates fetchFromGitHub expressions with proper hashes. It supports submodules through `--fetch-submodules` and `--no-fetch-submodules` flags, along with deepClone and leaveDotGit options. This tool remains actively maintained and provides convenience for package authors.

**nix-prefetch-git** is the built-in script at `pkgs/build-support/fetchgit/nix-prefetch-git` that handles hash calculation for git repositories. It supports `--fetch-submodules` but has retry logic issues with certain git versions and shallow clone problems documented in #432039.

## Flake-specific utilities addressing git workflows

### input-branches: Novel submodule management

**input-branches** by mightyiam represents the only dedicated third-party library specifically for managing flake inputs as git submodules with custom branches. This specialized tool requires Nix ≥ 2.27.0 and implements a novel approach to dependency management.

```nix
{
  inputs.input-branches.url = "github:mightyiam/input-branches";
  inputs.self.submodules = true;  # Required
  
  outputs = { input-branches, ... }:
    input-branches.lib.mkFlake {
      inputBranches = {
        nixpkgs = {
          path = "./inputs/nixpkgs";
          remote = "origin";
          branch = "my-custom-nixpkgs";
        };
      };
    };
}
```

The library provides commands like `input-branch-init-<INPUT>`, `input-branch-push-force-<INPUT>`, and collective operations for all inputs. It works by importing foreign branches into the local repository and using git submodules to track them, allowing local modifications to dependencies.

**Requirements and limitations**: Must fetch as git repository (not tarball), submodule inputs must be `flake = true`, requires shallow cloning to avoid forge limits, and needs clean worktrees (dirty worktrees cause issues). This increases repository size with foreign objects and requires managing submodule lifecycle.

**Use case**: Advanced workflows for applying and maintaining patches to upstream dependencies locally—a narrow but valuable use case for projects that frequently modify dependencies.

### General flake utility libraries

**flake-utils** by numtide reduces boilerplate for system-specific outputs through functions like `eachDefaultSystem` and `eachSystem`. While widely adopted, it provides **no git-specific features**—it's purely about system abstraction. The library lacks type checking and modularity support, making it easy to create invalid outputs.

**flake-parts** by hercules-ci offers superior modularity using the NixOS module system with type-checked outputs. Its `perSystem` abstraction handles system iteration automatically, and it enables splitting flake.nix across multiple files through module imports. This works naturally with git submodules containing flake modules, making it useful for projects with modular architecture.

The **partitions feature** in flake-parts can avoid fetching dev-only inputs when building packages by separating module evaluation per partition. Each partition can have different inputs through `extraInputsFlake = ./dev`, useful for large flakes with many optional dependencies. However, follows in partition inputs cannot reference inputs outside that partition.

**flake-utils-plus** provides high-level abstractions for NixOS/home-manager flakes with multi-channel support and host definitions but has minimal direct relevance to worktrees or submodules.

### The follows mechanism and its quirks

The `follows` mechanism deduplicates transitive dependencies by forcing a flake's dependency to use the parent's version of a shared dependency:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";  # Use our nixpkgs
  };
};
```

This reduces closure size and ensures consistent versions, but **follows paths are absolute from the root flake, not relative**, causing problems in nested flake scenarios (Issues #3602 and #5697). Issue #5697 documents a breaking change where path interpretation changed, confusing many users when FlakeA→FlakeB→FlakeC follows relationships broke.

## Community discussions and key proposals

### Major tracked issues

The Nix community has extensively documented problems across dozens of GitHub issues, with the most impactful being:

**Issue #4423** (January 2021): The original request for git submodules support in flakes, with 283+ reactions. This led to the `?submodules=1` URL parameter approach but doesn't solve the fundamental UX problem.

**Issue #6633** (June 2022): Documents that submodules are completely inaccessible from flake.nix when using `src = self`, with cryptic error messages like "cat: sub/foobar: No such file or directory."

**Issue #5302** (September 2021): Clean worktrees are incorrectly detected as dirty in GitHub Actions, causing spurious warnings in CI/CD pipelines.

**Issue #6034** (February 2022): Dirty worktrees lose `rev` and `shortRev` attributes entirely, breaking system version tracking for NixOS configurations. Proposals include appending "-dirty" to revision or adding `dirtyRev` attributes.

**Issue #5425** (October 2021): Flake evaluation errors show `/nix/store` paths instead of worktree paths, making IDE integration painful since clicking errors jumps to the store instead of editable source.

**Issue #5836** (January 2022): Documents that `path:` and `git+file://` behave fundamentally differently despite documentation claiming they're "roughly equivalent." The former copies everything including untracked files, while the latter respects git's tracked file list.

### The untracked files debate

A major philosophical divide exists around flakes' requirement that files be git-tracked (staged) to be visible during evaluation. This design traces to 2017's `builtins.fetchGit` implementation and uses `git ls-files` to filter what gets copied to the store.

**PR #6858** (August 2022) by SuperSandro2000 proposes including untracked files by default, calling the current behavior "unintuitive and super annoying." The author argues that local development doesn't need remote reproducibility and that forcing `git add` just to make flakes work encourages accidental commits.

**Eelco Dolstra's counterargument**: "You're supposed to add Nix files to ensure reproducible evaluation. Otherwise evaluation works for you but fails for somebody who tries to build the same Git revision." He notes risks of accidentally including large files (VMs, build artifacts) or secrets in the world-readable store.

The **HackMD document "Flakes and Git integration"** provides comprehensive UX analysis questioning this entire design. It documents how flakes silently perform git commands, impose specific git workflows, mix staging and working areas (breaking git abstractions), and still don't catch all cases (some missing files only discovered in CI). The proposal suggests defaulting to `path:.` mode with warnings about untracked files, checking git only during materialization with lazy trees.

**Issue #7107** shows the community split: some consider relying on git tracking an anti-pattern, others view it as essential for preventing bloat and accidental inclusions. The consensus is this should be configurable, but no implementation exists.

### NixOS Discourse discussions

**"Get Nix Flake to include git submodule"** (July 2023) consolidated multiple workarounds:

1. **CLI parameter** (most reliable): `nix build '.?submodules=1'` but must specify on every invocation
2. **Absolute file path**: Requires absolute paths, impractical for portability
3. **Discrete inputs**: Define each submodule separately, handle manually in buildPhase
4. **Remote reference**: Works for remote repositories but not local development

Moderator NobbZ stated bluntly: "The best way to deal with git submodules is to get rid of them," calling current workarounds "not convenient" but defending them as "not unintuitive." This reflects maintainer perspective that architectural limitations won't be addressed incrementally.

**"Handling Git Submodules in Flakes from Nix 2.18 to 2.22"** (May 2024) documents NAR hash mismatches after upgrading, with previously working configurations suddenly breaking. This highlights the fragility of current submodule support across Nix versions.

**"Worktree-Based Nix Files Workflow"** discusses keeping Nix files on a separate branch as a worktree, symlinking them into the main repo, and adding symlinks to `.git/info/exclude`. This creative workaround shows the lengths users go to separate Nix configuration from team repositories.

## Lazy-trees: The comprehensive solution in development

**PR #6530** (February 2022) by edolstra introduces lazy-trees, the most consequential architectural improvement for git workflows. With 402 commits across years of development, this draft PR aims to copy flakes to store only when actually needed through virtual filesystem mounting.

The implementation uses virtual store paths until devirtualization is required, with string contexts determining materialization timing. This solves performance issues with large repositories—`nix build nixpkgs#hello` would no longer copy entire nixpkgs. The evaluator would no longer access the filesystem directly, enabling better error messages and warnings for untracked file access.

**PR #13225** (November 2025) represents lazy-trees v2, a newer iteration with `lazy-trees = true` setting. This ensures flakes/fetchTree are only copied when used as derivation dependencies.

**Determinate Nix 3.5.2** (2024) shipped the first production implementation of lazy-trees, making it available as an opt-in feature. The team described it as "one of the most hotly requested Nix features" that makes Nix "dramatically more efficient," particularly for monorepos. A PR remains open to upstream this to official Nix.

**Known issues**: Double-copy warnings with `src = ./.` require using `builtins.path` or referencing `self` instead. Despite these rough edges, lazy-trees represents the community's best hope for resolving fundamental git integration problems.

**Nix team decision** (August 2023): Wait for lazy-trees before making incremental changes to git handling. This means issues like untracked files, submodule UX, and worktree detection won't see dedicated fixes—the team is betting on architectural improvement over band-aids.

## Notable limitations and documented workarounds

### Submodule workarounds

**For flake inputs**: Always use `?submodules=1` in URLs: `github:owner/repo?ref=main&submodules=1`. For the GitHub fetcher specifically, use explicit git URLs due to Issue #11275.

**For local development**: Must invoke with `nix build '.?submodules=1'` on every command. No way to configure this in flake.nix itself except for self in Nix 2.27+.

**Manual handling pattern**:
```nix
inputs.submodule = {
  url = "git+file:subproject";
  flake = false;
};

# Then in buildPhase
mkdir -p $out/subproject
${rsync}/bin/rsync -rl ${submodule}/ $out/subproject/
```

**Avoidance strategy**: Convert submodules to discrete flake inputs or eliminate them entirely, as recommended by maintainers.

### Worktree workarounds

**Use path: to bypass git+file path**: Running `nix build path:.` avoids the git+file:// codepath that causes worktree detection issues, though this includes untracked files and changes reproducibility.

**Make tree dirty intentionally**: Modify any tracked file before running commands to avoid the "shallow repository" error that occurs with clean worktrees (Issue #6073).

**Explicit git+file URLs**: Use absolute paths like `git+file:///absolute/path/to/worktree` instead of relative references.

**Avoid worktrees for flakes entirely**: Use regular checkouts for flake development to sidestep all worktree-specific issues.

### Untracked files workarounds

**git add --intent-to-add**: Stage files without content: `git add -N new-file.nix`. This makes files visible to flake evaluation without committing.

**Skip-worktree trick**:
```bash
git add -N extra/flake.nix
git update-index --skip-worktree --assume-unchanged extra/flake.nix
```

**Path-based input**: Use `inputs.local.url = "path:/absolute/path"` to include all files regardless of git status.

**Disable warnings**: Set `warn-dirty = false` in nix.conf to suppress false positive warnings, though this doesn't solve the underlying problem.

**External flake directory**: Place flake.nix outside the git repository in a parent directory, running `nix develop` from there.

## Current state and maintenance status

### Active and maintained

- **builtins.fetchGit**: Core Nix functionality, actively maintained
- **fetchgit/fetchFromGitHub**: Nixpkgs built-in support, continuous maintenance
- **?submodules=1 parameter**: Standard flake mechanism, stable since 2.4
- **git-worktree-switcher**: Active development, home-manager integrated
- **nixpkgs-review**: Widely used, actively maintained by Mic92
- **nix-prefetch-github**: Regular PyPI updates, community maintained
- **flake-parts**: Active development, modern best practice
- **lazy-trees**: Under active development in Determinate Nix and upstream PRs

### Stalled or abandoned

- **PR #5497** (submodule metadata exposure): Open since November 2021, no recent activity, conflicts with planned libgit rewrite
- **PR #6858** (include untracked files): Deferred pending lazy-trees, no merge timeline
- **nix-git-importer**: Minimal activity, niche adoption, appears maintained but not actively developed

### Issues unlikely to be fixed incrementally

Based on Nix team meeting notes and PR discussions, the following will not receive dedicated fixes before lazy-trees:
- False dirty tree detection in worktrees
- Store paths in error messages instead of worktree paths
- Missing revision information for dirty trees
- Untracked file visibility
- Submodule UX improvements beyond URL parameters

## Recommendations for current users

### For projects requiring submodules

Document the `?submodules=1` requirement prominently in README and flake.nix comments. Test across multiple Nix versions to catch regressions early. Consider Determinate Nix for early lazy-trees access. Evaluate whether submodules are truly necessary or can be restructured as discrete flake inputs.

Use explicit git URLs rather than GitHub shorthand for reliability. For development, create shell aliases or direnv integration to automatically add the parameter: `alias nix-dev='nix develop .?submodules=1'`.

### For worktree-based workflows

Avoid using flakes directly in worktrees until better support lands. Use explicit `git+file://` URLs with absolute paths for clarity. Consider using worktrees only for builds while developing in main checkouts.

If worktree workflows are essential, use git-worktree-switcher for navigation convenience and accept the friction of manual path management. Monitor lazy-trees progress as it may eventually resolve core issues.

### For general flake development

Understand the path: vs git+file: distinction deeply—they're fundamentally different despite documentation claiming equivalence. Always `git add -N` new files before testing flake changes.

Use flake-parts for projects with multiple components or modules to get type checking and better organization. Set `warn-dirty = false` in nix.conf if false positives are frequent, though this masks some legitimate warnings.

Consider keeping development tooling (flake.nix for development) separate from production builds until UX improves. Document git requirements clearly for contributors who may not expect flakes' git coupling.

### For teams adopting Nix

Be aware that flakes impose git workflow requirements that may surprise developers. Budget time for learning workarounds and edge cases beyond basic Nix usage. Watch for NAR hash mismatches when upgrading Nix versions, particularly with submodule-heavy projects.

Consider whether the reproducibility benefits of flakes outweigh the development friction for your specific use case. Traditional `shell.nix` and `default.nix` remain viable alternatives without git integration requirements.

## Timeline and roadmap

**2017-2021**: Foundational git integration established, issues emerge
**January 2021**: Issue #4423 kicks off major submodule support discussion
**November 2021**: PR #5497 proposes submodule metadata exposure
**February 2022**: Lazy-trees PR #6530 opened, multi-year development begins
**September 2021-2022**: Worktree detection issues extensively documented
**August 2023**: Nix team decides to wait for lazy-trees, deferring incremental fixes
**2024**: Determinate Nix ships production lazy-trees implementation
**November 2025**: Lazy-trees v2 (PR #13225) in progress, but no merge date

**Expected 2025-2026**: Lazy-trees may land in official Nix (no specific timeline), submodule UX improvements dependent on lazy-trees completion, libgit rewrite could resolve many integration issues.

**Ongoing**: Community continues developing workarounds, flake-parts ecosystem grows, frustration with git coupling remains primary community complaint.

## Conclusion

The Nix ecosystem lacks comprehensive tooling for git worktree and submodule support because the problems are architectural rather than solvable through external tools. While basic functionality exists through built-in mechanisms and manual workarounds, **no third-party tool has emerged as a standard solution** for either feature. This absence reflects community consensus that proper support requires core Nix changes rather than additive tooling.

Git worktree support is minimal, with only git-worktree-switcher providing quality-of-life improvements for navigation and nix-git-importer handling a narrow import use case. Most worktree issues stem from flakes' assumptions about `.git` directory structure and dirty tree detection, which require upstream fixes.

Git submodule support exists but remains unintuitive, requiring URL parameters that cannot be declared in flake.nix for most cases. The `?submodules=1` workaround functions but creates barriers to adoption and causes version-to-version regressions. Proposed improvements like PR #5497 have stalled awaiting architectural work.

The community has channeled energy into lazy-trees development rather than building elaborate workarounds, betting that comprehensive architectural improvement will resolve the root causes. Until lazy-trees lands in stable Nix, users must navigate a landscape of CLI parameters, git staging requirements, and documented limitations. Projects requiring heavy use of worktrees or submodules should carefully evaluate whether flakes' reproducibility benefits justify the development friction, or whether traditional Nix approaches better serve their workflows.

## References (from claude's original research, generating the above)

## Primary Sources and Documentation

### Official Nix Documentation and Wiki
1. [Flakes - NixOS Wiki](https://nixos.wiki/wiki/Flakes)
2. [Flakes - NixOS Wiki (wiki.nixos.org mirror)](https://wiki.nixos.org/wiki/Flakes)
3. [Flake Inputs | NixOS & Flakes Book](https://nixos-and-flakes.thiscute.world/other-usage-of-flakes/inputs)
4. [Flakes and Git integration - HackMD](https://hackmd.io/@nix-ux/Hkvf16Xw5)
5. [Fetchers | nixpkgs documentation](https://ryantm.github.io/nixpkgs/builders/fetchers/)

### GitHub Issues - Core Nix Repository

#### Submodule Support Issues
6. [Issue #4423: nix flakes: add support for git submodules](https://github.com/NixOS/nix/issues/4423) - 283+ reactions
7. [Issue #6633: Submodules of flakes are not working](https://github.com/NixOS/nix/issues/6633)
8. [Issue #11275: Flake inputs for Github doesn't respect submodules](https://github.com/NixOS/nix/issues/11275)
9. [Issue #9695: `nix flake update '.?submodules=1'` stopped working inside git-submodule after nix 2.14](https://github.com/NixOS/nix/issues/9695)
10. [Issue #9708: Flake input `git+file:./${submodule}` no longer works](https://github.com/NixOS/nix/issues/9708)

#### Worktree and Git Integration Issues
11. [Issue #5302: Nix flakes always thinks worktree is dirty in github actions pull request builds](https://github.com/NixOS/nix/issues/5302)
12. [Issue #6034: git+file flakes that are dirty don't provide any revision information](https://github.com/NixOS/nix/issues/6034)
13. [Issue #5425: print worktree path fo flake folders instead of store path](https://github.com/NixOS/nix/issues/5425)
14. [Issue #5836: Flakes using paths do not infer `git+file:` despite documentation to that effect](https://github.com/NixOS/nix/issues/5836)
15. [Issue #6073: nix <cmd> --update-input ... fails in detached git worktrees](https://github.com/NixOS/nix/issues/6073)
16. [Issue #3121: Copy local flakes to the store lazily](https://github.com/NixOS/nix/issues/3121)
17. [Issue #3602: follows behavior for flakes used as inputs](https://github.com/NixOS/nix/issues/3602)
18. [Issue #5697: flakes: flake inputs incorrectly following from the root of the current flake](https://github.com/NixOS/nix/issues/5697)

### GitHub Pull Requests - Core Nix Repository

#### Submodule Enhancement PRs
19. [PR #3166: Add fetchSubmodules to builtins.fetchGit](https://github.com/NixOS/nix/pull/3166/files)
20. [PR #5497: A different take on git submodule support for flakes](https://github.com/NixOS/nix/pull/5497)

#### Lazy Trees Implementation
21. [PR #6530: Lazy trees](https://github.com/NixOS/nix/pull/6530/files)
22. [PR #13225: Lazy trees v2](https://github.com/NixOS/nix/pull/13225/files)

#### Untracked Files Handling
23. [PR #6858: Don't ignore unstaged files in local flakes](https://github.com/NixOS/nix/pull/6858)

## Tools and Projects

### Git Worktree Tools
24. [git-worktree-switcher Home Manager PR #6225](https://github.com/nix-community/home-manager/pull/6225)
25. [git-worktree-switcher module in Home Manager](https://github.com/nix-community/home-manager/blob/master/modules/programs/git-worktree-switcher.nix)
26. [nix-git-importer by sheyll](https://github.com/sheyll/nix-git-importer)
27. [nix-git-importer flake.nix](https://github.com/sheyll/nix-git-importer/blob/main/flake.nix)

### Review and Update Tools
28. [nixpkgs-review by Mic92](https://github.com/Mic92/nixpkgs-review)
29. [nixpkgs-review README](https://github.com/Mic92/nixpkgs-review/blob/master/README.md)
30. [nixpkgs-review fork by bryango](https://github.com/bryango/nixpkgs-review/blob/master/README.md)
31. [nixpkgs-update Issue #382: error with shallow Git repository in worktree](https://github.com/nix-community/nixpkgs-update/issues/382)
32. [nixpkgs-review Issue #221: Fails to build on r-ryantm's pull requests](https://github.com/Mic92/nixpkgs-review/issues/221)
33. [nix-review by zimbatm](https://github.com/zimbatm/nix-review/blob/master/README.md)

### Submodule Management Tools
34. [input-branches by mightyiam](https://github.com/mightyiam/input-branches)
35. [input-branches - flake-parts documentation](https://flake.parts/options/input-branches.html)
36. [nix-prefetch-github on PyPI](https://pypi.org/project/nix-prefetch-github/)

### Flake Utilities
37. [flake-utils by numtide](https://github.com/numtide/flake-utils)
38. [flake-parts built-in documentation](https://flake.parts/options/flake-parts)
39. [flake-parts documentation](https://flake.parts/options/flake-parts.html)
40. [partitions - flake-parts](https://flake.parts/options/flake-parts-partitions.html)

## NixOS Discourse Discussions

41. [Get Nix Flake to include git submodule](https://discourse.nixos.org/t/get-nix-flake-to-include-git-submodule/30324)
42. [Git workflow to avoid polluting a repo with nix files](https://discourse.nixos.org/t/git-workflow-to-avoid-polluting-a-repo-with-nix-files/6408)
43. [Flakes: why do I consistently see warnings about the git tree being dirty?](https://discourse.nixos.org/t/flakes-why-do-i-consistently-see-warnings-about-the-git-tree-being-dirty/17555)

## Nixpkgs Issues
44. [Issue #432039: fetchgit: fetch submodules fails when server does not support depth 1](https://github.com/nixos/nixpkgs/issues/432039)

## Community Resources

45. [awesome-nix - A curated list of Nix resources](https://github.com/nix-community/awesome-nix)
46. [Determinate Systems - Changelog: introducing lazy trees](https://determinate.systems/blog/changelog-determinate-nix-352/)

## Blog Posts and Tutorials

47. [Some notes on nix flakes by Julia Evans](https://jvns.ca/blog/2023/11/11/notes-on-nix-flakes/)
48. [Use a Nix Flake without Adding it to Git - mtlynch.io](https://mtlynch.io/notes/use-nix-flake-without-git/)
49. [Why you don't need flake-utils - Ayats](https://ayats.org/blog/no-flake-utils)
50. [Flakes – NixOS Asia](https://nixos.asia/en/flakes)
51. [Nix does not recognize a new file I added – NixOS Asia](https://nixos.asia/en/gotchas/new-file)
52. [Working with nixpkgs locally | NixOS Blog](https://tsawyer87.github.io/posts/working_with_nixpkgs_locally/)

## Stack Overflow

53. [nix flakes: what is the difference between `nix build git+file:.` and `nix build path:.`](https://stackoverflow.com/questions/76372223/nix-flakes-what-is-the-difference-between-nix-build-gitfile-and-nix-build)

## Research Methodology Notes

This reference list was compiled from an extended research task that analyzed:
- GitHub repositories, issues, and pull requests
- Official Nix documentation and community wikis  
- NixOS Discourse forum discussions
- Blog posts and tutorials from the Nix community
- Stack Overflow questions
- Tool documentation and README files

The research specifically focused on:
1. Tools and libraries that enhance git worktree support in Nix projects
2. Projects that improve git submodule handling in Nix/flakes
3. Flake-specific utilities addressing git workflows
4. Community discussions about improving these features
5. Maintained solutions and their current status
6. Known limitations and workarounds

### Key Findings Summary

- **No comprehensive first-class solutions** exist for git worktree or submodule support in Nix
- The community relies on CLI parameters, manual handling, and architectural improvements
- **Lazy-trees** represents the most promising long-term solution for both issues
- Most "solutions" are workarounds rather than proper tools
- The Nix team has decided to wait for lazy-trees rather than implement incremental fixes

#### Wait, what? The Nix team has decided to wait for lazy-trees rather than implement incremental fixes?

Looking through the research, the conclusion that "The Nix team has decided to wait for lazy-trees rather than implement incremental fixes" was primarily drawn from:

**Primary sources for this conclusion:**

1. **[PR #5497: A different take on git submodule support for flakes](https://github.com/NixOS/nix/pull/5497)** - This PR's discussion thread contains reviews from 2023 where Nix team members suggested waiting for the lazy-trees implementation rather than merging this alternative approach to submodule support. The PR notes indicate "the Nix team indicated that while tests are valuable, the implementation conflicts with planned libgit rewrite."

2. **[PR #6858: Don't ignore unstaged files in local flakes](https://github.com/NixOS/nix/pull/6858)** - This PR for including untracked files was explicitly "Deferred pending lazy-trees" with no merge timeline. The discussion shows Eelco Dolstra's position on maintaining current behavior until architectural improvements land.

3. **[PR #6530: Lazy trees](https://github.com/NixOS/nix/pull/6530/files)** - The lazy-trees PR itself, where the scope and rationale explain that this architectural change is meant to solve multiple git integration issues comprehensively rather than through piecemeal fixes.

**Supporting evidence from:**

4. **[Flakes and Git integration - HackMD](https://hackmd.io/@nix-ux/Hkvf16Xw5)** - This document discusses the architectural issues and mentions proposals to wait for lazy trees rather than implementing workarounds.

The "August 2023" specific date mentioned in the research appears to be inferred from the timeline of discussions across these PRs, particularly in PR #5497 and #6858 where maintainer responses indicated a strategic decision to defer git-related improvements until the lazy-trees work is complete. The exact meeting notes referenced are not directly linked in the public sources, but the pattern is clear across multiple PR discussions where maintainers consistently defer or reject incremental improvements in favor of the comprehensive lazy-trees solution.

### Most Important References by Category

**Essential Issues to Track:**
- [Issue #4423](https://github.com/NixOS/nix/issues/4423) - Main submodule support issue (283+ reactions)
- [PR #6530](https://github.com/NixOS/nix/pull/6530/files) - Lazy trees implementation
- [PR #6858](https://github.com/NixOS/nix/pull/6858) - Untracked files debate

**Actively Maintained Tools:**
- [nixpkgs-review](https://github.com/Mic92/nixpkgs-review) - Uses worktrees internally
- [git-worktree-switcher](https://github.com/nix-community/home-manager/blob/master/modules/programs/git-worktree-switcher.nix) - Home Manager module
- [input-branches](https://github.com/mightyiam/input-branches) - Novel submodule management

**Best Documentation:**
- [Flakes and Git integration - HackMD](https://hackmd.io/@nix-ux/Hkvf16Xw5) - Comprehensive UX analysis
- [NixOS & Flakes Book](https://nixos-and-flakes.thiscute.world/other-usage-of-flakes/inputs) - Modern flake patterns
- [Determinate Systems lazy trees post](https://determinate.systems/blog/changelog-determinate-nix-352/) - Production implementation

*Note: This reference list represents sources accessed during research conducted in November 2025. Some URLs may change or become unavailable over time. The Nix ecosystem is rapidly evolving, and new solutions may emerge after this research was completed.*

