# ADR Reference Guide

Based on the "Design It!" methodology by Michael Keeling.

## When to Write an ADR

A decision is **architectural** if it meets any of these criteria:

1. **Affects other components or teams** - The decision impacts how other parts of the system work or how other teams develop their code

2. **Changes quality attributes** - The decision influences performance, security, scalability, maintainability, or other system qualities

3. **Is driven by constraints** - Business requirements, technical limitations, or political factors force a particular choice

4. **Has far-reaching impact** - Framework choices, technology selections, or patterns that touch many parts of the system

5. **Changes development/delivery process** - Decisions that fundamentally alter how the team builds or ships the system

### Quick Test

Ask yourself: "If this decision were reversed in 6 months, would it require significant rework?" If yes, document it.

## What to Include in Context

The Context section should answer "Why are we making this decision now?"

Include:
- **Technology landscape** - Current tech stack, available tools, integration requirements
- **Team capabilities** - Skills, experience, capacity
- **Business drivers** - Deadlines, budget, strategic direction
- **Previous decisions** - Related ADRs that influence this one
- **Constraints** - Non-negotiable requirements or limitations
- **Quality attribute priorities** - Which qualities matter most for this decision

## Writing Good Consequences

Be honest about tradeoffs. Every decision has costs.

### Positive Consequences
- What problems does this solve?
- What capabilities does it enable?
- How does it improve quality attributes?

### Negative Consequences
- What new complexities does it introduce?
- What alternatives are we giving up?
- What technical debt might accumulate?
- What skills does the team need to acquire?

Update consequences over time as you learn more about the actual impacts.

## Do's and Don'ts

### Do
- Make recording decisions a **team responsibility**
- Keep ADRs **close to the code** in the repository
- Use ADRs to **train teammates** in architectural thinking
- Enable **peer review** using standard development tools
- **Combine with other docs** - diagrams, views, design documents

### Don't
- Use ADRs as the **only** architecture documentation
- **Overthink** which decisions are architectural - when in doubt, document it
- Write ADRs **after the fact** - capture decisions when they're made
- Let ADRs become **too long** - if it's over 2 pages, split it

## Example ADR Structure

```
docs/adr/
  0001-record-architecture-decisions.md
  0002-use-postgresql-for-persistence.md
  0003-adopt-react-for-frontend.md
  0004-implement-event-sourcing.md
```

## File Naming Convention

Use this pattern: `NNNN-short-title-with-hyphens.md`

- 4-digit number with leading zeros
- Lowercase words separated by hyphens
- Keep titles brief but descriptive

## Superseding an ADR

When a decision changes:

1. Create a new ADR with the new decision
2. Update the old ADR's status to "Superseded by ADR-NNNN"
3. Reference the old ADR in the new one's Context section

This preserves the decision history and helps future readers understand the evolution.
