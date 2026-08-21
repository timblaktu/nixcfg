# Plan 052 — Super-plan: Share nixcfg nix-darwin + NixOS VM/WSL configs with the dev team

Status: ACTIVE (coordinating meta-plan; M0 decided 2026-08-20 → M-A/darwin bring-up first; M-C standing)
Owner: Tim
Created: 2026-08-20
Kind: **Coordinating meta-plan** — it TRACKS and sequences sub-plans that live in two
repos; it does NOT duplicate their task detail. Detailed tasks stay in their home plans.

## PUBLIC-SAFETY CONSTRAINT (read first)
This plan lives in **public `nixcfg`** (github.com/timblaktu/nixcfg). It MUST NOT contain
corporate secrets, internal URLs, GitLab hostnames, tokens, CIDs, or runner names. It
references the private `nixcfg-work` sub-plans **by number/name only**. Any secret-bearing
detail belongs in the corresponding `~/src/nixcfg-work/.claude/user-plans/` plan, not here.

## Super-goal
Make it turnkey for a dev-team colleague to run Tim's nixcfg-derived environment on their
own machine, across BOTH delivery shapes:
- **NixOS VM/WSL images** (the mostly-working half): WSL `.wsl`, Proxmox, EC2/Graviton AMI,
  and the aarch64 **Mac-VM qcow2** (UTM/QEMU on Apple Silicon).
- **Native nix-darwin** (the frontier half): a shared `corp-darwin-dev-team` config a
  colleague activates directly on an Apple-Silicon Mac.
…unified under one delivery + consumption + validation story, warm-cached for practical use.

## Two-repo / two-layer architecture
- **`nixcfg` (public) = shared substrate.** 47+ reusable modules, the distributable-image
  builders (WSL/Proxmox/EC2/Graviton/Mac-VM qcow2), the VM-test tiers (`mkVmTest`), and the
  distribution mechanism + docs. This is where the portable, secret-free work lands.
