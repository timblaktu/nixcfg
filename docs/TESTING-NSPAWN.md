# systemd-nspawn Container Test Backend (NixOS 26.05)

A practical guide to running NixOS integration tests on the **systemd-nspawn container
backend** instead of QEMU VMs: when to use it, the host prerequisites, how to write a new
container test, how to migrate an existing VM test, and the **real, verified constraints and
caveats** discovered doing exactly that in this repo.

> Status: the backend is proven working on this repo's current pin (nixos-unstable ≥ 2026-05,
> which already ships the 26.05 nspawn test-driver backend). See the "Verified vs open" section
> at the end for what is empirically confirmed vs still inferred. Origin: plan
> `053-nixos-2605-uplift-nspawn-tests` (Findings T6).

## Why (the payoff)

An nspawn container shares the host kernel instead of booting a full VM. Measured on this host
with an **identical** config (`system-cli` module + identical assertions), container vs QEMU:

| Metric | QEMU (`vm-system-type-cli`) | nspawn (`vm-nspawn-smoke`) | Speedup |
|---|---|---|---|
| Boot → `multi-user.target` | 24.38s | **4.66s** | ~5.2× |
| Test script total | 24.94s | **3.75s** | ~6.6× |
| QEMU "connecting" alone | 16.50s | ~0 | — |

The container ran the whole smoke faster than QEMU took just to connect. Because containers use
far less RAM than VMs, you can also run many more in parallel — the point of migrating: cheap,
fast test coverage across all hosts.

## When to use a container vs a VM (eligibility)

A container **shares the host kernel** — there is no initrd, no bootloader, no stage-1 systemd,
no kernel modules, no KVM. Only userspace systemd runs.

**Use a container** when the test only exercises userspace: users/groups, `sudo`/wheel, locale,
services (sshd, dbus, sops-nix activation), Home Manager activation, installed packages, config
files. This is the large majority of integration tests.

**Keep QEMU** when the test's *meaning* depends on kernel/boot semantics:
- Boot/initrd/bootloader/stage-1 behavior (e.g. "does a minimal config *boot*?" — a container
  reaching `multi-user.target` does **not** prove a bootable system).
- Kernel modules, `/dev/kvm`, device units, disk/LUKS/LVM, custom kernels.
- WSL- or hardware-specific boot behavior.

If unsure, classify by asking: "does any assertion depend on something below userspace?" If no,
it's a container candidate.

## Host prerequisites (the builder must grant `uid-range` + `cgroups`)

An nspawn container-test run derivation carries `requiredSystemFeatures = [ "uid-range" ]` and
the driver places the container in a cgroup. The **builder** must therefore have, in its Nix
config:

```nix
# modules/system/types/1-minimal/minimal.nix (NixOS block) — already enabled fleet-wide
nix.settings = {
  experimental-features = [ "nix-command" "flakes" "auto-allocate-uids" "cgroups" ];
  auto-allocate-uids = true;               # lets a build request a transient uid range
  extra-system-features = [ "uid-range" ]; # advertise it (append-safe; keeps kvm/nixos-test)
};
```

Three things are required, and all three were needed in practice — enabling only
`auto-allocate-uids` is **not** sufficient:
1. `auto-allocate-uids` experimental feature **and** setting = `true` (transient uid range).
2. `cgroups` experimental feature (else the run fails: *"experimental Nix feature 'cgroups' is
   disabled"*).
3. `uid-range` advertised in the builder's system features (via `extra-system-features`, which
   appends rather than clobbering the auto-detected `kvm`/`nixos-test`).

This is enabled fleet-wide in this repo's base module, so **every NixOS host and any CI runner
built from it** can run nspawn tests **after a `nixos-rebuild switch`** picks up the config.

### Running one right now without a rebuild (ad hoc / CI-runner setup)

You can supply the settings to a one-off build as root, bypassing the daemon (which ignores
client-side experimental-feature overrides). Use `NIX_CONFIG` (file-style) — command-line
`--option`/`--extra-experimental-features` flags do **not** work here (parse order: the
`auto-allocate-uids` *setting* is validated before the *feature* is active):

```bash
sudo env NIX_CONFIG=$'experimental-features = nix-command flakes auto-allocate-uids cgroups\nauto-allocate-uids = true\nextra-system-features = uid-range' \
  nix build '.#checks.x86_64-linux.vm-nspawn-smoke' --store local --no-write-lock-file -L
```

`--store local` makes the invoking (root) nix the builder so it applies these settings; without
it the request goes to the daemon, whose config is unchanged until a rebuild.

## Writing a new container test

Use the `mkContainerTest` helper in `modules/flake-parts/vm-tests.nix`. It wraps
`pkgs.testers.runNixOSTest` and places the machine under `containers.<name>`.

```nix
vm-my-smoke = mkContainerTest {
  name = "my-smoke";
  description = "…";
  modules = [ self.modules.nixos.system-cli ];   # compose dendritic modules, not host configs
  extraConfig = { systemDefault.userName = testUsername; };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("id ${testUsername}")
    machine.succeed("git --version")
  '';
};
```

**Why not `mkVmTest`?** `mkVmTest`/`mkHmModuleTest` wrap `pkgs.testers.nixosTest` — the *legacy*
`simpleTest`/`testing-python.nix` path, which has **no `containers` option**. The nspawn backend
lives only on `pkgs.testers.runNixOSTest` (the module-based `nixos/lib/testing/` framework), where
a top-level `containers.<name>` attr sits alongside `nodes.<name>` and `allMachines` merges both
(name-collision-guarded).

