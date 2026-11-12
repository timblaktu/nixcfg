# Learning Nix Here

## Who this is for

This page is for someone who is new to Nix and has just landed in this repository. You do not need to already know Nix to follow it. By the end you will understand how this repo is laid out, how one real piece of configuration flows from a file on disk into a built system, and what the house-specific vocabulary means.

A few Nix terms up front, each defined plainly (the Glossary at the bottom repeats them):

- **Nix** is a package manager and configuration language. You describe what you want in a `.nix` file, and Nix builds exactly that, reproducibly.
- A **derivation** is Nix's unit of "a thing to build" - a package, a config file, or a whole system. Nix evaluates your configuration into derivations and then realises (builds) them.
- A **flake** is a self-contained project that declares its inputs (dependencies, pinned to exact versions) and its outputs (what it produces). `flake.nix` at the repo root is the entry point.
- A **module** is a reusable chunk of configuration. Modules declare options and set values; the module system merges many modules together into one final configuration.

If you want the underlying concepts in depth, the official learning site [nix.dev](https://nix.dev) is the best starting point - in particular its introductions to the [Nix language](https://nix.dev/tutorials/nix-language), [flakes](https://nix.dev/concepts/flakes), and the [module system](https://nix.dev/tutorials/module-system/module-system).

## How to read this repo

Almost everything lives under `modules/`. Features (git, tmux, the shell, the editor) each get ONE home, regardless of which machine uses them. Machines (called **hosts**) are thin: a host mostly just lists the features it wants. This is the opposite of scattering a little bit of git config into every machine's file.

The rest of this page walks ONE real feature - git - from its file on disk all the way to a built, usable configuration, stopping at each link in the chain. Git is a good teaching example because it is small, it touches all three platforms this repo supports (NixOS, Darwin/macOS, and Home Manager for the user environment), and you almost certainly already know what git is, so the Nix machinery is the only new part.

## An end-to-end tour: the `git` module

### 1. The entry point: `flake.nix` and automatic discovery

Open `flake.nix`. It is deliberately tiny. The important part is this:

```nix
imports = [
  (import-tree [
    ./modules/flake-parts
    ./modules/meta
    ./modules/programs
    ./modules/system
    ./modules/hosts
  ])
];
```

**import-tree** is a small helper (a flake input, `github:vic/import-tree`) that walks those directories and imports EVERY `*.nix` file it finds, recursively. There is no hand-maintained list of modules anywhere. When you add a new file under `modules/`, it is picked up automatically the next time Nix evaluates the flake. So the way git enters the picture is simply: the file `modules/programs/git/git.nix` exists under `modules/programs`, therefore import-tree loads it. Nothing else references it by name.

This auto-discovery is the first half of what this repo calls the **dendritic** pattern (think of a tree growing new branches - you add a leaf file and it is absorbed into the tree without rewiring the trunk).

### 2. Dendritic registration: how a file publishes itself

Open `modules/programs/git/git.nix`. The module does not configure any particular machine directly. Instead it attaches its content under a shared namespace, `flake.modules.*`:

```nix
{
  flake.modules = {
    homeManager.git = { config, pkgs, lib, ... }: {
      programs.git = {
        enable = true;
        lfs.enable = true;
        settings = { /* aliases, delta, mergetool, ... */ };
        # ...
      };
      # delta pager, smart-nvimdiff mergetool, gitleaks, lazygit, etc.
    };

    nixos.git  = { ... }: { /* system-level git defaults */ };
    darwin.git = { ... }: { /* macOS git defaults */ };
  };
}
```

This is the second half of the **dendritic** pattern: every feature file declares named entries under `flake.modules.<platform>.<name>`. Here one file publishes three independent modules:

- `flake.modules.homeManager.git` - the rich user-level git setup (aliases, the delta pager, the neovim-based mergetool, LFS, security tools).
- `flake.modules.nixos.git` - minimal system-wide git defaults for NixOS machines.
- `flake.modules.darwin.git` - the same minimal defaults for macOS machines.

The `homeManager`, `nixos`, and `darwin` keys name the THREE flavours of configuration this repo targets:

- **NixOS** - the whole-machine operating system (abbreviated `[N]` in directory names, see the Glossary).
- **Darwin** - macOS system configuration via nix-darwin (abbreviated `[D]`).
- **Home Manager** - your personal user environment (dotfiles, shell, editor, per-user tools), which can run on top of NixOS, macOS, or even a plain Ubuntu box with Nix installed.

A feature often wants to disable the matching module that ships with upstream Home Manager, so that this repo's richer version is the only one in effect. When a module needs that, it does so with `disabledModules` written INSIDE its own dendritic entry - the override travels with the feature instead of living in some central list. (The git module here does not need to; modules like the shell do.)

### 3. What the git module actually sets

Still in `modules/programs/git/git.nix`, the `homeManager.git` entry sets ordinary Home Manager options under `programs.git`:

- `enable = true` and `lfs.enable = true` - turn on git and git-LFS.
- `settings` - the generated `~/.gitconfig`: the default branch, the merge/diff behaviour, a set of aliases (`st`, `ci`, `co`, `lg`, ...), and a credential helper.
- A **pre-commit hook** that auto-formats staged Nix files (and Rust, if present) before each commit.
- Extra packages installed into your environment: the `delta` diff pager, `lazygit`, `gitleaks` (secret scanning), `git-crypt`, and a small `smart-nvimdiff` wrapper that opens merges in neovim.

The commit-author email is deliberately NOT hard-coded to a personal address; it defaults to a neutral GitHub noreply address and can be overridden privately. That detail is not important to the tour - the point is that this one file is the single, complete source of truth for "what git looks like" everywhere in the repo.

### 4. How a host composes it

A **host** is a single machine's configuration, living under `modules/hosts/`. Open `modules/hosts/mbp [N]/mbp.nix` (an Intel MacBook Pro running NixOS). Its Home Manager section is essentially a shopping list:

```nix
flake.modules.homeManager."tim@mbp" = { config, lib, pkgs, ... }: {
  imports = [
    inputs.self.modules.homeManager.home-default   # a bundle layer
    inputs.self.modules.homeManager.shell          # feature
    inputs.self.modules.homeManager.git            # <-- our module
    inputs.self.modules.homeManager.tmux           # feature
    inputs.self.modules.homeManager.neovim         # feature
    # ...more features...
  ];
  # a little host-specific tuning follows
};
```

The line `inputs.self.modules.homeManager.git` is the link back to section 2: the host pulls in the exact module that `git.nix` published. `inputs.self` just means "this flake's own outputs," so the host is importing a module this same repo defined.

Notice two kinds of thing in that import list:

- A **feature module** like `git`, `shell`, `tmux` - one capability.
- A **bundle module** like `home-default` - a curated group of features/layers bundled together, so a host can pull in a whole baseline in one line instead of listing twenty features. (This repo stacks bundles as layers: `home-minimal` into `home-default` into `home-cli` into `home-desktop`, each adding more.)

So a machine's configuration is: pick a baseline bundle, then add the individual features you want. That composition - plus the host's own small tweaks - is the complete definition of `tim@mbp`'s user environment. The analogous whole-system (NixOS) side of the same file composes `inputs.self.modules.nixos.system-cli` the same way.

The host's two named outputs, `flake.modules.nixos.mbp` and `flake.modules.homeManager."tim@mbp"`, are then registered as buildable configurations in `modules/flake-parts/nixos-configurations.nix` and `modules/flake-parts/home-configurations.nix` respectively. Registration is kept separate from definition to avoid circular references.

### 5. How it gets built

Once a host's configuration is registered, Nix can evaluate it into derivations and build it. For the user (Home Manager) side:

```bash
# Build just the result, without changing anything live:
nix build ".#homeConfigurations.\"${USER}@$(hostname)\".activationPackage"

# Build AND switch your live user environment to it:
home-manager switch --flake ".#${USER}@$(hostname)"
```

Walking the chain backwards, here is what just happened:

```
flake.nix
  └─ import-tree discovers  modules/programs/git/git.nix
       └─ it publishes       flake.modules.homeManager.git
            └─ host imports    (modules/hosts/.../mbp.nix)
                 └─ registered flake.modules.homeManager."tim@mbp"
                      └─ output homeConfigurations."tim@mbp".activationPackage
                           └─ nix build / home-manager switch  ──►  your ~/.gitconfig, delta, lazygit, ...
```

`$(hostname)` fills in your machine's name and `${USER}` your username, so you build the configuration that matches where you are standing - never assume a name from an example. (For a whole NixOS system the equivalent is `sudo nixos-rebuild switch --flake '.#<host>'`.)

For how to validate the flake before building, how the test suite is organised, and how the WSL images are produced, see [ARCHITECTURE.md](ARCHITECTURE.md) and [SHARED-MODULES.md](SHARED-MODULES.md). For Nix fundamentals behind any step above - derivations, flakes, and the module system - [nix.dev](https://nix.dev) is the reference.

## Glossary

- **Nix** - a reproducible package manager and configuration language. You declare the desired state in `.nix` files; Nix builds exactly that.
- **derivation** - Nix's unit of "something to build": a package, a config file, or a whole system. Evaluation turns your configuration into derivations; realisation builds them.
- **flake** - a self-contained project with pinned inputs (dependencies) and declared outputs (what it produces). `flake.nix` is the repo's entry point.
- **module** - a reusable configuration unit that declares options and sets values. The module system merges many modules into one final result.
- **dendritic** (module pattern) - this repo's organising pattern: (1) import-tree auto-discovers every `modules/**/*.nix` file so there is no central import list, and (2) each file attaches its content under a shared `flake.modules.<platform>.<name>` namespace, optionally disabling an upstream equivalent via `disabledModules` inside its own entry. New features are added like branches on a tree - drop a file in, and it is absorbed.
- **import-tree** - the flake input (`github:vic/import-tree`) that recursively imports every `*.nix` file under the listed `modules/` directories, implementing the auto-discovery half of the dendritic pattern.
- **feature module** - a module providing ONE capability (e.g. `git`, `shell`, `tmux`, `neovim`). Lives under `modules/programs/`.
- **bundle module** - a module that groups several features/layers so a host can pull in a whole baseline in one import (e.g. `home-default`, `system-cli`). Bundles in this repo stack as layers, each building on the one below.
- **host** - a single machine's configuration under `modules/hosts/`. A host is thin: it mostly composes bundles and features and adds small machine-specific tweaks.
- **NixOS** - the full Linux operating system configured by Nix. Modules targeting it live under `flake.modules.nixos.*`.
- **Darwin** - macOS system configuration via nix-darwin. Modules targeting it live under `flake.modules.darwin.*`.
- **Home Manager** - per-user environment management (dotfiles, shell, editor, user tools), runnable on NixOS, macOS, or any Linux with Nix. Modules live under `flake.modules.homeManager.*`.
- **`[N]` / `[D]`** - bracket suffixes on host directory names indicating platform support: `[N]` means NixOS-only (e.g. `nixos-wsl-dev-team [N]/`), `[D]` means Darwin/macOS-only (e.g. `macbook-air [D]/`). A name with no bracket (e.g. `git/`, `shell/`) is universal across platforms.
- **RFM** - Reduced Functionality Mode, the degraded state the CrowdStrike Falcon security sensor runs in inside a WSL2 distribution (it cannot verify the custom WSL kernel). Unrelated to the module machinery above; see [CROWDSTRIKE-WSL2-SECURITY-BRIEF.md](CROWDSTRIKE-WSL2-SECURITY-BRIEF.md).
- **WSL** - Windows Subsystem for Linux, where several of this repo's hosts and pre-built images run.
