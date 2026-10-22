---
name: adr-writer
description: Guide writing Architecture Decision Records (ADRs) following the Design It! methodology. Use when creating ADRs, documenting architecture decisions, recording technical decisions, or when someone asks about ADR format or templates.
---

# Architecture Decision Record Writer

Two layers of guidance live here:
1. **Generic** ADR craft (Design It! methodology) - use anywhere.
2. **Platform ADR Standard** (below) - AUTHORITATIVE for the `project/docs/adrs`
   repo (and any repo that ships the SDA ADR process). It overrides the generic template
   there. Always prefer a repo's own shipped guide/template/topic-catalog over an exemplar.

## Generic ADR Template (non-platform repos)

```markdown
# ADR [NUMBER]: [DESCRIPTIVE TITLE]

## Status
[Draft | Proposed | Accepted | Superseded | Deprecated]

## Context
[Circumstances that led to this decision: constraints, drivers, prior decisions, quality attributes.]

## Decision
[State what you will do, clearly and specifically.]

## Consequences
### Positive
- ...
### Negative
- ...
```

## Generic Best Practices

- **One decision per file** - keep ADRs focused.
- **Keep it short** - the front-door is 1-2 pages; push depth to linked detail/design.
- **Plain language** - avoid jargon where possible.
- **Store with code** - ADRs in version control (e.g. `doc/adr/`).
- **Never delete old ADRs** - mark Superseded with a link to the replacement.
- **Review like code** - same review process as code. A green check script does NOT prove the decision is correct.

---

## Platform ADR Standard (AUTHORITATIVE)

Source: **SDA ADR Authoring Guide** (rev 2026-09) + `docs/process/adr/adr-template.md`,
`docs/process/topics/topic-catalog.yaml`, `docs/process/adr/repository-workflow.md`.
NOTE: the guide writes the ADR root as `docs/adr/`; the `project/docs/adrs` repo root is
`doc/adr/` (singular) - use `doc/adr/` there.

### 1. When to write one
Write an ADR for a **durable architecture decision** whose rationale, alternatives,
consequences, compatibility, or approval history must stay discoverable. **One primary
decision per ADR.** Keep evolving design detail in Confluence and LINK it; the ADR must still
stand on its own.

### 2. Required inputs (gather before creating the file)
decision title; decision owner; **author**; Jira key + link; Confluence design link; context +
problem; decision + rationale; alternatives; consequences/trade-offs; compatibility/migration;
validation evidence (or planned); proposed approvers + consulted; related/superseded ADRs;
topic hints. **If an input is unknown, leave an explicit `TBD` and resolve before acceptance.
NEVER invent links, approvals, evidence, identifiers, or topics.**

### 3. Identifier + location
Identifier is **`AAABBB`** (6 digits). Path:
`doc/adr/AAABBB-<short-title>/AAABBB-<short-title>.md`
- **`AAA` = group** (reuse the existing group the decision belongs to):

  | AAA | Group |
  |---|---|
  | 000 | General and Cross-layers |
  | 001 | DevEx |
  | 002 | PaaS |
  | 003 | Infrastructure and DevOps |
  | 004 | Testing |
  | 005 | IaaS |
  | 006 | Network |
  | 007 | VTE |

- **`BBB` = 3-digit unique index within the group** (next free index in that group).
- **Do NOT create a new group** merely because placement is unclear - reuse the closest, and
  record the ambiguity for architecture review.
- **Do NOT reuse or renumber an existing ADR identifier.** Once assigned, it is stable.
- Repository helpers may assist with placement/discovery, but the author reviews it.

### 4. Template (copy from `docs/process/adr/adr-template.md`)

```markdown
# AAABBB: ADR Title

- Status: <Proposed|Approved|Rejected>
- Author: <Author>
- Decision owner: <person or accountable group>
- Jira: <key and link>
- Confluence design: <stable design page link>
- Decision date: <YYYY-MM-DD when accepted; omit while proposed>
- Topics: <canonical topic slugs>
- Supersedes: <ADR identifiers or None>
- Superseded by: <ADR identifiers or None>

## Abstract
## Problem description
## Decision
## Rationale
## Alternatives considered
## Consequences
## Compatibility and migration
## Validation
## Reviewers (Approved/Rejected)
## Consulted
## Related ADRs
## Open questions/Comments by reviewers
```

- **Status enum is `Proposed | Approved | Rejected`** (not Draft/Accepted/Deprecated).
  Supersession is expressed via the `Superseded by` field, not a Status value.
- **`Author` is a distinct field** from `Decision owner` (owner = accountable person/group).
- `Confluence design` is required when a design page backs the decision.
- Sections stay IN THIS ORDER; each is a short summary + "Full detail: [link]".

### 5. Topics + related records
Use **canonical slugs from `docs/process/topics/topic-catalog.yaml`**. Search the ADR index
and neighboring records for related/superseded/conflicting decisions. Do NOT invent a new topic
alias unless the catalog change is intentional and reviewed.

### 6. Validate + review
Follow `docs/process/adr/repository-workflow.md`: review the actual diff, run the ADR checks,
complete the ADR merge-request template. A successful script run does not prove the decision is
correct.

### 7. Repository layout
- **One ADR = one self-contained folder** `doc/adr/AAABBB-<short-title>/`, front-door =
  `AAABBB-<short-title>.md` (the guide's prescribed named front-door), detail/diagram files beside it.
- **Never give one ADR two homes** (no loose top-level file AND a sibling folder).
- **All ADR folders under the one canonical root** `doc/adr/`. Copy an exemplar's *shape*, not
  its path.
- **KNOWN DIVERGENCE (as of 2026-09):** the first ADRs authored under the 6-digit scheme
  (`005003-onboard-reliability`, `002003-airgap-native-asset-delivery`) use `README.md` as the
  front-door, not the guide's `AAABBB-<short-title>.md`. Reconcile per repo owner before
  treating either as the fixed rule; new ADRs SHOULD follow the guide (named file) unless told
  otherwise.

## Status Lifecycle (generic repos)

- **Draft** -> **Proposed** -> **Accepted** -> **Superseded**/**Deprecated**.
  (the Platform standard uses Proposed/Approved/Rejected + a Superseded-by field instead - see above.)

For when a decision is architectural and worth an ADR, see [REFERENCE.md](REFERENCE.md).