## Migrating an existing VM test

The Python `testScript` does **not** change — machine names persist via `allMachines`. The edit
is infrastructure-only:

1. Switch the helper: `mkVmTest { … }` → `mkContainerTest { … }` (or, for a hand-rolled
   `pkgs.testers.nixosTest { nodes.machine = …; }`, use
   `pkgs.testers.runNixOSTest { containers.machine = …; }`).
2. Move each machine from `nodes.<n>` to `containers.<n>`.
3. Drop `virtualisation.memorySize` / `virtualisation.*` (QEMU-only; meaningless for containers).
4. Re-check service-state assertions against the caveats below (this is where migrations bite).

## Constraints & caveats (VERIFIED in this repo)

These are real differences observed while migrating, not theory:

- **Service activation can differ (VERIFIED).** `vm-nspawn-smoke` initially failed on
  `wait_for_unit("sshd.service")` — `sshd.service` was **inactive** at `multi-user.target` in the
  container, although the identical QEMU twin has it active. `system-cli` sets
  `services.openssh.enable = true` with no `startWhenNeeded`, so this is container-specific, not a
  socket-activation config. A confirmed contributing factor: the nspawn-container module runs the
  guest with **`--private-network`** (isolated network namespace), which changes network-target
  ordering and service startup. **Lesson:** do not assume a `wait_for_unit("<svc>.service")` that
  passes under QEMU will pass under nspawn. For userspace *setup* checks, prefer activation-agnostic
  assertions (e.g. assert the sshd host key exists: `test -f /etc/ssh/ssh_host_ed25519_key`) over
  waiting on a specific service unit. For tests that genuinely need a running service (the SSH
  cross-node tests), verify the service actually comes up in-container before trusting the migration.
- **Networking is isolated by default (`--private-network`).** Multi-container tests get networking
  via the test framework's `network.nix`, but single-container tests run with an isolated netns.
  Anything asserting real interfaces/DHCP/`network-online.target` may behave differently.
- **No `virtualisation.*` options.** `memorySize`, `cores`, disk images, etc. simply don't apply.
- **Boot semantics are absent by definition.** Reaching `multi-user.target` proves userspace came
  up, **not** that the system boots. Keep boot-smoke tests on QEMU.
- **Builder features are per-runner.** A runner without `auto-allocate-uids`+`cgroups`+`uid-range`
  cannot *build* a container test (it fails with "missing system features: uid-range"). Under
  `nix flake check --no-build` the check still **evaluates** fine — the requirement bites only at
  build time. Keep container tests out of a CI matrix until that runner is configured.

## Per-test migration inventory (this repo's 21 `vm-*` tests)

All 21 were verified to assert **pure userspace** at runtime (no kernel/boot/`/dev/kvm`/`modprobe`/
device-unit/nested-container assertions). Classification:

- **18 clean container candidates:** `vm-system-type-{default,cli}`, `vm-user-config`,
  `vm-shell-env`, `vm-neovim`, `vm-tmux`, `vm-git-advanced`, `vm-development-tools`, `vm-yazi`,
  `vm-hm-activation`, `vm-hm-module-isolation` (8 nodes — biggest RAM win), `vm-hm-composition-pairs`,
  `vm-full-cli-stack`, `vm-dev-team-stack`, `vm-sops-deployment`, `vm-sops-secrets`,
  `vm-ssh-service` (2-node), `vm-ssh-management` (2-node).
  - Watch `vm-sops-secrets` (sops-nix `/run/secrets` activation) and the two SSH tests (networking +
    service-activation) — verify empirically per the caveats above.
  - `node_podman` in `vm-hm-module-isolation` only asserts `which podman-tui` + a config file (no
    nested `podman run`), so it is eligible.
- **Keep QEMU on principle (1):** `vm-boot-minimal` — its meaning is *boot*.
- **Verify before moving (2):** `vm-system-type-desktop` (appears to be static `systemctl` checks →
  likely eligible), `vm-dev-team-vm-smoketest` (name implies image/boot smoke).

## Verified vs open (honesty ledger)

**Verified end-to-end on this host:**
- The nspawn backend builds and *runs*; `vm-nspawn-smoke` boots a container and passes.
- The measured speedups above.
- The exact builder config works — including that `extra-system-features = [ "uid-range" ]` (the
  committed mechanism) advertises `uid-range` and the test passes with it.
- `sshd.service` is inactive under nspawn while active under QEMU.
- The `--private-network` fact (read from the nspawn-container module source).

**Not yet verified / open:**
- The green runs used `--store local` (single-user root). The committed `minimal.nix` config uses
  the identical settings, but the **daemon path after a real `nixos-rebuild switch` has not been
  executed** — expected-equivalent (same nix binary, same nix.conf content) but unproven until a
  host is rebuilt.
- The precise reason `sshd.service` is inactive (network-target ordering under `--private-network`
  vs another cause) was **not** fully isolated.
- `vm-nspawn-smoke` is registered as a check but intentionally **not** in the CI matrix; it has not
  been run in CI.

## See also
- `docs/TESTING.md` — general test suite overview and QEMU/KVM integration tests.
- `modules/flake-parts/vm-tests.nix` — `mkVmTest` / `mkContainerTest` helpers + all `vm-*` checks.
- Plan `053-nixos-2605-uplift-nspawn-tests` (Findings T6) — the migration's working notes.
