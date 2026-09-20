# Domain Docs

How engineering skills consume this repository's domain documentation.

## Before exploring, read these

- `CONTEXT.md` at the repository root.
- `CONTEXT-MAP.md` instead, if one exists.
- Relevant ADRs under `docs/adr/`.

If these files do not exist, proceed silently. The domain-modeling skills create them lazily when terminology or architectural decisions are resolved.

## File structure

This repository uses a single-context layout:

```text
/
├── CONTEXT.md
└── docs/
    └── adr/
```

## Use the glossary's vocabulary

Use domain terms as defined in `CONTEXT.md`. Avoid synonyms that the glossary explicitly rejects.

If a required concept is missing, reconsider whether new terminology is necessary or note the gap for domain modeling.

## Flag ADR conflicts

Explicitly identify proposals that contradict an existing ADR instead of silently overriding the decision.
