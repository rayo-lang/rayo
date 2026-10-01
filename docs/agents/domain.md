# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring it. This is a single-context repo.

## Before exploring, read these

- **`GLOSSARY.md`** at the repo root — the glossary.
- **The spec chapters** — the numbered files in `docs/`. Read the ones that touch your area.
- **`docs/adr/`** — read ADRs that touch the built system you're about to work in, such as `rayoc`.

If `GLOSSARY.md` or `docs/adr/` doesn't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## Where terms and decisions live

- **Terms**: the language's terms are defined in the spec chapters. `GLOSSARY.md` names them and points into those chapters; it must not restate or contradict them.
- **The language's design** is the spec chapters themselves: they state the current rules. A design change edits the chapters it touches, and keeps no separate log of decisions.
- **ADRs** in `docs/adr/NNNN-<slug>.md`, numbered from `0001`, record decisions about built systems only: code that exists, such as `rayoc`. A decision about the language, or about a system not yet built, changes the spec instead.

## File structure

```
/
├── GLOSSARY.md
├── docs/
│   ├── adr/
│   │   └── 0001-<slug>.md
│   ├── 01-values-and-ownership.md     ← the numbered spec chapters
│   ├── …
│   └── hard-cases.md
└── examples/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a spec change proposal, a hypothesis, an example), use the term as defined in `GLOSSARY.md` and the spec. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag decision conflicts

If your output contradicts an existing ADR or a rule in the spec, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (…) — but worth reopening because…_

> _Contradicts 01's rule that copies are written out — but worth reopening because…_
