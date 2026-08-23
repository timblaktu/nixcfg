# CI model: classification as a flake output

## Purpose

The set of checks this flake defines, and the facts about how each one should run in CI (how often, by what means, on which architectures, needing which builder capabilities), are described once in the flake, next to the checks themselves. Continuous integration is then a function of that description rather than a separately maintained list. Adding or changing a check is a single edit in one place, and a guard makes it impossible to add a check that CI would silently ignore.

## The shape of it

Three pieces live in the flake:

- A classification map: for every check, when it runs, how it runs, on which architectures it is meaningful, and which builder capabilities it needs.
- A derived manifest: the same information as plain data, ready for a CI system to turn into concrete jobs.
- A drift guard: an ordinary check that fails if any check is missing from the classification, or the classification names a check that does not exist.

The CI configuration for a given platform is thin. It reads the manifest and renders it into that platform's own job format, and supplies only the things that are genuinely platform's own: which runners to use and which build cache to talk to. It contains no list of checks and no knowledge of tiers or backends.

## What a downstream flake reuses

Another flake that consumes this one as an input does not inherit this flake's checks, its classification, or its pipeline. Those belong to this repository and its own CI. A downstream repository has its own checks (its own hosts and configurations) and runs its own pipeline on its own platform.

What crosses the boundary is small and deliberate:

- The convention that every check runs by building it from the flake by name.
- The classification vocabulary: the same set of tiers and backends, so a downstream flake describes its checks the same way.
- The mechanism itself, exported as a reusable library (`ci.lib.mkMatrix` and `ci.lib.mkDriftGuard`), so a downstream flake applies the same pattern to its own checks instead of reimplementing it.

A downstream flake therefore classifies its own checks, derives its own manifest with the shared functions, adds its own drift guard, and renders its own platform's pipeline. The pattern is shared; the data and the pipelines are not.

## The classification, described

Each check carries four facts and one optional flag.

Tier is when it runs: on every change, on a schedule only, or locally only (never in CI).

Backend is how it runs and what it needs: a source lint; an evaluation with no build; a plain build of a derivation; a container based virtual machine test; a full virtual machine test that needs hardware virtualization; or an image build. The backend implies the builder capability required, if any.

Systems is the set of architectures on which the check is meaningful. A CI platform runs a check only where it has that requirement covered. Container based tests are meaningful on every supported architecture. Full virtual machine tests need hardware virtualization, so a platform runs them only on architectures whose runners provide it.

The optional flag lets a check stay classified but temporarily excluded from CI, for the case where a check is blocked on an unrelated upstream fix. It remains a real check and the guard still requires it to exist; re-including it later is a single change.

## Why the guard matters

Because the guard is itself an ordinary check that runs on every change, a check added without a classification fails the build and cannot be merged. This is what keeps CI a faithful function of the flake: the classification cannot fall behind the checks, and a platform's pipeline cannot quietly stop testing something.

## Decisions

Architecture coverage starts conservative. Evaluations, lints, builds, and full virtual machine tests run on the primary architecture only; container based tests run on every supported architecture. Full virtual machine tests on a second architecture depend on runners that provide hardware virtualization there, and are taken up when that becomes available rather than assumed now.

The classification carries intent only. Concrete runner and cache choices are computed by each platform's thin adapter, so the flake stays independent of any particular CI system or runner pool.

## Related documents

- [TESTING-NSPAWN.md](TESTING-NSPAWN.md): the container based test backend and its builder requirement.
- [nix-store-model-and-vmtest-backends.md](nix-store-model-and-vmtest-backends.md): the store model behind the container versus full virtual machine split.
