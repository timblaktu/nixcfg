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
- **P5 Execute:** implement the target — delete the 2 mocks + unsalvageable weak no-ops; rename
  `build-*-dryrun`→`eval-*-toplevel`; consolidate `eval-*`→`regression-test`; merge the SSH-2223 triple;
  write new Tier-1 behavioral tests for Tier-A hosts.
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

## Progress tracking
| ID | Task | Kind | Status |
|----|------|------|--------|
| P0 | Decide working branch | Interactive | TASK:COMPLETE 2026-08-20 — `feat/vmtest-refactor` (created from main) |
| P1 | **Parallel test-suite audit** — inventory + feature/code coverage map (run as a multi-agent Workflow) | 1 · analysis (workflow) | TASK:COMPLETE 2026-08-21 — `docs/VMTEST-AUDIT.md` (all 106 checks + 65 coverage rows + gaps/redundancies/weak + adversarial verification) |
| P2 | **Audit review & roadmap sign-off** — review findings + confirm/revise P3-P6 sequence | Interactive (gate) | TASK:COMPLETE 2026-08-21 — findings dispositioned, 2-tier priority + both-repos/CI-first framing settled, roadmap revised to P3-P7 (see "P2 review decisions") |
| P3 | Assessment + interactive backend-fit review + **nixcfg-work Tier-A host audit** (nothing sacred) | Interactive (collaborative) | TASK:IN_PROGRESS 2026-08-21 — nixcfg-work Tier-A audit groundwork prepared; interactive backend-fit review + Tier-0 list pending Tim |
| P4 | Target suite design (2-tier) — keep/merge/rewrite/drop/add + backend + rationale | Interactive (collaborative) | TASK:PENDING (dep P3) |
| P5 | Execute the refactor (conversions, new tests, deletions, renames, consolidations) | 1 · portable | TASK:PENDING (dep P4) |
| P6 | CI wiring (KVM runners, both arches) + carry into nixcfg-work corp hosts | 1 · CI / nixcfg-work | TASK:PENDING (dep P5) |
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
