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

`[RESEARCH]` **This is the product Apple is *not* sunsetting.** Apple's documentation
states that starting in macOS 27, Intel binary translation for Linux is built into the OS
with no separate Rosetta install, and the availability check always reports installed.
Apple developer support has drawn the distinction explicitly: running x86_64 Linux
binaries in VMs is a separate use case from the macOS Rosetta translation environment,
because those binaries do not depend on macOS system frameworks.

> **Implication for planning:** the macOS-app Rosetta deprecation timeline does **not**
> apply to the Linux/VM path. Do not let the two get conflated in risk assessments.
> `[UNVERIFIED]` — re-verify against Apple docs before committing a team toolchain, since
> this is still in motion as of writing.

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

`[UNVERIFIED — depends on facts not yet established]`

If the systems under test are not NixOS guests but arbitrary embedded Linux images wrapped
in a NixOS test harness, the same architecture rule applies unchanged: the *guest kernel's*
architecture, not the userspace, determines whether hardware acceleration is available.
Wrapping a custom `x86_64` kernel image in a NixOS test does not change the analysis in
§6.4.

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
| Q6 | Does `virtualisation.rosetta` register binfmt with `fixBinary` for sandbox use? | — | Open |
| Q7 | Are the systems under test NixOS guests or arbitrary embedded images? | — | Open |
| Q8 | Do the team's amd64-only vendor toolchains run clean under Rosetta? | — | Open |
| Q9 | Do any existing configs reference `cpick/nix-rosetta-builder`? | — | Open |
| Q10 | Confirm the Linux-VM Rosetta path's status in current Apple docs | — | Open |

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
- *Running Intel Binaries in Linux VMs with Rosetta*
- `VZGenericPlatformConfiguration.isNestedVirtualizationSupported` — the M3+ requirement

---

## 11. Changelog

| Version | Date | Change |
|---|---|---|
| v1 | 2026-08-31 | Initial compilation. Rosetta mechanics, `linux-builder-vz` upstreaming, VM-test analysis, verification plan. All §6.4–§6.6 claims `[UNVERIFIED]`. |

---

*Append below this line as the work proceeds.*