- **`nixcfg-work` (private, corporate GitLab) = deployment layer.** The real corp hosts
  (`corp-wsl-dev-team`, `corp-darwin-dev-team`, Tim's `pa163076mac`), the GitLab CI release
  pipeline, IT/compliance values. Consumes `nixcfg` as a flake input (currently pins nixcfg
  `main`). Cross-repo: several nixcfg changes only go LIVE via a nixcfg-work `flake.lock` bump.

## Constituent sub-plans (source of truth for detail)

### ACTIVE — in scope
| Plan | Repo | What | State (2026-08-20) |
|---|---|---|---|
| **026** team-sharing-refactoring | nixcfg | made the repo a shareable library + CrowdStrike module | DONE **except T6** (IT/Falcon demo — human/IT-gated) |
| **001** darwin-support | nixcfg-work | shared `corp-darwin-dev-team` nix-darwin config | Advanced WIP: **eval-green, NEVER activated on real Apple Silicon**; remaining tasks all hardware/Interactive/parked |
| **004** machine-image-ci-release | nixcfg-work | one GitLab pipeline for every distributable artifact | Active WIP: qcow2 build+publish already live; darwin-cache + macOS runner + metal-KVM gate not stood up; 5 T0 decisions open |
| **053** nixos-2605-uplift-nspawn-tests | nixcfg | 26.05 input uplift + systemd-nspawn container test backend → cheap/fast test coverage across all hosts | NEW 2026-08-20 (= milestone **M-E**). Top-priority WSL-side workstream; T0 (branch + release target) is Interactive/next |

### CLOSED — context only (do NOT resurface in "what's active" searches)
| Plan | Repo | Why closed |
|---|---|---|
| 023 distributable-wsl-images | nixcfg `archive/` | DONE — established the 4-layer `wsl-enterprise→dev-team→host→personal` model (foundational) |
| 020 vm-test-infrastructure | nixcfg `archive/` | DONE — the `mkVmTest` CI test substrate |
| 018 nixcfg-modularization | nixcfg `archive/` | SUPERSEDED — the two-repo split idea was abandoned (single-repo won); do NOT resurrect |
| 013 distributed-nix-binary-caching | nixcfg `archive/` | DEFERRED — Attic cache, blocked on office Mikrotik/NUC hardware; a productivity multiplier, not on the sharing critical path |
| 002 corp-wsl-distribution | nixcfg-work `archive/` | DONE — a `.wsl` was built, security-checked, imported, validated end-to-end |
| 003 corp-wsl-ci-release | nixcfg-work `archive/` | SUPERSEDED — absorbed into 004 T4 (the WSL slice of the unified pipeline) |

Numbering-collision note (housekeeping H2 below): nixcfg-work still has a second, unrelated
`002-vte-eks-auth-scoping.md` (AWS EKS auth, DONE) colliding with the archived corp-wsl 002.

## Current shipped state (what already works today)
- **Shared module library:** 47+ exports consumable via `github:timblaktu/nixcfg` (bundle or
  cherry-pick); layer model `system-{minimal,default,cli,desktop}`, `wsl-{base,enterprise,dev-team}`,
  platform-neutral `dev-team` NixOS module + `home-dev-team` HM bundle; CrowdStrike Falcon module.
- **NixOS images (builders work):** `nixos-wsl-dev-team` → `.wsl` (validated end-to-end);
  `nixos-dev-team` → Proxmox; `nixos-dev-team-ec2`/`-graviton` → AMI; **`nixos-dev-team-vm`
  (aarch64) → Mac-VM qcow2** (`image-vm-dev-team`). VM-test gate + shipped-image sudo/wheel
  smoketest wired.
- **CI (partial):** nixcfg-work `.gitlab-ci.yml` already builds+publishes the Mac-VM qcow2 on
  the aarch64 Graviton runner and wires the VMTest smoketest (opt-in / non-blocking).
- **Native darwin (eval-only):** two real host configs (`corp-darwin-dev-team` colleague,
  `pa163076mac` Tim's), full Model A system+HM, `bootstrap-darwin.sh`, colleague quickstart —
  all eval-green from Linux, none activated on a Mac.

## Open frontier — three SEQUENCED milestones + one STANDING workstream
M-A / M-B / M-D are sequenced milestones (their ordering = task **M0**). **M-C is NOT a
milestone with an end — it is an always-on parallel workstream** (its own section below).
Each points at sub-plan tasks for detail.

- **M-A — First real Mac (nix-darwin) hardware bring-up.** The biggest unknown; everything
  darwin is eval-only until a Mac boots the shared config. Drives nixcfg-work **001** T7/T8b/T18b;
  uses `bootstrap-darwin.sh` + `docs/darwin/RESUME-mac-nix-bringup.md`. Gate: physical Mac.
- **M-B — CI/delivery unification.** One GitLab pipeline building/gating/publishing every
  artifact (qcow2 + darwin cache + `.wsl`). Drives nixcfg-work **004** T0–T5 (absorbs 003).
  Gates: macOS aarch64-darwin build runner (doesn't exist yet), hsw-infra metal-KVM runner
  (offline), + 5 budget/infra decisions (004 T0). Insight (004 design doc): WSL ships a `.wsl`
  FILE asset; darwin ships NO file — deliverable = green build gate + warm cache consumed via
  substituter + `darwin-rebuild switch`.
- **M-C — Docs & consumption polish → see the STANDING WORKSTREAM section below.** Runs
  CONTINUOUSLY in parallel; not ordered against A/B/D.
- **M-D — IT/CrowdStrike compliance.** The Falcon/IT demo (nixcfg **026** T6) that unlocks
  production security compliance on the shared WSL image. Human/IT-gated.
- **M-E — NixOS 26.05 uplift + nspawn container test backend (→ nixcfg 053).** TOP-PRIORITY
  **WSL-side** workstream, added 2026-08-20. Migrates the stale nixpkgs pin (currently
  `nixos-unstable` @ 2026-01-30) to a 26.05-aligned target, then adopts the systemd-nspawn test
  driver backend (nixpkgs #478109) so most integration tests run as fast/cheap containers instead
  of QEMU VMs — the ENABLER for cheaply validating all 10 NixOS + 2 Darwin hosts (feeds M-B CI
  unification + general validation). Runs in PARALLEL with M-A: **M-A executes on the Mac (Tim,
  browser); M-E is what the WSL driver session actively builds meanwhile.** Does not block M-A.
  Detail owner = 053. Branch: `feat/nixos-26.05` (proposed, 053 T0).

## STANDING WORKSTREAM — M-C: docs & consumption polish (always-on, parallel)
**This is not a milestone that finishes; it is how the super-plan uses blocked time.**
Whenever ANY task is blocked on a long-running operation (a build, a CI run, a hardware
wait, an IT/budget decision), fall to this workstream and improve the docs. It runs in
parallel with M-A/M-B/M-D for the life of the plan and is never "done".

**Audience — weight every doc edit by this:**
1. A **dev-team colleague** who wants to CONSUME the shared configs/images with minimal friction.
2. Anyone **LEARNING** nix, NixOS, NixOS-WSL, nix-darwin, or reproducible configuration
   management — using this repo as a worked exemplar.

**Quality bar (all five, not merely "correct"):** accurate · current · approachable ·
intelligible · highly useful. Teach the *why* (reproducibility, the dendritic module pattern,
the layer model, flake inputs/pins) — not just enumerate the *what* — and give a followable
on-ramp for a Nix newcomer.

**Operating rule:** on hitting a block — (1) take the top unstarted item from the M-C backlog,
(2) VERIFY the current code before editing prose (never trust stale docs — the doc set is
known-drifted), (3) make the fix and mark it done, (4) return to the blocking task when it
unblocks. Keep edits small + shippable; `.md`-only commits skip the flake-check hook, so
commit freely.

**Scope = PUBLIC nixcfg docs.** Corporate onboarding (corp-wsl / corp-darwin specifics) is
tracked in nixcfg-work; a public doc may POINT to it but must carry no corporate detail.

**M-C backlog (LIVING — verified against code 2026-08-20; re-verify each before editing).**
GROUND TRUTH to fix everywhere: `shared-modules.nix` exports **57 modules = 16 NixOS + 32 HM
+ 9 Darwin**; `nixos-configurations.nix` registers **10 NixOS hosts**, `darwin-configurations.nix`
**2 Darwin hosts** (`macbook-air`, `powerbook`). Every doc currently disagrees, differently.

P1 (actively misleading / blocks a teammate):
- **Module counts contradict across 4 docs** (README "54", DISTRIBUTION "47", SHARED-MODULES
  "16+29+9=54", ARCHITECTURE "54"). Fix all to **57 (16/32/9)**; see the SSOT idea below.
- **SHARED-MODULES HM section says 29 but code exports 32** — missing rows for `home-wsl`,
  `home-darwin`, `jfrog-cli` (a teammate can't cherry-pick a module not in the catalog;
  `home-wsl`/`home-darwin` are the real composition layers). Bump header + add the 3 rows.
- **Image OUTPUTS undocumented as consumable artifacts.** `packages.nix` exports
  `image-proxmox-dev-team`, `image-ec2-dev-team`(+`-graviton`), `image-wsl-dev-team`, and the
  aarch64 **`image-vm-dev-team` (Mac-VM qcow2)** — DISTRIBUTION gives NO `nix build` for any,
  and the Mac-VM qcow2 consumption path exists nowhere. Add a "prebuilt image outputs" table
  (artifact→attr→arch→build cmd→result) + a Mac-VM/UTM walkthrough.
- **README host tables wrong:** missing `nixos-dev-team-vm` + `nuc-apt-repo` (NixOS) and
  `powerbook` (Darwin); `mbp` mislabeled "Intel MacBook Pro/x86_64" but is an x86_64-linux
  NixOS host. Fix rows + label.

P2 (stale/incomplete):
- ARCHITECTURE stats stale: "8 NixOS hosts"→10, "1 Darwin"→2, module total→57.
- DISTRIBUTION + README CI-stage counts hardcoded ("26/14/23/3/20/6") and drift-prone — verify
  against `flake-parts/{tests,vm-tests,github-actions}.nix` or replace with "enumerated by CI".
- SHARED-MODULES "Bundle Composition" boxes drift from the export comments in `shared-modules.nix`
  (`home-dev-team` understates its contents; `home-enterprise` omits members) — reconcile.
- Darwin `system-desktop` row is meaningless on macOS — clarify what it actually configures.
- WSL-TEAM-QUICKSTART SCM section mentions only `glab`/GitLab; repo is on GitHub + ships
  `github-auth` — add `gh`.

P3 (pedagogy / approachability — the teaching-example goal):
- **No "start here" on-ramp for a Nix newcomer** (README "Who This Is For" has no learner row;
  DISTRIBUTION assumes fluency). Add an annotated tour: `flake.nix`→import-tree auto-discovery→
  dendritic `flake.modules.*`→one worked module (e.g. `programs/git`)→compose→build, linking nix.dev.
- **Dendritic pattern + `[N]`/`[D]` host-dir convention never explained** — add a "how this repo
  is wired" section / glossary (dendritic, `[N]`/`[D]`, import-tree, bundle vs feature module, RFM).
- **SHARED-MODULES has no "required config / key options" per module** — turn the name list into
  a usable API reference (option namespaces already in the export comments).
- Tarball "~1.8 GiB" size asserted without provenance — mark measured-as-of / derive from CI.

Structural / high-leverage (each kills several rows):
- **Single source of truth for counts:** emit counts from a `nix eval` over `shared-modules.nix`
  into a docs include, OR a CI lint that greps the 4 docs and fails on mismatch. Kills the 47/54/57
  problem permanently.
- **`docs/LEARNING-NIX-HERE.md`** (or README section): one real module walked end-to-end — makes
  the repo a genuine exemplar, not a reference dump.
- **Artifact-topology diagram:** `host → build output → consumer` (e.g. `nixos-dev-team-vm`→qcow2→
  Mac/UTM; `nixos-wsl-dev-team`→`.wsl`→Windows; `-graviton`→AMI→EC2) — answers "what do I build for
  my platform?" which prose can't.
- **Per-audience TOC** (README "Who This Is For") extended to all 4 audiences + every artifact shape,
  as the canonical entry other docs link back to. Plus a repo-wide **glossary**.
- **Consumption completeness matrix** `(artifact shape) × (consumption path)` — verified gaps today:
  Mac-VM qcow2 (no path), Graviton/EC2 AMI (no build+deploy), Proxmox VMA (prose-only). Filling it
  makes "how a teammate consumes this" true for EVERY artifact, not just `.wsl`.

## Cross-cutting housekeeping
- **H1 — doc refresh:** `DISTRIBUTION.md`/`SHARED-MODULES.md` to cover Mac-VM qcow2, EC2/Graviton,
  darwin exports; reconcile the 47 vs 54 module count.
- **H2 — numbering hygiene:** resolve the nixcfg-work `002` collision (archive the done
  vte-eks `002`, or renumber); note nixcfg also has a `013-L1.0-*` pair distinct from the
  archived `013-distributed-nix-binary-caching`.
- **H3 — private deployment-values overlay:** the shared modules are deliberately
  deployment-agnostic; real values live in nixcfg-work. Keep that boundary as more sharing lands.

## Progress tracking (this super-plan's OWN coordination tasks)
| ID | Task | Kind | Status |
|----|------|------|--------|
| M0 | Order the SEQUENCED milestones + define near-term "done" | Interactive | TASK:COMPLETE 2026-08-20 — order = **M-A first**, then M-B/M-D |
| M-A | Drive first Mac hardware bring-up (→ nixcfg-work 001 T7/T8b/T18b) | 1 · Mac (+ Linux prep) | TASK:IN_PROGRESS 2026-08-20 — **Linux prep DONE + re-verified 2026-08-20**; Tim has the Mac in hand, hardware step now proceeds ON the Mac (browser) per RESUME-mac-nix-bringup.md |
| M-B | Drive CI/delivery unification (→ nixcfg-work 004 T0–T5) | gated: infra/budget | TASK:PENDING |
| M-C | **STANDING** docs & consumption workstream — always-on; fill ALL blocked time (see §STANDING WORKSTREAM) | continuous | STANDING (NOT a /next-task cursor row) |
| M-D | IT/CrowdStrike compliance demo (→ nixcfg 026 T6) | Interactive: IT | TASK:PENDING |
| M-E | **NixOS 26.05 uplift + nspawn test backend (→ nixcfg 053)** — TOP-PRIORITY WSL-side; parallel to M-A | 1 · portable (053) | TASK:IN_PROGRESS 2026-08-20 — sub-plan 053 authored; next = 053 T0 (Interactive: branch + release target) |
| H1 | Refresh DISTRIBUTION.md + SHARED-MODULES.md for the new image/darwin outputs | 1 · portable | TASK:PENDING |
| H2 | Resolve plan-number collisions (nixcfg-work 002; note nixcfg 013 pair) | chore | TASK:PENDING |

## Session log 2026-08-20 (Linux-prep re-verify + Mac-materials currency review)
Tim reported the MacBook is now in hand and is taking the hardware step to the browser
ON the Mac. This session (Linux) closed out the Linux-prep half and re-reviewed every
in-tree material Tim will follow from the Mac, for currency (materials last touched
2026-08-12, pin since bumped):
- **Both darwin configs re-verified eval-green** against the current nixcfg pin (`main`
  @ `4555c15`, 2026-08-18): `corp-darwin-dev-team` → `darwin-system-26.11.6a77112.drv`,
  `pa163076mac` → real `.drv`. No regression from the plan-050 pin bump.
- **Tim's path = `pa163076mac`** confirmed fully coherent: `username = "tim"` (no
  local-username.nix needed), imports corp baseline + `mss-clamp` with `mssClamp.enable`,
  casks vlc/spotify/bitwarden/chromium, `awscli.azureAuth` ENABLED (chromium shim),
  `home-darwin`. Eval-green.
- **Materials reviewed:** `bootstrap-darwin.sh`, `docs/darwin/RESUME-mac-nix-bringup.md`,
  `docs/CORP-DARWIN-QUICKSTART.md` (all nixcfg-work, `feat/darwin-support`). All referenced
  paths exist; branch + pin claims accurate. **One accuracy defect found + fixed** (nixcfg-work
  commit `bb07290`): QUICKSTART claimed the `corp-darwin-dev-team` colleague baseline
  auto-enables `mss-clamp` — it does NOT (imports only `system-default`); only `pa163076mac`
  enables it. Corrected the doc; does not affect Tim's path.
- **Open decision for Tim (not a blocker):** should the colleague `corp-darwin-dev-team`
  baseline also import+enable `mss-clamp`? (Colleagues will hit the same VPN/hotspot MTU
  black-hole. Left as Tim's config call; darwin variant is still `[HW-VERIFY]`.)
- **M-C standing workstream:** did top P1 backlog item — module-count contradictions fixed
  across all 4 public nixcfg docs to ground truth **57 (16/32/9)** + added missing catalog rows
  (`home-wsl`/`home-darwin`/`jfrog-cli`) (nixcfg commit `93a163b`). Remaining M-C backlog
  (image-outputs table, README host tables, learner on-ramp, etc.) untouched.
- **Next concrete step is ON THE MAC:** run `bootstrap-darwin.sh --check` then activate
  `pa163076mac` per RESUME/QUICKSTART; clear `[HW-VERIFY]` flags; mark nixcfg-work 001
  T7/T8b/T18b. Linux sessions can only re-verify eval + do M-C docs (ENVIRONMENT_NOT_CAPABLE
  for the hardware step).

## ACTIVE cursor — M-A (Mac/darwin bring-up first; Tim's order 2026-08-20)
M0 is decided: **do M-A first**, then M-B/M-D. `/next-task` resumes on **M-A** (the only
IN_PROGRESS milestone; M-C is standing, not a cursor row). M-A splits into work you can do
HERE (Linux) and work that needs a Mac — start with the Linux prep so a session is never a
dead-end:
- **Linux-side prep (do now, on this host):** in `~/src/nixcfg-work`, confirm the darwin
  configs still eval-green (`corp-darwin-dev-team`, `pa163076mac`); make `bootstrap-darwin.sh`
  + `docs/darwin/RESUME-mac-nix-bringup.md` current + fully self-contained; enumerate the
  EXACT Mac-side activation steps + expected failure modes (Nix installer backup-file clash,
  primaryUser, FileVault/MDM/Rosetta `[HW-VERIFY]` flags). Detail owner = nixcfg-work **001**.
- **Mac-side (a session ON Apple Silicon):** execute the first real `darwin-rebuild switch`
  per the RESUME doc; clear the `[HW-VERIFY]` flags and mark nixcfg-work **001** T7/T8b/T18b.
- If a Linux session has finished the prep and only the hardware step remains → that is
  `ENVIRONMENT_NOT_CAPABLE` here (needs a Mac); fall to M-C docs, don't invent a workaround.

## How to resume (for the next session)
1. This is the active plan (`.claude/active-plan` → this file). Read it + the active sub-plans
   (`~/src/nixcfg-work/.claude/user-plans/001-darwin-support.md`, `004-machine-image-ci-release.md`)
   and nixcfg `026` T6.
2. **Drive M-A** (above). **M-C is ALWAYS available** as blocked-time fallback — any time M-A
   (or later M-B/M-D) blocks on a build / CI / hardware wait / pending decision, do the top
   M-C backlog item (see §STANDING WORKSTREAM); never idle-wait on a long op.
3. Do NOT put corporate detail in this file (see PUBLIC-SAFETY CONSTRAINT). Corporate work is
   tracked in nixcfg-work's plans; this file only rolls up status + sequences milestones.

## Branch strategy (decided 2026-08-20)
Darwin test/dev phase uses **symmetric feature branches** in both repos (Tim's choice):
- **nixcfg-work:** all darwin work on `feat/darwin-support` (unchanged; never `main` there —
  main is the shared personal+team base). Pins nixcfg.
- **nixcfg:** future darwin **code** lands on **`feat/darwin-support`** (created off `main`
  2026-08-20, pushed as a marker). During hardware testing, pin nixcfg-work to
  `github:timblaktu/nixcfg/feat/darwin-support`; **merge → `main` + re-pin at the milestone**
  ("MacBook boots a nix-darwin config that runs Claude natively"). No darwin *code* changed yet
  this phase, so the pin bump waits until the first darwin code commit lands on the branch.
- **Trunk stays on main:** the super-plan file, public M-C docs, and the 053 sub-plan file live
  on `main` (trunk-wide; needed for `/next-task` resumption + consumers).
- **053 (26.05) is a SEPARATE branch** `feat/nixos-26.05` (repo-wide migration, orthogonal to
  darwin) — confirm in 053 T0.

## Resumability note (2026-08-20)
Plan files (`052`, `053`, nixcfg-work `001`) are **git-tracked** → they travel on clone. The
per-worktree `.claude/HANDOFF.md` + `.claude/active-plan` are **gitignored** → they do NOT travel,
so a *native* Claude session on the Mac won't auto-rehydrate via the SessionStart hook; the
self-contained plan files are the source of truth there. Model: **WSL session = driver** (holds
live context, edits both trees, runs M-E); **Mac = M-A hardware** via claude.ai browser + the
RESUME doc, until nix-darwin gives the Mac native `claude-code`.

## Guardrails
Serialize nix. No AI attribution. Coordinating plan = human-attended (Mode A); NOT
burndown-eligible (too many Interactive / hardware / budget gates). Confirm any merge to a
`main` (either repo) with Tim; never auto-merge.
