# Rosetta 2, Apple Virtualization.framework, and Nix/NixOS Multi-Architecture Tooling

**Living reference document — revise in place.**
Status: v1 · Compiled 2026-08-31 · Sources: web research + one prior conversation thread

---

## 0. Session prompt (read this first)

> **You are joining an ongoing investigation.** This document is the seed context for a
> multi-session working effort about running `x86_64-linux` and `aarch64-linux` Nix builds
> and NixOS VM tests from Apple Silicon macOS hosts, alongside existing Linux hosts.
>
> **Treat this document as mutable state, not as fixed instructions.** As we work through
> the source repositories in this session, you are expected to:
>
> 1. **Verify claims against the actual code.** Sections marked `[UNVERIFIED]` are
>    reasoning, not fact. Confirm or refute them against `nixpkgs`, our flakes, our
>    NixOS test definitions, and our CI configuration.
> 2. **Correct the document.** When you find something wrong, edit the relevant section
>    directly and add a line to the Changelog (§11). Do not leave stale claims standing.
> 3. **Preserve provenance markers.** Every claim is tagged with where it came from
>    (`[STATED]`, `[RESEARCH]`, `[UNVERIFIED]`, `[DECISION]`). Keep these tags on anything
>    you add. If you cannot tell whether something was established or assumed, tag it
>    `[UNVERIFIED]` and say so.
> 4. **Do not escalate assumptions.** An option listed here is an option, not a decision.
>    Nothing in §7 has been adopted. Do not generate configuration, CI changes, or ADRs
>    that presuppose a choice that has not been explicitly made in-session.
> 5. **Close open questions explicitly.** §9 is the working queue. When one is resolved,
>    move the answer into the relevant body section and strike it from §9 with the result.
>
> **The core question this document exists to answer:** what portion of a
> multi-architecture embedded Linux workflow can actually move onto Apple Silicon
> developer machines, and where is the hard boundary that Rosetta does not cross?
>
> Start by asking which part of the repository to examine first, unless the operator has
> already said.

---

## 1. Scope, provenance, and how to read this

### Provenance tags

| Tag | Meaning |
|---|---|
| `[STATED]` | Asserted by the operator in conversation. |
| `[RESEARCH]` | From public documentation, upstream source, or vendor docs. Cited in §10. |
| `[UNVERIFIED]` | Reasoning or inference. Plausible, not confirmed. Must be tested. |
| `[DECISION]` | An explicit choice that has been made. **Currently: none.** |

### What the operator has stated

- `[STATED]` There is a shared repository that defines NixOS VM tests wrapping both
  `x86_64` and `aarch64` QEMU machines, intended to run on arbitrary hosts configured
  via Nix and NixOS configurations.
- `[STATED]` The context is supporting an embedded Linux development team across both
  architectures.
- `[STATED]` The trigger for this investigation was a podcast describing recent
  nix-darwin / NixOS work leveraging Rosetta 2 through a declarative virtualization path.

### What has *not* been established

- Whether Apple Silicon machines are in use on the team today, and in what numbers.
- Which macOS versions and which M-series generations are in play. **This matters
  materially** — see §6.3.
- Whether the VM tests are gating CI, developer-local, or both.
- Whether the target systems under test are NixOS-based or arbitrary embedded Linux
  images wrapped in a NixOS test harness.

These gaps constrain the recommendations in §7. Fill them in before treating §7 as
actionable.

---

## 2. Rosetta 2 is two different products

Conflating these is the single most common source of confusion in this area.

### 2.1 Rosetta translation environment (macOS applications)

`[RESEARCH]` Translates `x86_64` **Mach-O** binaries so Intel Mac applications run on
Apple Silicon. Primarily ahead-of-time: on first launch the binary is translated to
`arm64` and the result cached, with a JIT path for dynamically generated code.

Performance is unusually good for a translation layer — typically 70–85% of native — and
the reason is architectural, not just compiler quality. Apple Silicon implements a
**hardware total-store-ordering mode** that can be toggled per thread. Translated x86 code
executes with x86 memory-ordering semantics natively, rather than requiring barrier
instructions inserted around every memory access. This is the thing most x86-on-ARM
translation efforts cannot replicate.

`[RESEARCH]` **This is the product Apple is sunsetting.** macOS 27 is slated to be the
last release with full Rosetta 2 support for Intel *macOS applications*.

### 2.2 Rosetta for Linux VMs

`[RESEARCH]` A separate capability. Since macOS 13, `Virtualization.framework` can expose
the Rosetta runtime into an **aarch64 Linux guest** as a VirtioFS directory share. Inside
the guest, that runtime is registered as a `binfmt_misc` handler for `x86_64` ELF. From
then on, executing an amd64 binary transparently invokes Rosetta.

**Critical property: the guest kernel remains aarch64.** This is userspace ELF translation
only. It is not machine emulation and it is not a hypervisor mode.

