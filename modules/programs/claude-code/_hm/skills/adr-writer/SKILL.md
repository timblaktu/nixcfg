---
name: adr-writer
description: Guide writing Architecture Decision Records (ADRs) following the Design It! methodology. Use when creating ADRs, documenting architecture decisions, recording technical decisions, or when someone asks about ADR format or templates.
---

# Architecture Decision Record Writer

## ADR Template

Use this template when documenting architectural decisions:

```markdown
# ADR [NUMBER]: [DESCRIPTIVE TITLE]

## Status

[Draft | Proposed | Accepted | Superseded | Deprecated]

## Context

[Explain the circumstances that led to this decision. Include:
- Technical constraints or requirements
- Business drivers or political climate
- Team skills and experience
- Related previous decisions
- Quality attributes at stake]

## Decision

[Describe the decision clearly and concisely. State what you will do, not what you won't do.]

## Consequences

### Positive
- [Benefit 1]
- [Benefit 2]

### Negative
- [Tradeoff or risk 1]
- [Tradeoff or risk 2]

[Update consequences as they emerge over time]
```

## Instructions

1. **Identify if the decision is architectural** - see [REFERENCE.md](REFERENCE.md) for criteria
2. **Choose a sequential number** for the ADR (check existing ADRs first)
3. **Write a descriptive title** that captures the decision essence
4. **Set initial status** to Draft or Proposed
5. **Describe context thoroughly** - future readers need to understand *why*
6. **State the decision clearly** - be direct and specific
7. **List consequences honestly** - both positive and negative

## Best Practices

- **One decision per file** - keep ADRs focused
- **Keep it short** - 1-2 pages maximum
- **Use plain language** - avoid jargon where possible
- **Store with code** - put ADRs in version control (e.g., `docs/adr/`)
- **Never delete old ADRs** - mark as Superseded instead, with a reference to the new ADR
- **Review like code** - ADRs should go through the same review process as code

## Status Lifecycle

- **Draft** - Initial writing, not yet shared
- **Proposed** - Ready for team review
- **Accepted** - Team has agreed to this decision
- **Superseded** - Replaced by a newer ADR (link to it)
- **Deprecated** - No longer relevant but kept for history

For detailed guidance on when to write an ADR and what makes a decision architectural, see [REFERENCE.md](REFERENCE.md).
