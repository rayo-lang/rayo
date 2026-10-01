# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring it. This is a single-context repo.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root — the glossary.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.
- **`docs/14-decisions.md`** — decisions D0–D19 and the open questions, recorded before `docs/adr/` existed. Read the entries that touch your area; they carry the same weight as ADRs.

If `CONTEXT.md` or `docs/adr/` doesn't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## Where terms and decisions live

- **Terms**: the language's terms are defined in the spec chapters, `docs/01-values-and-ownership.md` through `docs/15-soundness.md`. `CONTEXT.md` names them and points into those chapters; it must not restate or contradict them.
- **New decisions** go in `docs/adr/NNNN-<slug>.md`, numbered from `0001`. Don't append D20 or later to `docs/14-decisions.md`; it stays as the record of decisions made before `docs/adr/`.

## File structure

```
/
├── CONTEXT.md
├── docs/
│   ├── adr/
│   │   └── 0001-<slug>.md
│   ├── 01-values-and-ownership.md     ← spec chapters, 01–15
│   ├── …
│   ├── 14-decisions.md                ← decisions D0–D19, open questions
│   ├── 15-soundness.md
│   └── hard-cases.md
└── examples/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a spec change proposal, a hypothesis, an example), use the term as defined in `CONTEXT.md` and the spec. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag decision conflicts

If your output contradicts an existing ADR or D-entry, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (…) — but worth reopening because…_

> _Contradicts D14 (copies are written out) — but worth reopening because…_