`[RESEARCH]` **The two Rosetta use cases are officially distinct, but the Linux/VM path's
long-term future is NOT guaranteed (P8, verified 2026-09-04 against Apple's live pages).**
What is confirmed:
- Apple's deprecation notice is titled *"Upcoming changes to Rosetta support for **Intel-based
  macOS apps**"* and its scope is **exclusively macOS applications** — it makes **no mention**
  of Linux VMs, the Virtualization framework, or running x86_64 Linux binaries. Its timeline:
  **macOS 26.4+** — users may get a system notification when launching apps that rely on
  Rosetta; **macOS 27** — *"Final release to support Rosetta — Intel-only apps will no longer
  run"* as a general-purpose tool; **beyond macOS 27** — only *"Rosetta functionality for
  older, unmaintained gaming titles that rely on Intel-based frameworks will continue."*
- The Linux/VM path is a **separate, still-published feature** (Apple's *"Running Intel
  Binaries in Linux VMs with Rosetta"* doc + WWDC22 session): a `VZLinuxRosettaDirectoryShare`
  is mounted in an aarch64 guest and registered via `update-binfmts` so x86_64 Linux ELF is
  translated (TSO memory-model support in the guest kernel improves throughput). Apple DTS has
  drawn the distinction explicitly — x86_64 Linux binaries in a VM do **not** depend on macOS
  system frameworks, so it is *not* the same use case as the macOS Rosetta translation environment.

> **Implication for planning (CORRECTED — earlier draft overstated this):** the announced
> deprecation is scoped to **macOS apps** and does not name the Linux/VM path, so the two must
> not be conflated. **BUT** an earlier claim here — that Apple "is *not* sunsetting" the Linux
> path and that "starting in macOS 27 it is built into the OS with no separate install and the
> availability check always reports installed" — could **not** be verified and **overstates
> Apple's position.** Asked directly whether Linux-VM x86_64 translation survives past macOS 27,
> Apple DTS declined to commit either way: *"At this point in time we're not able to provide
> guidance beyond that text in the public documentation."* **Treat post-macOS-27 availability of
> Rosetta-for-Linux as an OPEN RISK, not a guarantee** — this is a real input to the §7 adoption
> decision and the PD gate (build-side reliance on Rosetta-translated x86_64 has an undetermined
> shelf life beyond macOS 27; the aarch64-native build path does not).

### 2.3 The hardware requirement is not "Rosetta needs a Max chip"

`[RESEARCH]` Rosetta behaves identically across all M-series silicon. A Max-tier part
buys throughput, not capability: more performance cores for build parallelism, higher
memory bandwidth (translated code leans on it), and enough unified memory to give a Linux
VM 32–64 GB while the host stays usable.

**However**, nested virtualization — which §6 shows is the gating feature for VM tests —
*is* generation-dependent. See §6.3.

---

## 3. Mechanism: how Rosetta reaches into a Linux guest

```
macOS host (aarch64-darwin)
└── Virtualization.framework VM
    ├── guest kernel: aarch64 Linux
    ├── VirtioFS share, mount tag "rosetta"  ← the Rosetta runtime
    │     └── mounted in guest, registered via binfmt_misc for x86_64 ELF magic
    └── userspace
          ├── aarch64 ELF  → executes natively
          └── x86_64 ELF   → kernel binfmt_misc → Rosetta → translated, executes
```

Constraints that fall directly out of this design:

- `[RESEARCH]` **aarch64 guest only.** There is no path to an x86_64 guest kernel.
- `[RESEARCH]` **Userspace ELF only.** No x86 kernel, no x86 kernel modules, no
  driver-level or boot-level work.
- `[RESEARCH]` **No 32-bit x86 (i386).**
- `[RESEARCH]` **QEMU cannot do this.** Rosetta is only exposable through Apple's
  `Virtualization.framework`. This is the reason the entire nixpkgs work described in §4
  required a new VMM rather than a QEMU flag.
- `[UNVERIFIED]` Vector extension coverage is partial. Code paths reaching for the newest
  AVX-512 instructions are expected to fault or require runtime dispatch fallback.
  Confirm the current AVX/AVX2 status against Apple's documentation for the macOS version
  in use before assuming a given toolchain works.
- `[UNVERIFIED]` JIT-heavy workloads degrade more than AOT workloads. Relevant later —
  see §6.5.

---

## 4. The NixOS / nix-darwin integration

### 4.1 `virtualisation.rosetta` (the long-standing piece)

`[RESEARCH]` `nixos/modules/virtualisation/rosetta.nix` in nixpkgs has existed for some
time. It mounts the VirtioFS share by tag and registers the binfmt handler using the
`x86_64-linux` binfmt magic. Defaults are tuned for UTM ("Apple Virtualization" engine
with "Enable Rosetta" ticked). Options include the mount tag and mount point.

This module was always usable — with UTM, Lima, or vfkit. What was missing was a
first-class, declarative, zero-config path.

`[RESEARCH]` **Verified (P1, live nixos-unstable):** the NixOS options index exposes
`virtualisation.rosetta.enable` (boolean; "requires the system to be a virtualised guest on an
Apple silicon host"; defaults tuned for UTM "Apple Virtualization" + "Enable Rosetta") and
`virtualisation.rosetta.mountTag` (the VirtioFS mount tag). ✓ Matches this section.

`[RESEARCH]` **P6a — binfmt registration confirmed in source (Q6 code half CLOSED).** In our pinned
nixpkgs (`ffb3c9b`) `nixos/modules/virtualisation/rosetta.nix` registers the handler as
`boot.binfmt.registrations.rosetta` with, on the `config = mkIf cfg.enable` branch:
- `rosetta.nix:77` **`fixBinary = true;`** — the binfmt_misc **`F` flag**. The kernel opens the
  interpreter (`${mountPoint}/rosetta`, line 72) at *registration* time and holds the fd, so exec
  invokes it via that pre-opened fd instead of re-resolving the path. This is precisely what makes
  x86_64 translation work **inside the Nix build sandbox** (a mount namespace where `/run/rosetta/rosetta`
  need not be resolvable by name).
- Supporting flags: `matchCredentials = true` (line 78, `C`), `preserveArgvZero = true` (line 79, `P`),
  and `wrapInterpreterInShell = false` (line 82 — call the runtime directly, no shell wrapper).
- The module is **purpose-built for sandboxed builds**, not just fixBinary: `nix.settings.extra-platforms
  = [ "x86_64-linux" ]` (line 65) advertises the extra build platform, and `extra-sandbox-paths =
  [ "/run/binfmt" cfg.mountPoint ]` (lines 66-69) bind-mounts the binfmt dir + the Rosetta share INTO the
  sandbox. The in-source comment (lines 74-75) cites the SAME Apple "Running Intel Binaries in Linux VMs
  with Rosetta" doc reconciled in §2.2/P8 as the source of the required flags.

So **Q6's code half is YES**: `virtualisation.rosetta` registers binfmt with `fixBinary` (+`C`/`P`, direct
interpreter) AND explicitly extends the sandbox for x86_64 builds. **Q6's Mac half stays open (P6b):** actually
demonstrating an `x86_64` `nix build` succeeding through the sandbox on Apple Silicon still needs a Mac.

### 4.2 The recent development (this is what the podcast was describing)

`[RESEARCH]` **`pkgs.darwin.linux-builder-vz`, backed by `pkgs.vzvm`.**

- Author: Jacek Galowicz (Nixcademy / Applicative Systems).
- nixpkgs PR **#544193**, **merged August 2026**.
- Announcement post: *"2.5x Faster x86_64 Linux Builds on macOS with Rosetta"*,
  published 2026-08-10.
- Reviewed by `arianvp`. Builds on Gabriella Gonzalez's original linux-builder and
  Enzime's nix-darwin module.
- `vzvm` source: `https://github.com/applicative-systems/vzvm` — roughly 1000 lines of
  Swift, no dependencies beyond Apple's Foundation and Virtualization frameworks.

> **Correction to a prior assumption in this thread:** this work *has* been upstreamed.
> It is in `nixos-unstable` today (and therefore cached by `cache.nixos.org`, requiring no
> manual bootstrap) and is slated to ship in **NixOS 26.11**. It is not an out-of-tree
> contribution.
>
> A separate, older, out-of-tree project also exists —
> `github.com/cpick/nix-rosetta-builder` — which solved the same problem before upstream
> did. If team configurations already reference it, that is a candidate for migration, but
> **that is an observation, not a recommendation.**

`[RESEARCH]` **Upstream presence verified (P1, 2026-08-31, live nixos-unstable via mcp-nixos):**
- `pkgs.darwin.linux-builder-vz` exists (attribute `darwin.linux-builder-vz`, package name
  `create-builder`, "Create a Linux builder VM for macOS"). ✓
- `pkgs.vzvm` exists — v1.0.0, "Minimal Linux VM monitor built on Apple's Virtualization.framework",
  homepage `github.com/applicative-systems/vzvm`, MIT. ✓ (The "~1000 lines of Swift" figure is not
  checkable from package metadata; treat that specific number as still `[UNVERIFIED]`.)
- The PR number (#544193), author, reviewer, and 2026-08-10 announcement date are **not** verifiable
  from nixpkgs metadata alone; they remain as-cited from the announcement post (§10), unverified here.

`[RESEARCH]` **Present in our current lock (P1, corrected):** our top-level `inputs.nixpkgs`
resolves to rev `ffb3c9b700e759be2ef13237c9d8f953b32a1e46`, `lastModified` **2026-08-19** — after the
August-2026 merge — and `pkgs.darwin.linux-builder-vz`, `pkgs.vzvm`, the `virtualisation.vz.*` module
(`nixos/modules/virtualisation/vz-vm.nix`) and `virtualisation.rosetta.nix` are all **already in the
nixpkgs we evaluate against** (verified by store-path inspection + `nix eval`). **No nixpkgs bump is
needed to adopt the mechanism** — this removes a prerequisite PM/P9 would otherwise have carried.
(Caveat, corrected in v1.3: an earlier v1.2 note wrongly said our pin was rev `62c8382`/2026-01-30
and predated the merge. That `62c8382` node in `flake.lock` is a *transitive* nixpkgs pulled in by
another flake input, **not** our top-level `inputs.nixpkgs`; the mistake came from reading a
lock-node by name instead of following the root input edge.)

`[UNVERIFIED]` **Zero adoption in our repos (P1, Q9):** `rg` across every nixcfg and nixcfg-work
worktree finds no reference to `cpick/nix-rosetta-builder`, nor to `linux-builder-vz`, `vzvm`,
`virtualisation.vz`, or `virtualisation.rosetta`. Nothing to migrate; the mechanism is genuinely
new to us (confirms the plan-055 survey).

### 4.3 What `linux-builder-vz` actually is

`[RESEARCH]` It runs the *same* NixOS builder guest as the existing `darwin.linux-builder`,
but on `Virtualization.framework` via `vzvm` instead of QEMU. Because it can therefore
expose Rosetta, `x86_64-linux` builds are **translated rather than emulated**.

Design decisions in `vzvm`:

| Aspect | Approach |
|---|---|
| Boot | `VZLinuxBootLoader` — direct kernel + initrd. No bootloader, no ESP, no mutable system disk. |
| Guest store | Read-only **EROFS** image, cached by closure hash. Source of the predictable boot time. |
| Networking | `Virtualization.framework` NAT attachment. Zero configuration. |
| Inbound SSH | Forwarded through a **vsock** socket (NAT blocks direct inbound). No root, no firewall config. |
| Rosetta | Mounted into the guest; `virtualisation.rosetta` registers it via `binfmt_misc`. |

It is a **drop-in replacement**: same host port (31022), same SSH host key and builder
identity, same launchd service, same `/etc/nix/machines` entry, same tuning options
(`ephemeral`, `maxJobs`, disk size, memory size, cores).

### 4.4 Reported numbers

`[RESEARCH]` From the author's benchmarks:

| Metric | Result |
|---|---|
| `x86_64-linux` build throughput | **2.54× faster** than QEMU with `boot.binfmt.emulatedSystems` |
| `aarch64-linux` build throughput | **Unchanged** between backends — confirms Rosetta is the variable |
| VM boot time | 12–13 s, consistently (QEMU builder often >30 s) |
| Builder closure download | ~3.2 GiB → ~1.2 GiB |

`[UNVERIFIED]` These are single-author benchmarks on unspecified hardware with an
unspecified workload mix. Treat 2.5× as an order-of-magnitude expectation, not a
specification. Benchmark against a representative build from the actual repository.

### 4.5 Configuration

Minimal:

```nix
# nix-darwin configuration
{
  nix = {
    linux-builder = {
      enable = true;
      package = pkgs.darwin.linux-builder-vz;   # the vz backend
      systems = [ "aarch64-linux" "x86_64-linux" ];
    };
    settings.trusted-users = [ "@admin" ];
  };
}
```

Rosetta must be installed on the host first (it is not present by default):

```console
$ softwareupdate --install-rosetta --agree-to-license
```

`[RESEARCH]` The builder **refuses to start** when Rosetta is missing rather than
silently dropping `x86_64-linux` support. To run without it:
`virtualisation.vz.rosetta.enable = false;`

`[RESEARCH]` **Verified against source (P1):** the nix-darwin option index confirms
`nix.linux-builder.{enable,package,systems,ephemeral,maxJobs,supportedFeatures,config,speedFactor}`
— the whole config shape above evaluates against real options. ✓ The guest-side toggles this section
and §6.3 cite are **confirmed correct** by reading the actual module in our pinned nixpkgs,
`nixos/modules/virtualisation/vz-vm.nix`:
- `virtualisation.vz.rosetta.enable` — declared at `vz-vm.nix:81-82`. ✓
- `virtualisation.vz.nestedVirtualization` — declared at `vz-vm.nix:100`. ✓
- `virtualisation.vz.package` = `mkPackageOption "vzvm"` (`vz-vm.nix:79`) — confirms the vz backend is
  `pkgs.vzvm`.
- When `vz.rosetta.enable` is set, the module wires `virtualisation.rosetta.enable = true` and
  `virtualisation.rosetta.mountTag = "rosetta"` (`vz-vm.nix:279-281`) — exactly the §3 mechanism.

These options simply are **not indexed by search.nixos.org yet** (they were merged too recently);
that index gap is what an earlier v1.2 note mis-read as a "discrepancy." The attribute paths are
correct — safe to use once a host actually adopts (still gated on P9). `fixBinary`/sandbox behaviour
of `virtualisation.rosetta` is a separate question owned by **P6a** (preview: `rosetta.nix:77` sets
`fixBinary = true`).

Realistic sizing (defaults of 1 core / 3 GB / 20 GB are too small for production builds):

```nix
{
  nix.linux-builder = {
    enable = true;
    package = pkgs.darwin.linux-builder-vz;
    systems = [ "aarch64-linux" "x86_64-linux" ];

    ephemeral = true;      # wipes the disk image on restart; config changes apply cleanly
    maxJobs = 4;
    config = {
      virtualisation = {
        darwin-builder = {
          diskSize   = 40 * 1024;
          memorySize =  8 * 1024;
        };
        cores = 6;
      };
    };
  };
}
```

### 4.6 Migration hazard

`[RESEARCH]` When switching an existing QEMU builder to the vz backend, **delete the data
disk first**:

```console
$ sudo rm /var/lib/linux-builder/nixos.qcow2
```

The vz builder reuses the same filename but writes a **raw** image, and will refuse to
start rather than misread a genuine qcow2 left in place.

### 4.7 Observability

`[RESEARCH]` Guest console output goes to the macOS unified log:

```console
$ /usr/bin/log show --last 5m --predicate 'subsystem == "systems.applicative.vzvm"'
```

Also visible in Console.app under Log Reports as `linux-builder.log` and
`linux-builder.console.log`.

### 4.8 Scope limits of `vzvm` itself

`[RESEARCH]` No display, no snapshots, no bridged networking, no cloud-init. It is
purpose-built for the remote-builder case. For general-purpose Linux VMs on macOS, vfkit,
Lima, or UTM are the appropriate tools — all three can also expose Rosetta, and
`virtualisation.rosetta` works with them.

---

## 5. Capability matrix

What moves onto an Apple Silicon Mac, and what does not.

| Workload | aarch64 | x86_64 | Notes |
|---|---|---|---|
| Nix package builds | Native | **Rosetta-translated** | ~2.5× faster than QEMU binfmt |
| Vendor toolchains shipped as amd64-only ELF | n/a | **Works** | The single biggest practical win for embedded work |
| Yocto / OE / Buildroot / ISAR-style flows | Native | Translated | Host tooling; not target execution |
| Container images (`linux/amd64`) | Native | Translated | Rosetta path avoids QEMU user-mode emulation |
| Building complete NixOS system closures for remote deploy | Native | Translated | `nixos-rebuild --target-host --fast --use-substitutes` |
| **NixOS VM tests** | **Conditional** — see §6 | **Problematic** — see §6 | The hard boundary |
| Booting an x86_64 kernel | — | **No** | Rosetta translates userspace ELF only |
| x86 kernel modules / driver work | — | **No** | |
| Target hardware behaviour (timing, errata, peripherals) | **No** | **No** | Not a target simulator under any configuration |

The general shape: **Rosetta relocates the *build and tooling host*. It does not relocate
the *system under test*.**

---

## 6. NixOS VM tests — the part that does not follow the build story

This is the section that answers the operator's actual question, and the answer is *not*
a straightforward extension of the build story.

### 6.1 Why VM tests are categorically different

A Nix *build* runs userspace processes. Rosetta translates userspace processes. The
mapping is clean.

A NixOS VM test **boots one or more full Linux kernels under QEMU** inside the build
sandbox. The test driver launches `qemu-system-<arch>` per node and drives them over
serial/monitor sockets. Rosetta has nothing to say about a kernel — it operates strictly
above the syscall boundary.

So the question is not "can Rosetta translate this?" It is **"where does the CPU
virtualization for the guest kernel come from?"**

### 6.2 The layering

```
macOS host (aarch64)
└── vzvm VM  (aarch64 Linux — the Nix remote builder)
    │  Rosetta: translates x86_64 *userspace* in this layer
    │
    └── Nix build sandbox running a NixOS VM test derivation
        └── qemu-system-<arch>  ← needs an acceleration source
            └── nested guest kernel  ← THE SYSTEM UNDER TEST
```

Rosetta operates at layer 2. The system under test is at layer 4. Rosetta does not reach
it.

### 6.3 aarch64 VM tests: viable, with hard prerequisites

`[RESEARCH]` NixOS integration tests require a builder that provides `/dev/kvm`. The
QEMU-based `linux-builder` could not provide this. **`vzvm` supports nested
virtualization**, so the builder VM can expose `/dev/kvm`:

```nix
{
  nix.linux-builder = {
    enable = true;
    package = pkgs.darwin.linux-builder-vz;

    config.virtualisation.vz.nestedVirtualization = true;
  };
}
```

`[RESEARCH]` **Prerequisites, per Apple's own documentation:**

- **macOS 15 or newer**
- **M3 chip or newer** — "Nested virtualization is available for Mac with the M3 chip, and
  later."

This is a fleet-composition constraint, not a software one. M1 and M2 machines — including
M1 Max and M2 Max — **cannot run NixOS VM tests locally under this scheme at all**. They
can still build.

> **Action item:** inventory the team's machines by M-generation and macOS version before
> any planning proceeds. This single fact partitions the fleet into two capability tiers.

`[UNVERIFIED]` For an aarch64 node under test: the L1 builder is aarch64, nested KVM is
aarch64, and the guest kernel is aarch64. Acceleration is available end to end and
performance should approach a native aarch64 runner. Benchmark to confirm.

`[RESEARCH]` **Our-suite premise confirmed (P1):** our VM tests are standard
`pkgs.testers.nixosTest`/`runNixOSTest` derivations, which the nixpkgs testing framework tags with
the `kvm` + `nixos-test` `requiredSystemFeatures`. We rely on this in practice: the
`vm-dev-team-vm-smoketest` is explicitly routed by nixcfg-work CI to an aarch64 KVM-metal runner
(tag `aws-uswest2-metal-nix-arm64-kvm`) "which provides hardware `/dev/kvm`"
(`modules/flake-parts/vm-tests.nix:2016-2017`). So "the builder must provide `/dev/kvm`" is not
hypothetical for us — it is already a hard requirement our aarch64 tests satisfy via a metal runner,
and is exactly what a Mac vz builder would need `vz.nestedVirtualization` to reproduce locally.

### 6.4 x86_64 VM tests: Rosetta does not help

`[UNVERIFIED — this is the central analytical claim of this document and must be tested]`

Trace it through:

1. The test derivation's system is `x86_64-linux`. Its build inputs — driver, QEMU,
   kernel, node closures — build fine, translated by Rosetta. **No problem yet.**
2. The driver executes `qemu-system-x86_64`. That binary is itself an x86_64 ELF, so it
   runs *under Rosetta translation*.
3. That QEMU must boot an **x86_64 guest kernel**.
4. Acceleration options for an x86_64 guest:
   - **KVM?** No. Nested KVM inside the L1 guest is running on ARM silicon. KVM only
     accelerates guests of the *same* architecture as the physical CPU. There is no x86
     hardware virtualization anywhere in this stack.
   - **Rosetta?** No. Rosetta cannot translate kernel-mode execution or provide a virtual
     CPU.
   - **TCG.** The remaining option: QEMU's software translator, in full-system mode.

So the effective execution model is **QEMU TCG (x86 → x86 IR → x86) running inside a
Rosetta translation of QEMU itself (x86 → arm64)**. Two translation layers stacked, with
the inner one being a JIT.

Consequences to expect and verify:

- `[UNVERIFIED]` **Severe slowdown.** Likely far worse than the ~2.5× improvement seen for
  builds — this is the pathological case, not the good case.
- `[UNVERIFIED]` **Possible outright failure.** QEMU's TCG is a JIT, and Rosetta's JIT
  support in Linux guests carries W^X and code-cache constraints. Whether a
  Rosetta-translated QEMU generating and executing TCG code works reliably is an open
  empirical question. **This is the highest-value single experiment to run.**
- `[UNVERIFIED]` **The `kvm` feature may cause a hard error rather than a fallback.**
  Nix gates on `requiredSystemFeatures` (`kvm`, `nixos-test`); QEMU invocation in the
  nixpkgs test machinery may attempt KVM acceleration and fail rather than silently
  degrade to TCG. Determine which failure mode actually occurs.

`[RESEARCH]` **Scope check against our actual suite (P1): this pathology is not currently
triggered.** Every test in `modules/flake-parts/vm-tests.nix` builds a guest of the **host**
architecture — x86_64-linux guests evaluate/run on x86_64 runners, and the one aarch64 gate
(`vm-dev-team-vm-smoketest`) runs on an aarch64 metal runner. We have **no** test that boots an
x86_64 guest kernel on an aarch64 host. The §6.4 two-translation-layers case therefore only arises
if we *choose* to route an x86_64 NixOS VM test onto a Mac's aarch64 vz builder (an Option-C-style
decision, §7). Until then the risk is latent, not active. The empirical "does TCG-under-Rosetta run
at all" question stays for **P3** (needs a Mac); this finding just bounds *when* it would matter for
us and hands that framing to plan 054.

### 6.5 The scheduling hazard

`[UNVERIFIED — but a concrete, checkable design concern]`

A builder configured as:

```nix
systems = [ "aarch64-linux" "x86_64-linux" ];
```

...and advertising `kvm` + `nixos-test` will present itself to Nix as capable of running
**x86_64 NixOS VM tests with KVM**. It is not. Nix has no way to express "this machine has
KVM for aarch64 but not for x86_64" in a single `/etc/nix/machines` entry.

`[UNVERIFIED]` A plausible mitigation is **two `nix.buildMachines` entries pointing at the
same SSH host**, with different `systems` and `supportedFeatures`:

```nix
# ILLUSTRATIVE ONLY — not validated, not a recommendation
nix.buildMachines = [
  { hostName = "linux-builder";
    systems = [ "aarch64-linux" ];
    supportedFeatures = [ "kvm" "nixos-test" "big-parallel" "benchmark" ]; }
  { hostName = "linux-builder";
    systems = [ "x86_64-linux" ];
    supportedFeatures = [ "big-parallel" "benchmark" ];   # deliberately no kvm/nixos-test
    speedFactor = 1; }
];
```

The intent is that x86_64 VM tests fail to schedule locally and route to a real x86_64
builder instead of silently running at TCG speed. **Whether Nix's scheduler accepts
duplicate `hostName` entries this way, and whether nix-darwin's `linux-builder` module
composes with hand-written `buildMachines`, must be verified before this is used.**

### 6.6 The embedded-specific caveat

`[RESEARCH — Q7 resolved, P1 2026-08-31]` **Our systems under test are NixOS guests, not
arbitrary embedded images.** All 19 VM tests in `modules/flake-parts/vm-tests.nix` (plus the two
`tests/integration/*.nix`) build the guest from our dendritic `self.modules.nixos.*` via
`pkgs.testers.nixosTest` (19 calls) or `runNixOSTest` (nspawn backend); 26 `self.modules.nixos.*`
imports; **zero** custom-kernel / raw-`.img` / `crossSystem` / non-NixOS guests. Even the
closest-to-"shipped-artifact" case (`vm-dev-team-vm-smoketest`) is a NixOS guest composed from
`system-cli` + `dev-team`, run on the test driver's own VM disk. So the "arbitrary embedded image"
branch below is, for us today, hypothetical.

The general rule still holds and is worth keeping: *if* a test ever wraps a non-NixOS `x86_64`
kernel image in a NixOS harness, the same architecture rule applies unchanged — the **guest
kernel's** architecture, not the userspace, determines whether hardware acceleration is available,
and wrapping a custom `x86_64` kernel in a NixOS test does not change the §6.4 analysis.

Separately: **VM tests of any architecture do not validate target hardware behaviour** —
timing, cache effects, errata, peripheral interaction, or anything touching real silicon.
That boundary is unaffected by any of this and is worth stating explicitly in any
discussion of "can we move testing to laptops."

---

## 7. Architectural options

**None of these is a recommendation. None has been adopted.** They are the shape of the
decision space given §6.

### Option A — Split by architecture
Apple Silicon machines run `aarch64-linux` VM tests locally (M3+/macOS 15+ only) and build
both architectures. `x86_64-linux` VM tests route to native x86_64 runners.

- *Requires:* solving §6.5 scheduling. Tolerating a capability split across the fleet.

### Option B — Builds local, all VM tests remote
Apple Silicon machines are build hosts only. All VM tests execute on native runners of the
matching architecture.

- *Requires:* aarch64 runner capacity. Gives up local test iteration on Macs.
- *Advantage:* one uniform story; no M-generation partition; no nested-virt dependency.

### Option C — Accept TCG for x86_64 VM tests locally
Allow the slow path for developer-local iteration, gate CI on native runners.

- *Requires:* §6.4's "does it even work" question answered affirmatively first.
- *Risk:* a slow-but-working local path silently becomes the path of least resistance.

### Option D — Do not move VM tests to Macs at all
Rosetta improves the build story only. Test execution stays where it is.

- *Advantage:* the smallest change; captures the largest verified win (§4.4) with no
  dependency on §6 at all.

The honest summary: **the build-side benefit is well-established and low-risk. The
test-side benefit is architecturally constrained, generation-gated, and — for x86_64 —
possibly nonexistent.** These should be evaluated as two separate decisions, not one.

---

## 8. Verification plan

Ordered by information value per unit of effort.

1. **Fleet inventory.** M-generation and macOS version for every developer machine.
   Partitions the fleet into nested-virt-capable and not. *Nothing in §6 can be planned
   without this.*
2. **Baseline the build win.** Stand up `linux-builder-vz` on one machine. Time a
   representative `x86_64-linux` build from the actual repository against the current QEMU
   binfmt path. Confirm or refute 2.5× on real workloads.
3. **Does a Rosetta-translated QEMU TCG even run?** The §6.4 question. Smallest possible
   x86_64 NixOS VM test, executed on the vz builder. Record the exact failure mode if it
   fails. **Highest-value single experiment in this document.**
4. **aarch64 VM test under nested virt.** On an M3+/macOS 15+ machine, enable
   `virtualisation.vz.nestedVirtualization` and run a representative aarch64 test. Compare
   wall-clock against a native aarch64 runner.
5. **Scheduling behaviour.** Test the §6.5 dual-entry approach. Determine what Nix
   actually does when a builder advertises `kvm` for a system it cannot accelerate.
6. **binfmt registration inside the Nix sandbox.** `[UNVERIFIED]` Nix builds run in a
   chroot. `binfmt_misc` handlers need the "fix binary" (`F`) flag to resolve the
   interpreter correctly across a chroot boundary. Confirm `virtualisation.rosetta`
   registers with `fixBinary` set, or that builds work regardless. A failure here would
   manifest as x86_64 builds working interactively but failing under `nix build`.
7. **Vendor toolchain smoke test.** Run whichever amd64-only vendor binaries the team
   depends on under Rosetta in the guest. This is where the AVX and JIT caveats in §3 will
   surface if they are going to.

---

## 9. Open questions

| # | Question | Owner | Status |
|---|---|---|---|
| Q1 | M-generation / macOS version distribution across the fleet | — | Open |
| Q2 | Does a Rosetta-translated `qemu-system-x86_64` run TCG reliably? | — | Open |
| Q3 | What is the actual x86_64 VM test wall-clock, if it runs at all? | — | Open |
| Q4 | Does Nix error or degrade when `kvm` is advertised but unusable for the target arch? | — | Open |
| Q5 | Can `nix.buildMachines` carry two entries for one host with different features? | — | Open |
| Q6 | Does `virtualisation.rosetta` register binfmt with `fixBinary` for sandbox use? | P6a/P6b | **Code half CLOSED (§4.1, P6a):** YES — `rosetta.nix:77` sets `fixBinary = true` (binfmt `F` flag) + `matchCredentials`/`preserveArgvZero`/`wrapInterpreterInShell=false`, and the module extends the sandbox for x86_64 (`extra-platforms`, `extra-sandbox-paths=[/run/binfmt, mountPoint]`). **Mac half still Open (P6b):** demonstrate an x86_64 `nix build` succeeding through the sandbox on a Mac. |
| Q7 | Are the systems under test NixOS guests or arbitrary embedded images? | P1 | **CLOSED (§6.6):** NixOS guests. All 19 VM tests build the guest from `self.modules.nixos.*` via `pkgs.testers.nixosTest`/`runNixOSTest`; zero embedded/raw-image/custom-kernel/cross-arch guests. |
| Q8 | Do the team's amd64-only vendor toolchains run clean under Rosetta? | — | Open |
| Q9 | Do any existing configs reference `cpick/nix-rosetta-builder`? | P1 | **CLOSED (§4.2):** No. `rg` across all nixcfg + nixcfg-work worktrees: zero hits for `cpick`/`nix-rosetta-builder` (also zero for `linux-builder-vz`/`vzvm`/`virtualisation.vz`/`virtualisation.rosetta`). |
| Q10 | Confirm the Linux-VM Rosetta path's status in current Apple docs | P8 | **CLOSED (§2.2):** The deprecation notice is scoped to Intel *macOS apps* only (macOS 26.4 notifications → macOS 27 final general-purpose Rosetta → beyond = unmaintained-games subset) and does **not** mention the Linux/VM path, which remains a separately-published feature; Apple DTS confirms the two are distinct use cases. **However** Apple explicitly declined to guarantee Linux-VM Rosetta past macOS 27 — post-27 availability is an OPEN RISK, not assured (correcting the earlier overstated "not being sunset" framing). |

---

## 10. References

**Primary — the recent work**
- Nixcademy, *2.5x Faster x86_64 Linux Builds on macOS with Rosetta*, 2026-08-10 —
  `https://nixcademy.com/posts/rosetta-linux-builder-macos/`
- nixpkgs PR #544193 — `https://github.com/NixOS/nixpkgs/pull/544193`
- `vzvm` — `https://github.com/applicative-systems/vzvm`
- nixpkgs darwin-builder docs —
  `https://github.com/NixOS/nixpkgs/blob/master/doc/packages/darwin-builder.section.md`
- `virtualisation.rosetta` module —
  `https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/rosetta.nix`

**Background / prior art**
- nixpkgs issue #262941, *x86_64-linux builder for darwin is slow; no Rosetta* (2023) —
  the original problem statement
- nix-darwin issue #1091 — the UTM + `virtualisation.rosetta` workaround
- `cpick/nix-rosetta-builder` — out-of-tree predecessor
- Nixcademy, *Run NixOS Integration Tests on macOS* — the test-driver-on-macOS piece

**Apple**
- *About the Rosetta translation environment* —
  `https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment`
- *Running Intel Binaries in Linux VMs with Rosetta* —
  `https://developer.apple.com/documentation/virtualization/running_intel_binaries_in_linux_vms_with_rosetta`
- *Upcoming changes to Rosetta support for Intel-based macOS apps* (deprecation notice, P8) —
  `https://developer.apple.com/news/?id=w5ngl9k2`
- `VZGenericPlatformConfiguration.isNestedVirtualizationSupported` — the M3+ requirement

---

## 11. Changelog

| Version | Date | Change |
|---|---|---|
| v1.5 | 2026-09-04 | **P6a — binfmt fixBinary confirmed in source (Q6 code half CLOSED).** Read `rosetta.nix` in our pinned nixpkgs (`ffb3c9b`, store `/nix/store/jpnpv93s5ppfb1kbvfp8qa763vfb4fjb-source`): `boot.binfmt.registrations.rosetta` sets `fixBinary = true` (line 77, the `F` flag → interpreter fd pre-opened at registration, works inside the mount-namespace build sandbox), plus `matchCredentials`/`preserveArgvZero`/`wrapInterpreterInShell=false`, and the module explicitly extends the sandbox for x86_64 (`nix.settings.extra-platforms=["x86_64-linux"]`@65, `extra-sandbox-paths=["/run/binfmt", mountPoint]`@66-69). §4.1 gains a P6a block; §9 Q6 code-half struck (Mac half → P6b). Confirms P1's incidental preview. |
| v1.4 | 2026-09-04 | **P8 — Apple-docs recheck (Q10 CLOSED).** Verified §2.2 against Apple's live deprecation notice + developer news. CONFIRMED: the deprecation is scoped to Intel *macOS apps* only (timeline: macOS 26.4 notifications → macOS 27 final general-purpose Rosetta → beyond = unmaintained-games-only subset), makes NO mention of the Linux/VM path, and Apple DTS confirms the two are distinct use cases; the Linux-VM feature remains separately published. CORRECTED: the earlier `[RESEARCH]` claim that Apple "is *not* sunsetting" the Linux path, and the specific "macOS 27 built-in / no separate install / availability check always reports installed" statement — unverifiable and overstated. Apple DTS explicitly declined to commit whether Linux-VM Rosetta survives past macOS 27, so post-27 availability is now recorded as an OPEN RISK feeding §7 / the PD gate. §2.2 rewritten, §9 Q10 struck, §10 refs add the deprecation-notice + Linux-VMs doc URLs. Empirical build/TCG claims (§4.4/§6.x) remain `[UNVERIFIED]` (Mac-gated, P2-P4). |
| v1 | 2026-08-31 | Initial compilation. Rosetta mechanics, `linux-builder-vz` upstreaming, VM-test analysis, verification plan. All §6.4–§6.6 claims `[UNVERIFIED]`. |
| v1.3 | 2026-08-31 | **P1 self-correction (verified against actual pinned nixpkgs source, not just the search index).** Two v1.2 claims were wrong and are corrected in §4.2/§4.5: (1) our top-level `inputs.nixpkgs` is rev `ffb3c9b` / **2026-08-19** (post-merge) and **already contains** `linux-builder-vz`, `vzvm`, `virtualisation.vz.*`, and `rosetta.nix` — **no nixpkgs bump needed**; the `62c8382`/2026-01-30 lock node is a *transitive* input of another flake input, not our root nixpkgs (v1.2 read a lock-node by name instead of following the input edge). (2) The `virtualisation.vz.*` paths are **not** a discrepancy — they are confirmed in `nixos/modules/virtualisation/vz-vm.nix` (`vz.rosetta.enable`@81, `vz.nestedVirtualization`@100, `vz.package=vzvm`@79, and vz→`virtualisation.rosetta` wiring @279-281); they were merely absent from the search.nixos.org index. Source also corroborates §2.3/§3: vz-vm.nix asserts aarch64-darwin-host-only (@197) and cannot emulate a foreign guest arch (@204). Incidental P6a preview: `rosetta.nix:77` sets `fixBinary = true` (P6a still owns the sandbox (b) analysis). |
| v1.2 | 2026-08-31 | **P1 code-verification pass** (host-independent; no Mac). Verified vs live nixos-unstable (mcp-nixos) + our repos: `pkgs.darwin.linux-builder-vz` and `pkgs.vzvm` (v1.0.0) **exist upstream** (§4.2 ✓); `virtualisation.rosetta.{enable,mountTag}` **exist** (§4.1 ✓); `nix.linux-builder.{package,systems,ephemeral,maxJobs,supportedFeatures,config,speedFactor}` **exist** (§4.5 config shape ✓). **Discrepancy flagged:** `virtualisation.vz.rosetta.enable` / `virtualisation.vz.nestedVirtualization` (§4.5/§6.3) are **not** in the NixOS options index — likely guest-module-only; exact attr path downgraded to `[UNVERIFIED]`, source confirmation deferred to P6a/PM. **Q7 CLOSED (§6.6):** our systems-under-test are NixOS guests (19 `nixosTest`/`runNixOSTest`, 26 `self.modules.nixos.*` imports, zero embedded/raw-image/cross-arch guests). **Q9 CLOSED (§4.2):** zero refs to `cpick/nix-rosetta-builder` (or `linux-builder-vz`/`vzvm`/`virtualisation.vz`/`virtualisation.rosetta`) anywhere in nixcfg + nixcfg-work. **New findings:** (a) our nixpkgs pin (rev `62c8382`, 2026-01-30) **predates** the Aug-2026 merge — mechanism is upstream but absent from our lock; adoption needs a bump (§4.2). (b) §6.4 pathology is **not currently triggered** — our VM tests are all host-arch, aarch64 gate runs on an aarch64 KVM-metal runner; the x86-on-Mac case only arises under an explicit Option-C routing choice (§6.4). (c) §6.3 KVM premise **confirmed for us** — `vm-dev-team-vm-smoketest` already requires hardware `/dev/kvm` via a metal runner (§6.3). |
| v1.1 | 2026-08-31 | `[STATED]` Placed under nixcfg plan 055 (worktree `nixcfg-rosetta`, branch `plan-055-rosetta-multiarch`). Cross-repo survey (nixcfg + nixcfg-work, all worktrees/branches): existing prior art is QEMU-binfmt cross-builds (`dev-team.nix` `boot.binfmt.emulatedSystems`), an aarch64 NixOS qcow2 run under UTM/QEMU (`nixos-dev-team-vm` / `image-vm-dev-team`, nixcfg-work CI-published), an *inverted* remote builder (Linux host → Mac for aarch64-darwin), and Rosetta-into-a-Linux-guest already used once via Colima `rosetta=true` (x86 containers). `linux-builder-vz`/`vzvm`/`virtualisation.vz` have ZERO occurrences in either repo — the mechanism here is new to us. Full claim-verification deferred to plan 055 P1. `[DECISION]` (governance, not §7): split public/private — nixcfg owns the portable mechanism + claim-verification; nixcfg-work owns the §7 adoption decision + corp experiments; §6 feeds plan 054, not a fork. Reference §7 A/B/C/D remain **options, none adopted.** |

---

*Append below this line as the work proceeds.*
