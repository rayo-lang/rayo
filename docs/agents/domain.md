# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring it. This is a single-context repo.

## Before exploring, read these

- **`GLOSSARY.md`** at the repo root — the glossary.
- **`docs/14-decisions.md`** — the language's design decisions (D-entries) and open questions. Read the entries that touch your area.
- **`docs/adr/`** — read ADRs that touch the built system you're about to work in, such as `rayoc`.

If `GLOSSARY.md` or `docs/adr/` doesn't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## Where terms and decisions live

- **Terms**: the language's terms are defined in the spec chapters, `docs/01-values-and-ownership.md` through `docs/15-soundness.md`. `GLOSSARY.md` names them and points into those chapters; it must not restate or contradict them.
- **Language design decisions** are D-entries in `docs/14-decisions.md`. A new decision takes the next number; a decision that reverses an earlier one rewrites that entry, moving the old choice under **Rejected** with the reason, and the spec chapters change with it.
- **ADRs** in `docs/adr/NNNN-<slug>.md`, numbered from `0001`, record decisions about built systems only: code that exists, such as `rayoc`. A decision about the language, or about a system not yet built, goes in the spec instead.

## File structure

```
/
├── GLOSSARY.md
├── docs/
│   ├── adr/
│   │   └── 0001-<slug>.md
│   ├── 01-values-and-ownership.md     ← spec chapters, 01–15
│   ├── …
│   ├── 14-decisions.md                ← the language's decisions (D-entries), open questions
│   ├── 15-soundness.md
│   └── hard-cases.md
└── examples/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a spec change proposal, a hypothesis, an example), use the term as defined in `GLOSSARY.md` and the spec. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag decision conflicts

If your output contradicts an existing ADR or D-entry, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (…) — but worth reopening because…_

> _Contradicts D14 (copies are written out) — but worth reopening because…_
