# Nix's store/db/daemon/profiles, and how NixOS VMTest backends interop with them

A conceptual reference explaining **what "nix" actually is** (it's four separate things), **how nix
operates inside containers**, and **why the two NixOS integration-test backends (QEMU vs
systemd-nspawn) behave so differently** when a test does a nix operation at runtime — most notably
**Home Manager activation.**

> Origin: written up from the plan 054 P5b "nspawn-fidelity spike" investigation (2026-08-21). The
> practical, task-facing version of the nspawn conclusions lives in `docs/TESTING-NSPAWN.md`
> ("Constraints & caveats"); this document is the deeper *why*. The upstream-unblock research is
> tracked as task **R1** in `.claude/user-plans/054-vmtest-capabilities-coverage.md`.

---

## 1. "Nix" is four separate things

When people say "nix," they blur together four distinct components. Keeping them apart is the key to
everything below.

1. **The store** — `/nix/store`, the big directory of built artifacts. Content-addressed and
   **immutable**: a path either exists with exactly its built content, or it doesn't.
2. **The database** — `/nix/var/nix/db` (a SQLite file). It records **which store paths are "valid"**
   (registered as known-good) and the reference graph between them (what depends on what).
3. **The daemon** — `nix-daemon`, a privileged process that mediates all **writes** to the store/db on
   behalf of unprivileged users, over a socket at `/nix/var/nix/daemon-socket/socket`.
4. **Profiles** — `/nix/var/nix/profiles/...`, chains of symlinks that track **generations** of an
   installed environment (system, per-user, Home Manager). Switching generations = repointing a symlink.

### The single most important insight

**Nix trusts its *database*, not the filesystem.** A path can be physically present in `/nix/store`,
full of the right files, and nix will still treat it as **"invalid" / not there** if the *database*
doesn't have it registered. "The files exist on disk" and "nix knows this path is valid" are two
different facts, and nix acts only on the second.

This is why you can't make nix work in a container just by giving it the store *files* — you also have
to give it a *database* that agrees those files are valid, and (for writes) a way to *modify* the
store/db.

---

## 2. Reads vs writes: what actually needs what

Most things a booted system does with the store are **pure reads**: to run a program, the kernel maps
the already-built binary out of `/nix/store`. That needs the store *files* readable — nothing else. No
db, no daemon, no writes.

A **runtime nix *operation*** is different. `nix build`, `nix-env`, `nix profile`, `nix-store --set`,
etc. touch the **db** and often **write** to the store or profiles. These need:

- a store nix can **open** (and, as we'll see, nix insists on being able to *manage* it),
- a **db** that knows the relevant paths are valid,
- and usually a **daemon** (or direct write access) to perform the operation.

**Home Manager activation is one of the rare runtime nix operations.** `home-manager-<user>.service`
runs `nix-env -p …/profiles/per-user/<user>/home-manager --set <generation>` to register the new
generation as the current one. That is a genuine runtime nix write — which is exactly what trips over
the container limitations below. Ordinary services never do this; they just execute pre-built binaries
(pure reads), which is why "check git is installed" works in a container but "activate Home Manager"
does not.

---

## 3. How nix runs inside a container (the two working models)

Every *working* "nix in a container" is one of two internally-consistent setups:

- **Model A — self-contained.** The container has its **own** complete, **writable**, consistent store
  + db + daemon (e.g. a Docker image built with nix, or a full QEMU VM with its own disk). All four
  components agree with each other and nix can do anything.
- **Model B — borrow the host.** The container **does not run its own daemon**; it sets
  `NIX_REMOTE=daemon` and talks to the **host's** nix-daemon (which has the full db and write access to
  the host store). This is literally how NixOS's imperative/declarative `nixos-containers` work — see
  `nixos/modules/virtualisation/container-config.nix`, which under `boot.isContainer` sets
  `environment.variables.NIX_REMOTE = "daemon"` with the comment *"Use the host's nix-daemon."*

Both are coherent: store, db, and daemon all match. Trouble comes from a setup that is *neither*.

---

## 4. The two NixOS VMTest backends

NixOS integration tests spin up one or more machines and run a Python `testScript` against them. There
are two backends for "spin up a machine":

| | **QEMU** (`pkgs.testers.nixosTest` / `nodes.<name>`) | **systemd-nspawn** (`pkgs.testers.runNixOSTest` + `containers.<name>`) |
|---|---|---|
| Isolation | Full virtual machine — own kernel, initrd, bootloader, virtual disk | Container — **shares the host kernel**, userspace-only |
| Speed | Slow (~25 s just to connect) | Fast (~4 s) — ~5–7× faster, far less RAM |
| Store | Read-only host store **+ a writable overlay** | Host store bind-mounted **read-only**, no overlay |
| Nix operations at runtime | **Work** | **Don't work** (this document's subject) |

