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

> **⚠ SUPERSEDED by the R2 spike (§8f probe 3b, 2026-08-21).** This section's thesis — "HM activation needs
> a writable store, so it must stay on QEMU until an upstream `writableStore`-for-nspawn lands" — is
> **wrong**. HM activation runs on nspawn **today** with a RO store and a test-level config (empty
> `build-users-group` to skip the chown + a daemon-free `nix-store --load-db` of the HM closure); no
> writable store and no upstream change are required. The text below is kept for the P5b reasoning trail;
> read §8f for the corrected conclusion.

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

## 8. Prior art & upstream path (R1)

> Desk research completed 2026-08-21 (plan 054 task R1). Method: LOCAL-FIRST reading of the nix
> (`~/src/nix`, HEAD `2f28dd9`, 2026-04-24) and nixpkgs (`~/src/nixpkgs-upstream`, `58702cd2`,
> 2026-02-01) clones, plus web/GitHub for the PRs, issues, and Discourse/blog threads cited below.
> Sources are linked so the searches are reproducible; a short "reproducible negatives" list records
> queries that found nothing so a re-run doesn't re-chase them.

### 8a. The nspawn test backend's history (who built it, what they said about the store)

The container test backend landed upstream in **two merged nixpkgs PRs**, with a third for docs. There
is **no RFC**; design discussion lived in-thread.

| Item | What | Author / status | Link |
|---|---|---|---|
| Origin issue **#350899** | "Use containers for NixOS tests?" — the feature request. Scope = the backend; does **not** discuss store writability, `nix build`, or HM. | Atemu — **closed** | <https://github.com/NixOS/nixpkgs/issues/350899> |
| PR **#470248** | `nixos/nspawn-container: init a new nspawn-container profile` (carried init commit `4bd5482aa60b`). Body: *"lays the groundwork to … rework the nixos test infrastructure to allow for containers."* Credits the **Clan.lol** team as first implementors. | Jeremy Fleischman (`jfly`) — **merged** 2026-01-20 (`392f87a1`) | <https://github.com/NixOS/nixpkgs/pull/470248> |
| PR **#478109** | `nixos/test-driver: add support for nspawn containers` — the actual driver wiring (`containers.<name>`, `BaseMachine`/`QemuMachine`/`NspawnMachine`, shared VLANs, `run-nspawn` driving `nsenter`). Head branch = the `applicative-systems:nixos-test-containers` branch our reference doc's provenance pointed at (now merged wholesale; the `compare/…` link 404s post-merge). | Kierán Meinhardt (`kmein`), HM-integration heavy-lifting by `jfly` — **merged** 2026-03-18 | <https://github.com/NixOS/nixpkgs/pull/478109> |
| PR **#479968** | `nixos/doc: document systemd-nspawn test containers`. Notes bind paths *"have to be accessible from within the Nix sandbox … use `sandbox-paths` and/or `programs.nix-required-mounts`."* | `kmein` — **merged** | <https://github.com/NixOS/nixpkgs/pull/479968> |

