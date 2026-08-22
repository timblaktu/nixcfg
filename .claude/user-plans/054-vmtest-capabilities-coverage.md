# Plan 054 — VMTest suite audit & refactor (nixcfg + nixcfg-work)

Status: ACTIVE (VMTest workstream; follows 053's nspawn backend enablement)
Owner: Tim
Created: 2026-08-20
Parent: `.claude/user-plans/052-dev-team-sharing-superplan.md` (M-E testing family; enabler for M-B CI)
Working branch: **`feat/vmtest-refactor`** (created 2026-08-20 from `main`; all refactor work lands here,
merge→main at completion). Decided by Tim.

## Goal (reframed 2026-08-20 — Tim)
NOT "add tests to raise host coverage." The goal is to **fully analyze the tests we already have —
focusing on actual CODE / FEATURE coverage, not just host coverage — and refactor everything (nothing
is sacred) toward a single cohesive, effective set of NixOS VMTests built from BOTH `nodes` (QEMU) and
`containers` (nspawn) constructs.** Deleting, merging, and rewriting existing tests is in scope.
Per-host smoke and QEMU→nspawn migration are *outcomes* of the analysis, not the objective.

## Method — phased (analysis before surgery)
- **P1 Parallel audit (inventory + coverage map):** enumerate EVERY check across both repos, record
  what each actually asserts, AND map tests → the modules/features they exercise — surfacing which
  features are well-covered, thinly-covered, untested, or only eval-gated, plus redundancy and weak
  tests. This is the heart, and it is run as a multi-agent Workflow (see P1 task def).
- **P2 Audit review & roadmap sign-off (Interactive gate):** Tim reviews `docs/VMTEST-AUDIT.md`, confirms
  or corrects the findings (gaps / redundancies / weak / backend-fit), and signs off on (or revises) the
  roadmap and sequence of P3-P6 BEFORE any per-test work begins. This is a deliberate checkpoint: the
  audit's conclusions and the assumed downstream plan are not treated as settled until Tim agrees.
- **P3 Assessment + backend deep-dive + nixcfg-work Tier-A audit (Interactive):** (a) EXTEND the audit
  into `nixcfg-work` Tier-A hosts (`pa161878-nixos`, macbook) — P1 covered nixcfg only, but the daily
  drivers live in nixcfg-work; (b) the deferred **interactive backend-fit review** (per-test node vs
  container vs eval-only/drop) that encodes **per-host testability classes** (darwin = eval+build+shared-
  module-on-Linux-proxy; WSL = eval+layer; bare Linux = full QEMU boot on KVM); (c) confirm the exact
  Tier-0 consolidation list (which `eval-*` collapse into `regression-test`, keeping `eval-nixos-wsl-dev-team`).
  "Nothing is sacred."
- **P4 Target design (Interactive):** the redesigned **2-tier** suite — Tier 0 (consolidated eval-regression
  gate) + Tier 1 (behavioral node/container VMTests), Tier-A hosts first — keep/merge/rewrite/drop/add with
  backend assignment + rationale. Bakes in the already-decided deletions/renames. Agreed with Tim before execution.
- **P5 Execute (split into P5a/P5b/P5c — Tim, 2026-08-21):** implement the agreed design
  (`docs/VMTEST-TARGET-DESIGN.md`) in three de-risked sub-steps. **P5a** = Tier-0 eval-regression
  consolidation (pure eval, low-risk, single `nix flake check --no-build` gate): expand `regression-test`,
  create `eval-hm-modules` + `eval-nixos-modules`, rename the 8 `build-*-dryrun`, merge the SSH-2223 triple,
  delete the no-ops, rewrite the 3 salvage checks. **P5b** = nspawn-fidelity SPIKE (own step, before the
  bulk migration): prove `mkContainerTest` can host HM activation + sops-nix activation (+ multi-node
  isolation) so P5c's backend assignments are evidence-based, not assumed. **P5c** = Tier-1 behavioral
  refactor (dep P5b): delete the 2 mocks, drop `vm-yazi`, merge the two stacks → `vm-compose-stack`, migrate
  the boot-independent tests to nspawn per the spike findings, add `vm-wsl-dev-team-layers`.
- **P6 CI + nixcfg-work:** wire the redesigned suite onto the KVM runners (both arches; QEMU node tests are
  first-class in CI, nspawn an opt-in speedup) and carry the cohesive approach into nixcfg-work's corp hosts.
- **P7 Backlog (deferred):** `nuc-apt-repo` (aptly-repo + apt-cacher-ng), `mss-clamp`, enterprise/
  wsl-enterprise layers, `jfrog-cli`/`monitoring`, darwin sample hosts, and a real (non-mock)
  rbw→SSH-key-deploy secrets-management test.

## Task definitions

### P1 — Parallel test-suite audit `TASK:COMPLETE 2026-08-21` (run as a multi-agent Workflow — Tim opted in)
**Execute this as a `Workflow` (multi-agent), not inline.** Tim has explicitly authorized the parallel
audit; the whole-suite scope (100+ checks across both repos, cross-referenced against ~57 modules)
is exactly the decompose-and-cover-in-parallel case.

Shape of the workflow:
1. **Discover** the full check set: `nix eval '.#checks.<sys>' --apply builtins.attrNames` for nixcfg
   AND nixcfg-work (both x86_64-linux and aarch64-linux); list `tests/`, `modules/flake-parts/
   {tests,vm-tests}.nix`, `tests/integration/*`, and the module tree (`modules/**` → the ~57 exported
   modules).
2. **Fan out** (pipeline/parallel): one agent per test-file group / check family — each returns, per
   check: name, backend (`nodes`/QEMU vs `containers`/nspawn vs `runCommand`/eval vs lint), what it
   asserts (concrete), and which module(s)/feature(s) it exercises. In parallel, agents walk the module
   tree and report, per module/feature: is it touched by any test, and how deeply.
3. **Synthesize** (barrier): merge into (a) a full **inventory table** (check → backend → asserts →
   modules touched) and (b) a **feature/code coverage map** (module/feature → covering tests → depth:
   well / thin / eval-only / untested), with explicit **gaps**, **redundancies** (N tests covering the
   same thing), and **weak tests** (trivial/tautological assertions) flagged.
4. **Adversarially verify** a sample of the "untested"/"redundant" claims before trusting them (a
   feature marked untested may be covered indirectly; a "redundant" pair may differ subtly).

Feed the inputs already gathered (nspawn caveats, full-host conflict cascade, host classification —
below). **DoD:** a durable audit artifact **`docs/VMTEST-AUDIT.md`** exists containing the inventory
table + the feature-coverage map + flagged gaps/redundancies/weak-tests; `nix eval` discovery commands
are recorded so the audit is reproducible. No test is judged in isolation without noting the
module/feature it maps to.

### P2 — Audit review & roadmap sign-off `TASK:COMPLETE 2026-08-21` (Interactive gate — dep P1)
**Interactive.** Injected at Tim's request (2026-08-21): before any per-test assessment, Tim wants to
review the audit and confirm he is happy with the findings and the assumed sequence of downstream tasks.
`/next-task` on this task yields USER_INPUT_REQUIRED — it must be run interactively.

What this task covers (a collaborative working session over `docs/VMTEST-AUDIT.md`):
1. **Walk the findings** — the four analysis sections (Gaps, Redundancies, Weak/trivial, Backend-fit) and
   the Verification-notes table. Claude presents each; Tim accepts / rejects / annotates. Anything Tim
   disputes gets re-checked against the code on the spot (don't defend a finding — verify it).
2. **Settle the framing decisions that gate everything downstream**, e.g.: is "nothing is sacred" still
   the operating principle, or are specific checks/areas off-limits? Is `nuc-apt-repo` (aptly-repo +
   apt-cacher-ng) confirmed as the priority new-coverage target? Do we consolidate the redundant `eval-*`
   family into `regression-test` (and if so, how do we preserve `eval-nixos-wsl-dev-team`)? Is the
   node-vs-nspawn split policy agreed? Scope: nixcfg only first, or nixcfg + nixcfg-work together?
3. **Confirm or revise the roadmap** — the P3→P6 sequence (per-test assessment → target design → execute →
   CI/nixcfg-work). Tim may reorder, split, merge, or add tasks here. If the sequence changes, update this
   plan's Method section + progress table before P3 begins.

**DoD:** a short **"P2 review decisions"** subsection is appended to this plan's Session log capturing:
(a) which audit findings Tim accepted / rejected / amended, (b) the settled framing decisions from step 2,
and (c) the confirmed-or-revised P3-P6 roadmap. No code changes. P3 does not start until this is recorded
and Tim has signed off.

### P5a — Tier-0 eval-regression consolidation `TASK:COMPLETE 2026-08-21` (dep P4 — COMPLETE)
Portable, **eval-only, no boot** — the low-risk half of the execution. Source of truth for every change:
`docs/VMTEST-TARGET-DESIGN.md` §T0.1-T0.9. Edits `modules/flake-parts/tests.nix` only. Do it in this order,
`nix flake check --no-build` after each group (idempotent: check-before-edit; a resumed run converges):
1. **Expand `regression-test`** (T0.1 + folded `config-snapshot-validation`): add `nixos-wsl-dev-team`
   `system.stateVersion`; add `home.username` for the 4 HM configs (parity); add the
   `stateVersion == "24.11"` equality assertions for thinky-nixos/potato/nixos-wsl-minimal/mbp.
2. **Create `eval-hm-modules`** (T0.2) folding all **20** `eval-hm-module-*`; **create `eval-nixos-modules`**
   (T0.3) folding the **6** `eval-nixos-module-*` (per-layer `extraConfig` as noted).
3. **Rename** the 8 `build-*-dryrun` → `eval-*-toplevel`/`-tarball`/`eval-images-*` (T0.4), preserving their
   `hasProxmox`/`hasAmazon` asserts.
4. **Merge the SSH-2223 triple** (T0.5): `ssh-service-configured` + `cross-module-wsl-base` +
   `module-wsl-settings-integration` → one `eval-wsl-settings-*` check keeping the openssh-port==sshPort and
   userName==defaultUser invariants.
5. **Delete** the 12 standalone host/config evals (folded into regression-test), the 20 `eval-hm-module-*`,
   the 6 `eval-nixos-module-*`, and the no-ops: `flake-validation`, `validated-scripts-module`,
   `ssh-public-keys-registry`, `opencode-config-validation`, `cross-module-home-manager`,
   `cross-module-sops-base`, `config-snapshot-validation`, `unified-files-diagnostic-test`,
   `hybrid-files-module-test`.
6. **Rewrite to actually assert**: `tmux-picker-syntax` (run `bash -n` on the picker), `module-base-integration`
   (assert `userGroups`, keep `userName`), `files-module-test` (assert one real generated `home.file` exists
   with expected content). Add `activate-hm-nixvim-minimal` (T0.7, build-tier).
**DoD (checkable):** `nix flake check --no-build` exits 0. `nix eval '.#checks.x86_64-linux' --apply
builtins.attrNames` shows: **GONE** = the 12 standalone evals + 20 `eval-hm-module-*` + 6
`eval-nixos-module-*` + the 9 no-ops + the 3 old SSH-2223 names + the 8 old `build-*-dryrun` names; **PRESENT**
= `eval-hm-modules`, `eval-nixos-modules`, the 8 `eval-*-toplevel/-tarball/eval-images-*`, one
`eval-wsl-settings-*`, and `tmux-picker-syntax`/`module-base-integration`/`files-module-test` still present.
Net check count drops from 106 to ~59 (exact delta reconciled during execution; the named GONE/PRESENT lists
are the real gate, not the absolute number). x86_64 and aarch64 attrName sets remain mirrored. Committed.

### P5b — nspawn-fidelity spike `TASK:COMPLETE 2026-08-21` (dep P4 — COMPLETE; MUST precede P5c)
"Verify before migrating." A short, throwaway-friendly proof that `mkContainerTest` (nspawn, 053 T6) can host
the three semantics P5c wants to move off QEMU. Add temporary spike checks (may be removed/absorbed in P5c):
(i) **HM activation** — a container that reaches `home-manager-<user>.service` and finds one generated
`home.file`; (ii) **sops-nix activation** — a container where a checked-in fixture secret is decrypted to
`/run/secrets` with the expected mode/owner (mirror the `vm-sops-secrets` fixture path); (iii) **multi-node
isolation** — two containers via `start_all` (stand-in for `vm-hm-composition-pairs`/`-module-isolation`).
**DoD (checkable):** each of the three either **builds+passes** under `nix build '.#checks.<sys>.<spike>'`
(→ that semantic is nspawn-safe) **or** produces a recorded, specific failure. Append a **"P5b spike findings"**
subsection to this plan's Session log stating, per semantic, nspawn-OK vs must-stay-QEMU + the evidence.
Those findings become P5c's authoritative backend map (overriding any `N?` guess in the design doc). Needs a
KVM/nspawn-capable builder (present on `pa161878-nixos`); on an incapable host → ENVIRONMENT_NOT_CAPABLE.

### P5c — Tier-1 behavioral refactor `TASK:PENDING` (dep P5b)
Edits `modules/flake-parts/vm-tests.nix` + deletes `tests/integration/{ssh-management,sops-deployment}.nix`.
Backend per each test = the **P5b findings** (not the design doc's `N?` guesses). Steps (idempotent):
1. **Delete** `vm-ssh-management` + `vm-sops-deployment` and their two `tests/integration/*.nix` files.
2. **Drop `vm-yazi`**, folding its `init.lua`+`keymap.toml` existence asserts into `vm-hm-module-isolation`'s
   yazi node.
3. **Merge** `vm-full-cli-stack` + `vm-dev-team-stack` → one parameterized `vm-compose-stack` (param =
   `system-cli` layer vs real `nixos-dev-team` host module with grub/disk forced off, `/`=tmpfs); union of
   asserts runs per parameterization.
4. **Migrate to nspawn** every test P5b proved safe (candidates: `vm-system-type-default`, `vm-user-config`,
   `vm-shell-env`, `vm-development-tools`, `vm-git-advanced`, `vm-neovim`, `vm-tmux`, `vm-hm-activation`,
   `vm-hm-composition-pairs`, `vm-hm-module-isolation`, `vm-sops-secrets`, `vm-compose-stack`); rewrite any
   `sshd.service` assert to the socket form. **Keep QEMU**: `vm-boot-minimal`, `vm-system-type-cli`,
   `vm-system-type-desktop`, `vm-nspawn-smoke`, `vm-ssh-service`, `vm-dev-team-vm-smoketest`.
   **⚠ CORRECTED BY P5b FINDINGS (see "P5b spike findings"):** NixOS-integrated HM-activation tests
   FAIL under nspawn (in-container nix-daemon cannot chown the shared `/nix/store`), so of the list above
   ONLY `vm-sops-secrets` migrates to nspawn; **`vm-shell-env`, `vm-development-tools`, `vm-git-advanced`,
   `vm-neovim`, `vm-tmux`, `vm-hm-activation`, `vm-hm-composition-pairs`, `vm-hm-module-isolation`,
   `vm-user-config` STAY ON QEMU** (they reach `home-manager-<user>.service`). Any multi-node test that
   DOES move to nspawn must use hostname-valid node names (no underscores). Do NOT attempt a store/daemon
   workaround to force HM tests onto nspawn — that is out of scope.
5. **Add `vm-wsl-dev-team-layers`** (nspawn): compose `system-cli + wsl-dev-team + wsl-enterprise` +
   `monitoring` + `mss-clamp` — first behavioral coverage of `monitoring`/`mss-clamp` (the Tier-A WSL stack).
**DoD (checkable):** `nix flake check --no-build` exits 0. attrNames show: **GONE** = `vm-ssh-management`,
`vm-sops-deployment`, `vm-yazi`, `vm-full-cli-stack`, `vm-dev-team-stack`; **PRESENT** = `vm-compose-stack`,
`vm-wsl-dev-team-layers`. The two `tests/integration/*.nix` files no longer exist. The retained-QEMU set is
unchanged. Representative build-verify (heavy full-suite VM builds are CI/P6, not this DoD): `nix build
'.#checks.x86_64-linux.vm-nspawn-smoke'` passes AND at least one newly-migrated nspawn test builds+passes.
Committed. Needs KVM/nspawn builder → else ENVIRONMENT_NOT_CAPABLE.

## Progress tracking
| ID | Task | Kind | Status |
|----|------|------|--------|
| P0 | Decide working branch | Interactive | TASK:COMPLETE 2026-08-20 — `feat/vmtest-refactor` (created from main) |
| P1 | **Parallel test-suite audit** — inventory + feature/code coverage map (run as a multi-agent Workflow) | 1 · analysis (workflow) | TASK:COMPLETE 2026-08-21 — `docs/VMTEST-AUDIT.md` (all 106 checks + 65 coverage rows + gaps/redundancies/weak + adversarial verification) |
| P2 | **Audit review & roadmap sign-off** — review findings + confirm/revise P3-P6 sequence | Interactive (gate) | TASK:COMPLETE 2026-08-21 — findings dispositioned, 2-tier priority + both-repos/CI-first framing settled, roadmap revised to P3-P7 (see "P2 review decisions") |
| P3 | Assessment + interactive backend-fit review + **nixcfg-work Tier-A host audit** (nothing sacred) | Interactive (collaborative) | TASK:COMPLETE 2026-08-21 — nixcfg-work Tier-A audit in VMTEST-AUDIT.md; backend=aggressive-nspawn; renames=both; Tier-0=12-host collapse (add nixos-wsl-dev-team); eval-hm-module-*=consolidate (see "P3 decisions") |
| P4 | Target suite design (2-tier) — keep/merge/rewrite/drop/add + backend + rationale | Interactive (collaborative) | TASK:COMPLETE 2026-08-21 — `docs/VMTEST-TARGET-DESIGN.md` (AGREED); Q1-Q4 signed off (see "P4 decisions") |
| P5a | Tier-0 eval-regression consolidation (batch evals, renames, no-op deletions, 3 rewrites) | 1 · portable (eval-only) | TASK:COMPLETE 2026-08-21 — 106→60 checks (x86/aarch64 mirrored); flake check --no-build exit 0; 3 rewrites + 4 new/merged gates build+pass (see "P5a execution") |
| P5b | nspawn-fidelity spike (prove HM-activation + sops-nix + multi-node isolation under `mkContainerTest`) | 1 · builder (KVM/nspawn) | TASK:COMPLETE 2026-08-21 — sops-nix + multi-node = nspawn-OK (build+pass); HM-activation = must-stay-QEMU (recorded daemon/store failure); 3 spike checks in vm-tests.nix (see "P5b spike findings") |
| P5c | Tier-1 behavioral refactor (drop mocks/vm-yazi, merge stacks→`vm-compose-stack`, nspawn migrations, add `vm-wsl-dev-team-layers`) | 1 · builder (KVM/nspawn) | TASK:PENDING (dep P5b) |
| P6 | CI wiring (KVM runners, both arches) + carry into nixcfg-work corp hosts | 1 · CI / nixcfg-work | TASK:PENDING (dep P5a, P5c) |
| P7 | Backlog — deferred Tier-B coverage (nuc-apt-repo, mss-clamp, enterprise, jfrog/monitoring, darwin, real rbw test) | 1 · deferred | TASK:PENDING (dep P4) |

## Inputs already gathered this session (feed P1-P4)
- **Backend capability (053 T6, DONE):** `mkVmTest` (QEMU) + `mkContainerTest` (nspawn, proven,
  daemon-path verified, ~5-7× faster). Guide + caveats in `docs/TESTING-NSPAWN.md` (service-unit
  differences e.g. `sshd.socket` not `sshd.service`; networking; fidelity limits).
- **Current surface (nixcfg):** 22 `vm-*` tests, all composing MODULES not host configs; plus
  `eval-*`, `build-*-dryrun`, integration (`tests/integration/*`), unit (`tests/{sops-*,ssh-*}`),
  `cross-module-*`, `module-*-integration`, `lint-*`, `skill-injection-*`. Full enumeration = P1.
- **Full-host-in-container = conflict cascade** (`nixpkgs.hostPlatform` read-only + `systemd-resolved`
  assertion + more) — so host-level tests are layer+settings compositions or QEMU, not literal hosts.
- **Host classification (see table below):** most per-host container smoke would be REDUNDANT with
  existing layer tests; the one clear untested feature-set is **`nuc-apt-repo`** (aptly + apt-cacher-ng).
  This is a P3/P4 input, not a standalone task anymore.
- **nixcfg-work:** ~zero VMTests of its own (re-exports 1 nixcfg check); nixpkgs `331800d` has nspawn;
  container tests there couple with T8b (pin bump → 26.05 uplift) unless done self-contained.

### Host classification (2026-08-20) — feature-coverage lens
| Host | Distinct runtime content | Already covered by | Note |
|---|---|---|---|
| **nuc-apt-repo** | `aptly-repo` + `apt-cacher-ng` (UNIQUE services) | nothing | real feature gap |
| nixos-dev-team | `dev-team` layer | `vm-dev-team-stack` | layer covered |
| nixos-dev-team-ec2/-graviton/-vm | dev-team + image | layer + image-build checks (+ `vm-dev-team-vm-smoketest`) | image=build/boot |
| nixos-wsl-dev-team / -minimal | WSL | `Test-WslImport.ps1` (shipped image) | WSL=image test |
| potato | `system-default` (aarch64 SBC) | `vm-system-type-default` | HW=real SBC |
| mbp | `system-cli` | `vm-system-type-cli` | layer covered |
| thinky-nixos | personal + WSL | (personal) | skip / WSL image |

## Guardrails
Serialize nix. No AI attribution. Analysis + sign-off (P1-P4) before any deletion/rewrite (P5). Container tests need the
nspawn nix config on the builder (053 T6). nixcfg-work container work couples with T8b unless
self-contained. Confirm any merge to `main` / nixcfg-work pin bump with Tim. "Nothing is sacred" means
tests CAN be dropped/rewritten — but only with a recorded rationale (P4/P5), never silently.

## Session log
- 2026-08-20 (authoring + reframe): created after 053 T6. Probed full-host-in-container → conflict
  cascade. Tim first picked per-host smoke (#3) + review-then-migrate (#1), then **reframed the whole
  effort**: not coverage-adding but a full AUDIT + REFACTOR of the VMTest suite around code/feature
  coverage, nothing sacred, both nodes+containers. Restructured the plan into phases. Then Tim: run the
  thorough audit via `/next-task` as a PARALLEL WORKFLOW, on a NEW branch. Actions: created
  `feat/vmtest-refactor` (P0 COMPLETE); folded inventory + coverage-map into a single **P1
  parallel-audit Workflow task** (first PENDING → `/next-task` starts there); renumbered P2-P5. Next
  session: `/next-task` runs the P1 audit workflow → produces `docs/VMTEST-AUDIT.md`.
- 2026-08-21 (P1 DONE): ran the audit as a 25-agent Workflow (9 check-family + 2 module-walk fan-out →
  synthesize → 12 adversarial verifiers → finalize). Produced **`docs/VMTEST-AUDIT.md`**: all 106 checks
  inventoried (backend/asserts/modules/depth/weakness), 65-row feature-coverage map, plus derived Gaps,
  Redundancies, Weak-tests, and Backend-fit sections + a Verification-notes table (9 confirmed, 3 partial,
  0 refuted — partials corrected in-place). Discovery reproducible: nixcfg = 106 checks (mirrored x86_64/
  aarch64); nixcfg-work = 1 re-exported check. **Headline findings feeding P2 review / P3-P4:**
  (a) **Real gap:** `nuc-apt-repo` host + its unique `aptly-repo`/`apt-cacher-ng` services = ZERO coverage
      (highest-value new-test target); also `jfrog-cli`/`monitoring`/`mss-clamp` wired-but-untested,
      darwin outputs untested, dev-shells never built, auth-helpers + many program modules eval-only.
  (b) **Redundancy:** ~12 `eval-*`/`eval-hm-*` checks largely subsumed by `regression-test` + the
      `*-dryrun` toplevel forcers + `config-snapshot-validation` (but `eval-nixos-wsl-dev-team` is NOT in
      regression-test — don't drop it blindly); triple SSH-port-2223 asserts; mock-vs-real pairs
      (`vm-ssh-management`↔`vm-ssh-service`, `vm-sops-deployment`↔`vm-sops-secrets`); `vm-yazi`↔isolation.
  (c) **Weak/tautological:** `flake-validation`, `validated-scripts-module`, `ssh-public-keys-registry`,
      `files-module-test`, `unified-files-diagnostic-test`, `opencode-config-validation`, `tmux-picker-syntax`,
      `cross-module-sops-base`, `module-base-integration` — echo/touch or self-referential asserts.
  (d) **Backend-fit:** `build-*-dryrun` are eval-forcers misnamed `build-*`; `ssh-service-configured` is an
      eval not a service test; `vm-nspawn-smoke` is the one intentional nspawn twin; aptly/apt-cacher-ng
      want real nspawn/QEMU. Next: **P2 (Interactive gate, injected 2026-08-21 at Tim's request)** —
      review these findings + confirm/revise the P3-P6 roadmap before per-test assessment (P3) begins.

### P2 review decisions (2026-08-21) — Tim signed off

**(a) Audit findings — accepted / amended.** Walked all four analysis sections one-by-one:
- **Gaps:** accepted as accurate, but RE-PRIORITIZED. The Tier-B gaps (`nuc-apt-repo`, `mss-clamp`,
  enterprise/wsl-enterprise, `jfrog-cli`/`monitoring`, darwin samples) are parked as backlog (P7). The
  `nuc-apt-repo` "highest-value target" call from P1 is OVERRIDDEN — that host was never really used.
  The active gap is now "Tier-A shipped/daily-driver hosts lack *behavioral* coverage."
- **Redundancies:** accepted. Confirmed by reading the code that the two mock/real pairs mock our
  modules rather than exercise them (`vm-ssh-management` comment literally "simulate ... without importing
  them" + mock `rbw` + never completes a real login; `vm-sops-deployment` hand-drives sops/age CLIs,
  never imports `secrets-management`). DECISION: **drop both mocks** (`vm-ssh-management`,
  `vm-sops-deployment`, and their `tests/integration/*.nix`), keep the real twins (`vm-ssh-service`,
  `vm-sops-secrets`). Also merge the SSH-2223 triple; drop `eval-*` dominated by `*-dryrun`.
- **Weak/trivial:** accepted. Delete or rewrite-to-assert the no-ops (`flake-validation`,
  `validated-scripts-module`, `ssh-public-keys-registry`, `files-module-test`,
  `opencode-config-validation`); fix `tmux-picker-syntax` to actually run `bash -n`. Recorded rationale each.
- **Backend-fit:** accepted the renames in principle (`build-*-dryrun`→`eval-*-toplevel`; rename
  `ssh-service-configured` to reflect it is an eval; keep `vm-nspawn-smoke` as the nspawn reference), but
  Tim wants a **dedicated interactive backend-fit review** — MOVED into P3.

**(b) Framing decisions settled.**
1. **"Nothing is sacred" still fully in effect** — deletions/rewrites allowed with recorded rationale.
2. **Scope = BOTH repos (nixcfg + nixcfg-work), CI-first.** The suites will run on existing nix-capable,
   **KVM-enabled runners on both arches** → QEMU `nodes` tests are first-class in CI (not just local);
   nspawn is an opt-in speedup, not a CI necessity.
3. **eval-* = "nix checks, not tests" (Tim's framing).** Collapse the ~12 redundant `eval-*`/`eval-hm-*`
   into `regression-test` as a **Tier-0 eval-regression gate** (preserve `eval-nixos-wsl-dev-team`, which
   `regression-test` does NOT currently force). The "VMTest suite" refactor targets the **behavioral**
   (node/container) tier.
4. **2-tier host priority (only two tiers).**
   - **Tier A (do first):** daily drivers `pa161878-nixos` + macbook (BOTH in nixcfg-work) + ALL dev-team
     image hosts (`nixos-dev-team`/`-ec2`/`-graviton`/`-vm`) + ALL WSL images (`nixos-wsl-dev-team`/
     `-minimal`) + the dev-team shared images.
   - **Tier B:** thinky-nixos, `mbp`, `potato`, `nuc-apt-repo`, enterprise layers, darwin sample hosts.
5. **Per-host testability classes** (VMTests boot Linux NixOS only): darwin macbook = eval + build-dryrun
   + shared-module-on-Linux-proxy (macOS can't run on KVM Linux runners); WSL hosts = eval + layer
   composition; bare Linux hosts = full QEMU boot on KVM.
6. **Structural consequence:** P1 audited nixcfg only; the Tier-A daily drivers live in `nixcfg-work`,
   which was NOT audited → P3 must extend the audit there.

**(c) Roadmap — confirmed/revised (P3-P7).** P3 gains the nixcfg-work Tier-A audit + the deferred
interactive backend-fit review + the Tier-0 consolidation-list confirmation; P4 designs the 2-tier suite;
P5 executes (deletions/renames/consolidations/new Tier-1 tests); P6 wires CI on KVM runners both arches +
nixcfg-work; **new P7** holds the deferred Tier-B backlog. Method section + progress table updated to match.
No code changed in P2.

### P3 decisions (2026-08-21) — Tim signed off

**(a) nixcfg-work Tier-A audit — DONE** (durable artifact: new "nixcfg-work Tier-A audit" section appended
to `docs/VMTEST-AUDIT.md`). Findings that drive P4/P5:
- **nixcfg-work has ZERO test infrastructure** — no `checks` of its own; re-exports exactly one nixcfg
  check (`vm-dev-team-vm-smoketest`, aarch64). Both Tier-A daily drivers are entirely unverified.
- **`pa161878-nixos` (WSL, daily driver)** imports `wsl-dev-team -> wsl-enterprise -> system-cli + wsl`
  + `monitoring` + `mss-clamp`. It is the ONLY real consumer of `monitoring` **and** `mss-clamp` — the two
  modules the nixcfg audit flagged as zero-coverage "dead-until-wired." They are live-but-unguarded here.
  Testability class = **eval + layer composition** (WSL cannot boot on KVM).
- **`pa163076mac` (Darwin, "macbook", daily driver)** — HM `corp-dev-team + home-darwin + tim-corp-personal`.
  Testability class = **eval + build-dryrun + shared-module-on-Linux-proxy** (macOS cannot boot on KVM).
- **Correction to nixcfg audit:** `modules/lib/rbw.nix` (rbw) is consumed by BOTH daily drivers (WSL via
  `awscli`, and Darwin), not darwin-only. Corp HM bundles (`corp-dev-team`, `tim-corp-personal`) are the
  real Tier-A HM surface and are wholly untested.

**(b) Backend policy = AGGRESSIVE nspawn migration.** Migrate boot-independent QEMU `node` tests to nspawn
(~5-7x speedup); keep QEMU only for tests asserting genuine boot/kernel/hardware/systemd-target semantics.
`vm-nspawn-smoke` stays the nspawn reference; its `sshd.socket`-not-`sshd.service` finding is the fidelity
rule for what can move. P4 will tag each behavioral test node-vs-container with rationale. (This sharpens
the P2 "nspawn is an opt-in speedup" into a default-to-nspawn-where-safe policy; QEMU remains first-class
in CI for the boot tests.)

**(c) Renames = APPLY BOTH sets in P5.** `build-*-dryrun` -> `eval-*-toplevel` (they force eval, never
build); `ssh-service-configured` -> an eval-named check reflecting it is an option-value eval, not a
service test (it also folds into the SSH-2223 consolidation).

**(d) Tier-0 consolidation list — CONFIRMED.** Collapse these **12 host/config evals** into `regression-test`
(the single Tier-0 eval-regression gate): the 7 already-forced NixOS host evals (`eval-thinky-nixos`,
`eval-potato`, `eval-mbp`, `eval-nixos-wsl-minimal`, `eval-nixos-dev-team`, `eval-nixos-dev-team-ec2`,
`eval-nixos-dev-team-graviton`), the 4 HM config evals (`eval-hm-thinky-nixos`, `eval-hm-thinky-ubuntu`,
`eval-hm-mbp`, `eval-hm-nixvim-minimal`), PLUS `eval-nixos-wsl-dev-team` — which is NOT currently in
regression-test's forced list, so P5 first ADDS `nixos-wsl-dev-team.config.system.stateVersion` (and
`home.username` for HM parity) to regression-test's inherited attrs, THEN drops the standalone. This is
pure eval batching (no runtime/WSL boot); zero coverage loss.

**(e) eval-hm-module-* (20 isolation evals) = CONSOLIDATE into ONE multi-module eval gate.** Same coverage
(every HM module forced to evaluate standalone — the property that catches breakage in modules no tested
host enables, e.g. corp-only modules), far less boilerplate, matches the regression-test batching approach.
Nix names the broken module on failure. Not dropped per-module.

P3 outputs feed P4 (2-tier target design): Tier 0 = `regression-test` (12-host+HM batch) + the consolidated
multi-module HM eval + the renamed `eval-*-toplevel` forcers; Tier 1 = behavioral node/container tests,
default-to-nspawn-where-boot-independent, Tier-A hosts first (WSL/Darwin daily drivers get eval+layer+
build-dryrun coverage since they can't QEMU-boot).

### P4 decisions (2026-08-21) — Tim signed off

Durable artifact: **`docs/VMTEST-TARGET-DESIGN.md`** (status AGREED) — the full 2-tier keep/merge/rewrite/
drop/add table with backend + rationale per check, baking in all P2+P3 decisions. `/next-task` on P4
correctly yielded USER_INPUT_REQUIRED; the four open design choices were resolved interactively:

- **Q1 (sops backend):** MIGRATE `vm-sops-secrets` to nspawn, with a P5 fidelity verification of the
  sops-nix activation path; fall back to QEMU only if that verification fails.
- **Q2 (compose-test consolidation):** DROP `vm-yazi` (fold its `init.lua`/`keymap.toml` asserts into
  `vm-hm-module-isolation`'s yazi node) AND MERGE `vm-full-cli-stack` + `vm-dev-team-stack` into one
  parameterized `vm-compose-stack` (param = `system-cli` layer vs real `nixos-dev-team` host module).
- **Q3 (weak tests):** delete the no-ops (`flake-validation`, `validated-scripts-module`,
  `ssh-public-keys-registry`, `opencode-config-validation`, `cross-module-home-manager`,
  `cross-module-sops-base`) + 2 of 3 files-family; SALVAGE `files-module-test` into one genuine files-module
  assertion; rewrite `tmux-picker-syntax` (`bash -n`) + `module-base-integration` (`userGroups`); fold
  `config-snapshot-validation`'s `stateVersion=="24.11"` into `regression-test`.
- **Q4 (NixOS layer evals):** CONSOLIDATE the 6 `eval-nixos-module-*` into one `eval-nixos-modules` gate
  (mirrors the HM 20→1), per-layer assertion setup carried as per-module `extraConfig`.

**Net target:** Tier 0 = ~4 batched eval gates + 8 renamed toplevel/tarball/image forcers + kept
builds/lints (−~7 weak checks, 3 rewritten). Tier 1 = 22 `vm-*` → 17 (drop 2 mocks + `vm-yazi`, merge 2
stacks→1, add `vm-wsl-dev-team-layers` for the WSL daily-driver layer stack incl. first behavioral
`monitoring`/`mss-clamp` coverage), majority migrated QEMU→nspawn. QEMU retained for boot (`vm-boot-minimal`,
`vm-system-type-cli`), graphics (`vm-system-type-desktop`), real cross-node SSH (`vm-ssh-service`), and the
shipped-image gate (`vm-dev-team-vm-smoketest`, re-exported into nixcfg-work CI). No coverage dropped
silently — see the design doc's "Coverage-preservation ledger". P5 executes this; no code changed in P4.

### P5a execution (2026-08-21) — DONE

Implemented `docs/VMTEST-TARGET-DESIGN.md` §T0 in `modules/flake-parts/tests.nix` (single file, eval-only). Net
check count **106 → 60** (x86_64 and aarch64 attrName sets verified mirrored). `nix flake check --no-build`
exits 0; the 3 rewrites + 4 new/merged eval gates + the 2 new activation tests all `nix build` and pass
(built explicitly since `--no-build` skips check bodies).

- **Expanded `regression-test` (T0.1):** added `nixos-wsl-dev-team` stateVersion, `home.username` for all 4 HM
  configs (parity with folded eval-hm-* checks), and folded `config-snapshot-validation`'s
  `stateVersion == "24.11"` equality asserts for thinky-nixos/potato/nixos-wsl-minimal/mbp.
- **New `eval-hm-modules` (T0.2):** one gate folding all 20 `eval-hm-module-*`. **New `eval-nixos-modules`
  (T0.3):** one gate folding the 6 `eval-nixos-module-*` (per-layer `extraConfig` preserved verbatim).
  Implemented via inlined `forceHmModuleEval` / `forceNixosModuleEval` helpers (`lib.mapAttrsToList` over a
  module attrset; referencing each config's homeDirectory/stateVersion forces standalone eval).
- **Renamed 8 `build-*-dryrun`** → `eval-thinky-nixos-toplevel`, `eval-nixos-wsl-minimal-toplevel`,
  `eval-nixos-dev-team-toplevel`, `eval-nixos-wsl-dev-team-tarball`, `eval-thinky-nixos-tarball`,
  `eval-images-dev-team`, `eval-images-ec2`, `eval-images-graviton` (T0.4). `hasProxmox`/`hasAmazon` asserts kept.
- **Merged SSH-2223 triple (T0.5)** → `eval-wsl-settings-ssh-port`, keeping openssh-port==sshPort and
  base-userName==wsl-defaultUser invariants (+ ssh-enabled / port-2223 / wsl-enabled / hostname guards).
- **Deleted:** 12 standalone host/config evals, 20 `eval-hm-module-*`, 6 `eval-nixos-module-*`, and the 9 no-ops
  (`flake-validation`, `validated-scripts-module`, `ssh-public-keys-registry`, `opencode-config-validation`,
  `cross-module-home-manager`, `cross-module-sops-base`, `config-snapshot-validation`,
  `unified-files-diagnostic-test`, `hybrid-files-module-test`). Removed the now-unused
  `mkEvalTest`/`mkHmEvalTest`/`mkHmModuleEvalTest`/`mkNixosModuleEvalTest`/`snapshotBaseline` helpers (else
  `lint-deadnix` fails).
- **Rewrote to actually assert:** `tmux-picker-syntax` (now runs `bash -n` on the picker),
  `module-base-integration` (asserts `systemDefault.userGroups` contains `wheel`, keeps `userName`),
  `files-module-test` (builds an HM config using the files module's `staticFiles` path and asserts the generated
  `.config/glow/glow.yml` `home.file` exists with expected content — exercises the real home.file generation
  code). **Added `activate-hm-nixvim-minimal`** (T0.7, build-tier, widens the activation-build pattern).
- **Follow-up (non-blocking):** docs under `docs/TESTING*.md`, `tests/README.md`, `docs/src/how-to/test.md` still
  reference old check names (narrative only; P5a scope = tests.nix only). A comment in `vm-tests.nix:1252`
  mentions `eval-hm-module-development-tools` (comment, not functional). Refresh in P6/doc pass.

**P4 close-out verification (2026-08-21).** Before declaring P4 done, cross-checked the design against the
live flake (`nix eval '.#checks.x86_64-linux' --apply builtins.attrNames` = 106): all 34 check names the
design proposes to drop/rename/merge exist. Found + fixed ONE inaccuracy — `eval-hm-module-*` is **20**, not
18 (corrected in the design doc + this plan). Then, at Tim's direction, **split P5 into P5a/P5b/P5c with
checkable DoDs** (see Task definitions): P5a = Tier-0 eval consolidation (low-risk, eval-only, next up);
P5b = nspawn-fidelity spike (verify HM-activation + sops-nix + multi-node isolation under `mkContainerTest`
BEFORE migrating); P5c = Tier-1 behavioral refactor (dep P5b, backend map from the spike). P6 now deps
P5a+P5c. P5a and P5b both depend only on P4 (actionable now); P5a is ordered first as the intended
`/next-task` target, P5b must precede P5c.

### P5b spike findings (2026-08-21) — nspawn fidelity, evidence-based backend map for P5c

Ran on `pa161878-nixos` (KVM + `systemd-nspawn` present). This host's running system predates the 053-T6
fleet-wide base-module switch, so the **nix-daemon does not yet advertise `uid-range`** — nspawn checks
built via the documented ad-hoc root path (`sudo env NIX_CONFIG='… auto-allocate-uids cgroups / auto-
allocate-uids = true / extra-system-features = uid-range' nix build … --store local --no-write-lock-file`).
A `nixos-rebuild switch` on this host would enable the unprivileged daemon path. Three temporary spike
checks were added to `modules/flake-parts/vm-tests.nix` (right after `vm-nspawn-smoke`); they are throwaway
per the P5b def and will be removed/absorbed in P5c. All three **evaluate** clean (`--no-build`); check
total 60 → 63.

**Per-semantic verdicts (authoritative — override any `N?` guess in `docs/VMTEST-TARGET-DESIGN.md`):**

1. **sops-nix `/run/secrets` activation → nspawn-OK ✅** (`spike-nspawn-sops`, build+pass, 4.27s). A
   checked-in fixture age key + SOPS-encrypted YAML (the `vm-sops-secrets` fixtures) decrypt during
   activation to `/run/secrets` with **exact mode/owner preserved** (`database_password` 0400 root:root,
   `api_key` 0440 tim:users), correct plaintext (`supersecret123`), and ownership enforcement holds
   (non-root read of the root-only secret is denied). **P5c decision: MIGRATE `vm-sops-secrets` to nspawn**
   (resolves design-doc Q1 — the fidelity verification the migration was gated on passed). Minor note: `su -`
   prints "Authentication service cannot retrieve authentication info (Ignored)" in the container but still
   drops privileges enough for the perms check — cosmetic, not a fidelity gap.

2. **Multi-node isolation via `start_all` → nspawn-OK ✅** (`spike-nspawn-multinode`, build+pass, 4.23s).
   Two containers boot in parallel, each sees its own hostname, and filesystem state is isolated (a file
   created on one is absent on the other). **BUT a hard constraint surfaced:** container/node names become
   the `systemd-nspawn --machine=` name, which **MUST be a valid hostname — underscores are REJECTED**
   (`Invalid machine name: node_a` → the machine never comes up → `systemd-nspawn process exited
   unexpectedly`). QEMU node names tolerate underscores, so this **bites on migration**. **P5c action:**
   any multi-node test moved to nspawn MUST rename underscore node names to hostname-valid forms (hyphens
   OK) — affects `vm-hm-composition-pairs` (`pair_nvim_tmux`, `pair_git_nvim`, …) and
   `vm-hm-module-isolation` (`node_podman`, …). (Those two ALSO hit finding #3 below, so they stay QEMU
   regardless — but the rule applies to any future multi-node nspawn test, e.g. `vm-wsl-dev-team-layers`.)

3. **NixOS-integrated HM activation → MUST-STAY-QEMU ❌** (`spike-nspawn-hm-activation`, RECORDED FAILURE;
   the identical-module QEMU twin `vm-hm-activation` passes). Root cause: the container shares the host
   `/nix/store` **read-only**, so the in-container **nix-daemon aborts at startup** — `changing ownership of
   path "/nix/store": Operation not permitted` — and `home-manager-<user>.service`'s profile registration
   (`nix-env --set`, which round-trips through that daemon) then dies with `cannot open connection to remote
   store 'daemon': Connection reset by peer`, leaving the unit **failed**. This is the single most
   consequential finding: it **overrides the design doc's aggressive-nspawn assumption for the whole HM
   family.** **P5c decision: KEEP ON QEMU** every NixOS-integrated HM-activation test — `vm-hm-activation`,
   `vm-shell-env`, `vm-neovim`, `vm-tmux`, `vm-git-advanced`, `vm-development-tools`, `vm-user-config`,
   `vm-hm-composition-pairs`, `vm-hm-module-isolation`, `vm-yazi`'s fold target — anything that reaches
   `home-manager-<user>.service`.

   **ALT-CONFIG PROBE (Tim-requested — "try one legitimate lever before committing HM→QEMU"):** tried the
   canonical `nixos-containers` pattern that makes nix work in a shared-store container — disable the
   in-container daemon (`nix.enable = lib.mkForce false`, + force off the cascading `nix.gc.automatic` /
   `nix.optimise.automatic` assertions) and bind the **host** nix db read-only into the container
   (`virtualisation.systemd-nspawn.options = [ "--bind-ro=/nix/var/nix/db:/nix/var/nix/db" ]`) so local-mode
   `nix-env --set` could validate the prebuilt HM generation and write only the profile symlink to the
   container's writable `/nix/var`. **Result: FAILED EARLIER** — the container never starts:
   `Failed to clone /nix/var/nix/db: No such file or directory`. Root cause is one level deeper than the
   container config: the NixOS test runs **inside the Nix build sandbox**, which deliberately excludes
   `/nix/var/nix/db` and the nix daemon socket. Nixos-containers work because they proxy to the **host**
   daemon (`NIX_REMOTE=daemon`, comment "Use the host's nix-daemon" in `container-config.nix`) — but the test
   nspawn backend runs its own daemon against a `--bind-ro=/nix/store` store with an empty db, and the
   sandbox blocks any path to the host's db/daemon. Making HM activation work would need builder-global
   `extra-sandbox-paths` surgery that **breaks test hermeticity/reproducibility** (the test would depend on
   host db state) — a fundamentally different mechanism, not a config toggle. **Conclusion stands and is now
   evidence-backed at the sandbox layer: HM-activation tests must stay QEMU.** The probe's evidence is folded
   into the `spike-nspawn-hm-activation` code comment; the throwaway v2 experiment check was removed (kept
   only the v1 baseline reproducer, per Tim). **Do not attempt this workaround in P5c** — out of scope.

**Net effect on P5c backend map:** sops → nspawn (✅ new); pure-userspace/service tests without HM
activation remain nspawn candidates (e.g. `vm-system-type-default`, and the already-proven
`vm-nspawn-smoke` twin of `vm-system-type-cli`); **all HM-activation tests stay QEMU** (❌ reverses the
design-doc default); multi-node nspawn tests must use hostname-valid node names. `vm-compose-stack` and
`vm-wsl-dev-team-layers`: if either composes HM user config that activates, it inherits finding #3 → QEMU;
otherwise nspawn-eligible (decide per final module set in P5c).