### 4a. How QEMU tests make nix fully usable — `virtualisation.writableStore`

A QEMU test VM *also* starts from the host's read-only store, yet `nix build` works inside it. Why?
Because the test base turns on **`virtualisation.writableStore`** (see
`nixos/modules/virtualisation/qemu-vm.nix`), which does two things:

1. **Writable overlay** — it stacks a writable tmpfs *on top of* the read-only host store, so the store
   *looks* writable to nix even though the host copy underneath is read-only.
2. **Database registration** — a `register-nix-paths` systemd oneshot runs
   `nix-store --load-db < …/nix-path-registration` **early in boot** (the same file notes: *"nix-store
   --load-db writes to the SQLite DB directly, so it does not need the nix-daemon"*), so the VM's db
   actually knows the pre-built closure paths are valid. The registration is passed in via the kernel
   command line to avoid a `toplevel ↔ registration` build cycle.

With a writable store **and** a registered db, nix inside a QEMU test is a normal, self-consistent
**Model A** nix. Everything works.

### 4b. What the nspawn container backend sets up

The container base module `nixos/modules/virtualisation/nspawn-container/default.nix` is deliberately
minimal (it's new — NixOS 26.05). Its `systemd-nspawn` invocation includes:

- `--bind-ro=/nix/store:/nix/store` — the store is mounted **read-only**. There is **no writable
  overlay** and (`virtualisation.*` being QEMU-only) no `writableStore`.
- `--private-users=no` — no user-namespace uid remapping (container "root" == the build's uid).
- `--private-network`, `--keep-unit`, `--register=no`, `--notify-ready=yes`.
- It sets `boot.isNspawnContainer = true` — **not** `boot.isContainer = true`, so the
  `container-config.nix` "use the host's nix-daemon" wiring (Model B) does **not** apply.

And `/nix/var` (which holds the db and profiles) is part of the container's own fresh root, **not**
shared from the host — so the container has its **own** db, not the host's, and nothing registers the
closure into it.

**The result is a Frankenstein that is neither Model A nor Model B:** a **read-only** store borrowed
from the host, plus the container's **own** (unregistered) db, plus its **own** daemon. The three
disagree. That's fine for tests that only *read* the store (the large majority). It breaks the moment a
test does a runtime nix *operation*.

---

## 5. The failure: Home Manager activation under nspawn

Running our `vm-hm-activation` test on the nspawn backend, `home-manager-<user>.service` reaches state
**failed**. The directly-observed cause:

```
nix-daemon: unexpected Nix daemon error:
    error: changing ownership of path "/nix/store": Operation not permitted
hm-activate-<user>: error: cannot open connection to remote store 'daemon':
    error: read of 32768 bytes: Connection reset by peer
```

Mechanism: when nix opens a store for a write/registration operation, its `LocalStore` layer tries to
**ensure the store directory has the expected ownership/permissions** — i.e. it `chown`s `/nix/store`.
On a **read-only** bind mount that `chown` fails with `EPERM`, and the operation aborts. Home Manager's
`nix-env --set` round-trips through the daemon, the daemon dies on that chown, and HM fails.

The identical config **passes under QEMU**, because QEMU's `writableStore` gives it a writable store, so
the chown succeeds.

---

## 6. Three probes — and why each is blocked by the Nix build sandbox

The obvious question: *if it's configurable, can't we just reproduce what QEMU does?* We tried three
legitimate levers. **All three failed, each revealing a deeper wall.** The crucial context: a NixOS
test is itself **built as a nix derivation** (`nix build .#checks…`), so the whole thing runs **inside
the Nix build sandbox** — an isolation boundary that, for reproducibility, cuts the build off from the
host's `/nix/var`, the daemon socket, the network, and most mount operations.

| # | Lever | Idea | Result |
|---|---|---|---|
| 1 | **Borrow the host db/daemon** (Model B) | `nix.enable = false` + `--bind-ro=/nix/var/nix/db` | Container won't start: `Failed to clone /nix/var/nix/db: No such file or directory` — **the sandbox hides the host db and daemon socket.** |
| 2 | **Register the db daemon-free** (QEMU's trick) | a `register-nix-paths` oneshot running `nix-store --load-db` from a `closureInfo` registration | The load-db step **itself** dies on `changing ownership of path "/nix/store"` — **proving the wall is nix's `LocalStore`, not the daemon**: *every* store op chowns the store on open. |
| 3 | **Make the store writable** (an overlay) | `systemd-nspawn --overlay=/nix/store:…:/nix/store` — the direct analog of `writableStore` | systemd-nspawn fails at spawn — **the sandbox blocks the overlayfs mount.** |

Notably, in probe 2 we never even reached the point of testing the "empty db" hypothesis — the
`LocalStore` chown wall preempts it in every configuration. The read-only store is the first and
hardest barrier.

### Why QEMU sidesteps all of this

QEMU's `writableStore` machinery (a) is **QEMU-only** — `virtualisation.*` options don't exist for
containers — and (b) does its overlay mount and db load **inside the guest kernel**, *not* in the build
sandbox. The guest is a real, separate kernel with its own block devices and mount namespace where an
overlay is legal. The nspawn container has neither an equivalent option nor a place to legally perform
these mounts, because it shares the host kernel and lives inside the sandbox.

---

## 7. Conclusion: the missing capability is "writableStore for the nspawn backend"

This is **not** a hardcoded-broken framework, and **not** a misconfiguration on our part. It is a
genuine **capability gap**: the nspawn *test* backend has no equivalent of QEMU's
`virtualisation.writableStore`. Until it grows one, any test that performs a runtime nix operation
(Home Manager activation being the practical case) must run on QEMU.

A fix would need to give the container a **writable + registered** store from *inside* the sandboxed,
shared-kernel environment — e.g. one of:

- an **overlay mounted from within the container's own mount namespace** (after `systemd-nspawn` has
  entered it and gained the needed capabilities), rather than a host-side `--overlay` the sandbox
  rejects;
- a **writable tmpfs store seeded** with (or bind-union'd over) the read-only store, plus an early
  `register-nix-paths`-style db load driven from a `closureInfo` shipped in the closure (no host access
  needed);
- teaching nix's `LocalStore` to **skip the ownership fixup** when the store is a read-only bind mount
  (so read-only-store + writable `/nix/var` profiles could suffice for `nix-env --set`, which only
  writes profiles, not the store).

Which of these is viable — and whether any already exists upstream — is exactly what task **R1**
investigates.

---

## 8. Practical guidance (which tests can move to nspawn)

- **Safe on nspawn:** tests that only *read* the store — pure system/userspace checks with **no Home
  Manager activation** (e.g. `vm-system-type-default`, `vm-user-config`), plus sops-nix activation
  (a plain activation-script + tmpfiles path, no nix op) and multi-node topologies (with hostname-valid
  node names — no underscores).
- **Must stay on QEMU:** anything that waits on `home-manager-<user>.service`, anything doing a runtime
  nix operation, and the usual boot/graphics/real-network/image gates.

See `docs/TESTING-NSPAWN.md` for the full per-test breakdown and the other verified nspawn caveats
(socket-activated sshd, hostname-valid machine names, networking fidelity).

---

## 9. Provenance

- Investigated in plan `054` P5b on host `pa161878-nixos` (KVM + `systemd-nspawn`), 2026-08-21.
- nspawn checks were built via the ad-hoc root path (the daemon lacks `uid-range` until a
  `nixos-rebuild switch` picks up the 053-T6 base-module change):
  ```
  sudo env NIX_CONFIG=$'experimental-features = nix-command flakes auto-allocate-uids cgroups\nauto-allocate-uids = true\nextra-system-features = uid-range' \
    nix build '.#checks.x86_64-linux.<name>' --store local --no-write-lock-file -L
  ```
- Upstream sources referenced: `nixos/modules/virtualisation/qemu-vm.nix` (writableStore +
  register-nix-paths), `nixos/modules/virtualisation/nspawn-container/default.nix` (the container
  invocation), `nixos/modules/virtualisation/container-config.nix` (`NIX_REMOTE=daemon` for
  `boot.isContainer`), `nixos/lib/testing/` (the test driver).