**Stated limitations (quoted).** No PR or comment says "no writable store" or "Home Manager won't
activate" outright — the read-only store is presented only as a *design property* (`nspawn-container/
default.nix` header: *"By default, the Nix store is shared read-only with the host, which makes
(re)building very efficient"*). The write-path was **consciously not built**; the only trace of
considering it is a roberth↔kmein exchange on #478109:

> *"We would have to overlay something like a minimum root filesystem onto the host file system before
> executing the container (via another layer of namespacing?). I don't know if this would be worth the
> effort?"* — kmein, <https://github.com/NixOS/nixpkgs/pull/478109#issuecomment-3861345545>

The load-bearing documented limitation is that **specialisations are hard-disallowed** (an assertion in
the module + the manual): *"Switching to a specialisation requires the creation of SUID/SGID wrappers,
which is disallowed in `systemd-nspawn` within the Nix sandbox."* The setuid ban's root cause, per jfly,
*"ultimately comes from the nix sandbox, not from systemd-nspawn"*
(<https://github.com/NixOS/nixpkgs/pull/478109#discussion_r2867708539>). **There is no `writableStore`
follow-up issue or TODO anywhere** — confirmed by reading `nixos/lib/testing/*.nix` (grep for
`writabl`/`overlay`/`bind-ro` returns nothing) and the `run-nspawn` launcher (its only self-added bind is
`--bind={shared_dir}:/tmp/shared`; everything else, including `--bind-ro=/nix/store`, is passed straight
through; commands enter via `nsenter`, so **no post-spawn mount hook exists today**).

Secondary write-ups (useful design context, not upstream code): Nixcademy
<https://nixcademy.com/posts/faster-cheaper-nixos-integration-tests-with-containers/>; Applicative
Systems test-driver manual container section
<https://applicative.systems/nixos-test-driver-manual/features/container/>.

### 8b. Prior art for a writable/registered store in containers

- **No upstream `writableStore` for the nspawn backend exists** (§8a) — a contribution would not be
  enabling a dormant switch.
- **QEMU's `writableStore` is the battle-tested blueprint**, and it is entirely in-guest, daemon-free
  (verified in `~/src/nixpkgs-upstream/nixos/modules/virtualisation/qemu-vm.nix`): `regInfo =
  closureInfo { rootPaths = additionalPaths; }` (line 330) is passed via the kernel cmdline
  `regInfo=…/registration` (line 1325); an early boot step runs `nix-store --load-db < $regInfo`
  (lines 1240-1241 — the same file notes load-db writes the SQLite DB directly, no daemon needed); and
  the store is made writable by an **in-guest overlay** declared as a `fileSystems."/nix/store".overlay`
  entry — `lowerdir=/nix/.ro-store`, `upperdir=/nix/.rw-store/upper`, `workdir=/nix/.rw-store/work`
  (lines 1445-1450), the upper on a tmpfs (`writableStoreUseTmpfs`, line 1465). The reusable registration
  primitive is `pkgs.build-support/closure-info.nix` → `$out/registration`.
- **Nix's experimental `local-overlay-store`** is the only *first-class* "writable upper over read-only
  lower" store primitive (confirmed in `~/src/nix`: `LocalOverlayStore : virtual LocalStore`,
  `local-overlay-store.hh:113`; it is a `LocalStore` subclass, **not** a daemon store, so it needs no
  nix-daemon; gated behind `experimental-features = local-overlay-store`, `.hh:79`). **Nix does not
  perform the overlay mount itself** — you mount the OverlayFS and Nix only *verifies* it via
  `/proc/self/mounts` (skippable with `check-mount=false`); the lower store must be immutable and set
  `read-only=true`. Docs: <https://nix.dev/manual/nix/2.31/store/types/experimental-local-overlay-store.html>.
  **Caveat — it is rough in containers:** Nix issue **#11840** (open) reports the overlay-store
  misbehaving in a k8s pod (*"the lower-layer database unexpectedly updated despite being in a read-only
  conceptual layer"*, spurious substituter downloads) — <https://github.com/NixOS/nix/issues/11840>.
- **Clan.lol is prior art for a DRIVER-SIDE writable store — NOT for an in-container writable
  `/nix/store`.** (Primary-source correction, R2 probe 1, 2026-08-21 — the R1 write-up above took the
  "nix writes work inside nspawn" claim from the Nixcademy/Clan blog, unverified; reading `clan-core`
  refutes the *in-container* reading.) Verified against the local `~/src/clan-core` clone:
  - Their nspawn containers mount `/nix/store` **read-only**, exactly like upstream — there is **no
    in-container overlay** and no in-container store write.
  - The writable store lives in the **test driver's own sandbox** (host-side Python, run in the
    `testScript` *before* any container starts): `setup_nix_in_nix()` builds a *separate* store under
    `$temp_dir/store` by **bind-mounting** individual paths as root (or `cp --reflink` when non-root),
    then registers them daemon-free with `nix-store --load-db --store "$CLAN_TEST_STORE"` from a
    `closureInfo` — `pkgs/testing/nixos_test_lib/nix_setup.py:177-226`,
    `pkgs/testing/flake-module.nix:22-24`.
  - The runtime nix operations they run (e.g. `clan machines list --flake …`, offline `nixos-rebuild`)
    execute in the **driver's Python via `subprocess.run`** against that driver-side store —
    `checks/service-dummy-test-from-flake/default.nix:34,52-57` — **not** via `machine.succeed()` inside
    the nspawn container. There is no evidence anywhere in the tree of HM activation / `nix-env` /
    `nixos-rebuild` running *inside* a clan nspawn container.
  - They use the **upstream** `containers.<name>` backend (`nixosLib.runTest`,
    `lib/flake-parts/clan-nixos-test.nix:29`), but the store-writability layer is a **home-grown,
    driver-coupled** Python package (`legacyPackages.nixosTestLib`), not a portable in-container facility.
  - **Net:** Clan.lol proves the *build sandbox* permits a writable, `load-db`-registered store **in the
    driver's own namespace** — useful blueprint for the daemon-free `closureInfo`→`load-db` half — but it
    does **not** demonstrate the in-container writable `/nix/store` that HM activation under nspawn needs.
    Blog "Debugging Offline Nix Builds" <https://clan.lol/blog/debugging-offline-nix-builds/>; `clanTest`
    lib in `clan-core` <https://git.clan.lol/clan/clan-core> (GitHub mirror
    <https://github.com/clan-lol/clan-core>).
- **HM-in-container failure reports** (confirm a writable+registered store is a genuine prerequisite, not
  optional): home-manager **#2325** (*"opening lock file '/nix/var/nix/profiles/per-user/…/home-manager.lock':
  No such file or directory"*) <https://github.com/nix-community/home-manager/issues/2325>; **#3752**
  (HM assumes profiles/gcroots under `/nix/…`, not store-location-agnostic)
  <https://github.com/nix-community/home-manager/issues/3752>.

**Reproducible negatives:** no origin PR for `virtualisation.writableStore` itself surfaced (only current
source); no issue *requesting* generalizing `writableStore` beyond QEMU; no Discourse/GitHub thread shows
HM activation succeeding inside an nspawn *test* with a writable store; GitHub code-search API needs auth
(substituted raw-file grep).

### 8c. The `LocalStore` chown question — CONFIRMED (source + skip flags)

The failing `changing ownership of path "/nix/store"` in the P5b spike comes from nix's `LocalStore`
constructor doing a store-directory **ownership fixup on open**. Exact source (in `~/src/nix`):

- **Call site:** `src/libstore/local-store.cc:173` — `chown(config->realStoreDir.get(), 0, gr->gr_gid)`
  inside the "set permissions for a multi-user install" block.
- **The throw:** that is the throwing wrapper `nix::chown` at `src/libutil/unix/file-system.cc:294-298`
  (`throw SysError("changing ownership of %s", …)`) — on a **read-only bind mount** the `::chown(2)`
  returns `EPERM` and it throws, aborting the store open. (The spike's older nix phrased it *"…of path
  %1%"*; same site.)
- **Guard (three conditions, all must hold to reach the chown):**
  `if (isRootUser() && localSettings.buildUsersGroup != "") { … else if (!config->readOnly) { … chown … } }`.

**A skip flag EXISTS — in fact two levers, but each has a catch:**

1. **`read-only = true`** store setting (`src/libstore/include/nix/store/local-store.hh:106`) — skips the
   chown (via the `!config->readOnly` guard) **but also** opens the SQLite DB with SQLite's `immutable`
   flag and disables locking (it is explicitly *"for when the database is on a read-only filesystem"*).
   That makes it **query-only** — it would block the very DB writes HM needs (`nix-env --set` registers a
   new profile generation in the DB). So `read-only=true` alone does **not** unblock HM.
2. **Empty `build-users-group`** (`build-users-group = ""`) — skips the *entire* multi-user chown block
   via the `buildUsersGroup != ""` guard, **without** the DB-immutability side-effect. This is the cleaner
   lever for "skip the chown but keep the DB writable." (Running non-root would also skip it, but the
   nspawn spike needs root.)

**Net:** the chown is not a hardcoded wall — it is skippable. But skipping it only solves the *first*
barrier. `nix-env --set` still needs (a) a **writable DB/profiles** under `/nix/var` and (b) the store
op to not itself write into the read-only `/nix/store` dir. That is why the read-only-store route is
*partially* viable, not a clean win — see 8d(3).

### 8d. Feasibility of the three §7 fix directions

| # | Direction (from §7) | Verdict | Evidence |
|---|---|---|---|
| 1 | **Overlay mounted from *inside* the container's mount namespace** (post-spawn), not a host-side `--overlay` | **BLOCKED for the live store — and MOOT** (superseded by #3) | A process *inside* the nspawn container **can** `mount -t overlay` over a RO lower store in-sandbox: R2 probe 2 mounts `overlay` at a **side path** with rc=0, readable + writable (`spike-r2-overlay` builds+passes). **But applying it to the live `/nix/store` fails, even done right:** R2 probe 2b (`spike-r2-hm-overlay-live`) runs the overlay EARLY (`before sysinit.target`) with `--make-rprivate` propagation and STILL corrupts exec (`nsenter: failed to execute /bin/sh`, `wait_for_unit` rc=127) — so the earlier failure was **not** a propagation artifact; you cannot swap the in-use `/nix/store` from within the running container. QEMU only gets away with it via an initrd overlay before PID1 (`qemu-vm.nix:1445-1450`), which nspawn has no equivalent of. **Moot regardless:** direction #3 (below) makes HM activation work with **no overlay at all**, so this route is not worth pursuing. |
| 2 | **Writable tmpfs store seeded + early `register-nix-paths`/`load-db`** from a shipped `closureInfo` | **VIABLE — daemon-free `load-db` confirmed** (R2 probes 2+3) | The db-load half is proven daemon-free in-container: R2 probe 3 runs `nix-store --load-db` (rc=0) from a shipped `closureInfo/registration` with `NIX_REMOTE=` (direct `LocalStore`, no daemon). Pairs with either the writable store of #1 **or** the writable-`/nix/var`-only route of #3 — it is the registration component, reusable verbatim (`closureInfo` → `nix-store --load-db`, qemu-vm.nix:330, 1240-1241). |
| 3 | **Teach `LocalStore` to skip the ownership fixup on a RO bind mount** (→ RO store + writable `/nix/var`) | **VIABLE — CONFIRMED, and the simplest fix (new recommended primary)** (R2 probe 3) | Proven end-to-end: `spike-r2-roskip` builds+passes with `/nix/store` **read-only** (mount opts `ro,…`), `/nix/var` writable, and `nix.settings.build-users-group = ""` (the §8c chown-skip lever). Daemon-free (`NIX_REMOTE=`), `nix-store --load-db` (rc=0) **and** `nix-env -p …/profiles/r2-test --set <path>` (rc=0) both complete; the profile symlink resolves and the binary runs. So a profile write completes with a RO store + writable `/nix/var` — **no overlay, no store-writability needed** for the `nix-env --set` operation at HM's core. This is materially simpler than #1 (a single store setting + a writable `/nix/var` bind, no mount-namespace surgery) and needs **no nix patch** (the skip lever already exists). **Full HM activation now CONFIRMED end-to-end** (R2 probe 3b, `spike-r2-hm-roskip`, build+pass): with `build-users-group=""` + a `load-db` of the HM closure, `home-manager-<user>.service` reaches `active` status=0/SUCCESS on a read-only store — no overlay, no writable store, no upstream change. Not just the simplest route, the complete one for HM tests. |

### 8e. Recommendation (UPDATED post-R2 spike, 2026-08-21)

> The R1 desk research below originally recommended direction #1 (in-namespace overlay) as primary and
> framed the fix as an *upstream* contribution. The **R2 spike (§8f) overturns both**: direction #3
> (chown-skip + daemon-free `load-db`, RO store, writable `/nix/var`) not only works but drives **full HM
> activation** under nspawn — and it needs **no upstream change and no writable store**, only a test-level
> config. Direction #1's overlay is blocked for the live store (probe 2b) and moot (probe 3b).

**Primary (revised) — a LOCAL `mkContainerTest` change, no upstream needed.** To host HM (or any
`nix-env --set`) tests on nspawn, the container just needs: (a) `nix.settings.build-users-group = ""`
(skip the `LocalStore` chown, §8c), and (b) a `register-nix-paths` oneshot running `nix-store --load-db`
from a `closureInfo` of the relevant closure (the HM generation:
`config.home-manager.users.<user>.home.activationPackage`), ordered before `home-manager-<user>.service`,
with `/nix/store` left read-only and `/nix/var` writable. R2 probe 3b (`spike-r2-hm-roskip`) proves this
reaches `home-manager-<user>.service` = `active` status=0. This can be baked into a `mkContainerTest`
variant in `modules/flake-parts/vm-tests.nix` **today** — see the P5c reconsideration in plan 054.

**Optional upstream polish (nice-to-have, not required):** the same two levers could be offered as an
opt-in `writableStore`-analog on the nspawn backend (`nixos/modules/virtualisation/nspawn-container/
default.nix` + the `closureInfo` plumbing in `nixos/lib/testing/`) so every consumer gets it without
hand-rolling the oneshot. But since the local recipe already works, an upstream PR is convenience, not a
prerequisite. **Do not** pursue direction #1's overlay (blocked + moot) and **do not** patch nix.

Note the R1 suggestion to "read `clan-core` first because it likely already solves this" was **checked and
does not hold** (§8b correction): clan-core makes a writable store in the *driver* sandbox, not inside the
container, so it is not a drop-in for in-container HM activation — but that turned out not to matter, since
HM activation needs no in-container writable store at all (probe 3b).

**Exact files a fix would change** (upstream nixpkgs):
- `nixos/modules/virtualisation/nspawn-container/default.nix` — add an opt-in `writableStore` analog: for
  direction #3, set `nix.settings.build-users-group = ""` + a `register-nix-paths` oneshot running
  `nix-store --load-db` from a shipped `closureInfo`, ordered before `home-manager-<user>.service`.
- `nixos/lib/testing/{nodes,run}.nix` and the `run-nspawn` launcher / `NspawnMachine` — plumb the
  `closureInfo` registration into the container (the QEMU path passes it via kernel cmdline; nspawn needs
  an equivalent bind/arg).
- **Do *not* patch nix itself.** Direction #3's chown-skip already exists as store settings; nix's
  `local-overlay-store` is experimental and buggy in containers (#11840). A nix patch is not on the
  critical path.

**Status vs P5c:** the plan currently still lists the HM family as QEMU-only (from P5b, before probe 3b).
That assumption is now falsified — HM tests *can* run on nspawn via the local recipe above. Whether P5c
adopts it is a **design decision flagged for Tim** (plan 054 "R2 spike findings" → "P5c reconsideration"),
not something R2 changes unilaterally. The R2 conclusion: the capability gap is real but **closable
locally, today** (direction #3), with an upstream PR as optional convenience.

### 8f. R2 spike results (empirical — 2026-08-21, host `pa161878-nixos`)

The R2 spike turned the §8d verdicts from "on-paper" into evidence. Five throwaway nspawn checks
(`modules/flake-parts/vm-tests.nix`, after the P5b spikes), built via the §10 ad-hoc sudo-root path
(daemon still lacks `uid-range`). Full write-up in plan 054's "R2 spike findings".

> **Cleanup (2026-08-21):** after recording these results, the four superseded checks (`spike-r2-overlay`,
> `spike-r2-roskip`, `spike-r2-hm-overlay-live`, and probe 2b) were **pruned** from `vm-tests.nix`, keeping
> only **`spike-r2-hm-roskip`** (probe 3b) as the canonical, reproducible proof and the seed for the P5c
> HM-on-nspawn migration. The table below preserves all five probes' findings for the record.

| Probe | Direction | Check | Result |
|---|---|---|---|
| 1 | Clan.lol prior-art (primary source) | — (read `~/src/clan-core`) | **CORRECTS R1's claim** — clan-core's writable store is **driver-side**, not in-container (see §8b). |
| 2 | #1 in-namespace overlay (mechanism) | `spike-r2-overlay` | **MECHANISM CONFIRMED at a side path** (build+pass) — a process in the container can `mount -t overlay` over a RO lower store, readable + writable. |
| 2b | #1 overlay on the LIVE `/nix/store` + full HM | `spike-r2-hm-overlay-live` | **BLOCKED (recorded failure)** — even an EARLY (`before sysinit.target`), `--make-rprivate` overlay onto the live `/nix/store` breaks all exec (`nsenter: failed to execute /bin/sh`, `wait_for_unit` rc=127). The propagation-artifact hypothesis is **refuted**; you cannot swap the in-use `/nix/store` from within the running container. |
| 3 | #3 LocalStore RO-skip (core op) | `spike-r2-roskip` | **CONFIRMED VIABLE** — RO store + writable `/nix/var` + empty `build-users-group`: `load-db` (rc=0) and `nix-env --set` (rc=0) complete daemon-free; profile resolves+runs (build+pass). |
| 3b | #3 driven to FULL HM activation | `spike-r2-hm-roskip` | **★ CONFIRMED — full HM activation succeeds under nspawn with a RO store ★** `home-manager-<user>.service` reaches `active (exited)` status=0/SUCCESS; the generated git config exists with the expected content. NO overlay, NO writable store — just `build-users-group=""` + a daemon-free `load-db` of the HM closure (build+pass). |

**Bottom line — this OVERTURNS the §5-§7 thesis and P5b's "HM must stay QEMU":** Home Manager activation
does **not** actually need a *writable store* under nspawn. The P5b failure was the `LocalStore` chown on
the RO store abort (§5), and probe 3b shows both blockers clear with a **test-level config, no upstream
change and no writable store**: (a) `nix.settings.build-users-group = ""` skips the chown (§8c lever 2),
(b) a `register-nix-paths` oneshot runs `nix-store --load-db` from a `closureInfo` of the HM generation so
the db agrees the generation is valid, (c) `nix-env --set` (HM's core op) then writes only the profile
under the writable `/nix/var` — never the RO store. The "writableStore-for-nspawn" contribution R1
scoped is therefore **not required** for HM tests. Direction #1's overlay is both **blocked for the live
store** (probe 2b) **and now moot** (probe 3b makes it unnecessary).

**P5c implication (FLAGGED FOR DECISION, not auto-applied):** P5b/P4 put the entire HM-activation family
on QEMU on the belief that nspawn cannot host HM. Probe 3b refutes that belief. A `mkContainerTest`
variant that sets `build-users-group=""` + a generic `load-db` oneshot (closureInfo derived from
`config.home-manager.users.<user>.home.activationPackage`) could host the HM family on nspawn (~5-7×
faster). This is a P5c backend-map change and a design call for Tim — see plan 054 "R2 spike findings"
→ "P5c reconsideration". R2 does not change P5c unilaterally.

---

## 9. Practical guidance (which tests can move to nspawn)

- **Safe on nspawn:** tests that only *read* the store — pure system/userspace checks with **no Home
  Manager activation** (e.g. `vm-system-type-default`, `vm-user-config`), plus sops-nix activation
  (a plain activation-script + tmpfiles path, no nix op) and multi-node topologies (with hostname-valid
  node names — no underscores).
- **Must stay on QEMU:** anything that waits on `home-manager-<user>.service`, anything doing a runtime
  nix operation, and the usual boot/graphics/real-network/image gates.

See `docs/TESTING-NSPAWN.md` for the full per-test breakdown and the other verified nspawn caveats
(socket-activated sshd, hostname-valid machine names, networking fidelity).

---

## 10. Provenance

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
