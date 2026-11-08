# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring it. This is a single-context repo.

## Before exploring, read these

- **`GLOSSARY.md`** at the repo root — the glossary.
- **The spec chapters** — the numbered pages in `docs/spec/` and any subchapters they link. Read the ones that touch your area.
- **The validation documents** — when changing the spec, check the safety argument and relevant hard cases in `docs/validation/`. The spec defines the rules; validation checks them.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.

If `GLOSSARY.md` or `docs/adr/` doesn't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates `GLOSSARY.md` lazily when a term gets resolved, and `docs/adr/` with the first ADR after Rayo 1.0.

## Where terms and decisions live

- **Terms**: the language's terms are defined in the spec chapters. `GLOSSARY.md` names each, says in one sentence what it is, and links to its definition; the rules stay in the chapters, and the glossary never contradicts them.
- **The language's design** is the spec chapters themselves: they state the current rules.
- **The guide** in `docs/guide/` teaches the spec's rules and states none of its own. A spec change that alters a rule the guide teaches updates that guide chapter in the same change.
- **Before Rayo 1.0, decisions edit what they shape.** The whole project is still being shaped until then, so every decision is part of that shaping, including one that reverses an existing rule. It edits the spec chapters or the code it touches, and no ADR or other log of decisions is kept.
- **ADRs** in `docs/adr/NNNN-<slug>.md`, numbered from `0001`, record a change of course after Rayo 1.0: a decision that considerably changes something that already exists, or turns the project in a new direction. The `domain-modeling` skill holds the full test.

## File structure

```
/
├── GLOSSARY.md
├── docs/
│   ├── adr/
│   │   └── 0001-<slug>.md
│   ├── guide/
│   │   ├── 01-basics.md                   ← the numbered guide chapters
│   │   └── …
│   ├── spec/
│   │   ├── 01-values-and-ownership.md     ← a numbered spec chapter
│   │   ├── 02-views-and-dependencies.md   ← a chapter's landing page
│   │   ├── 02-views-and-dependencies/      ← its subchapters
│   │   └── …
│   ├── validation/
│   │   ├── safety-argument.md
│   │   └── hard-cases.md
│   └── why-rayo.md
└── examples/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a spec change proposal, a hypothesis, an example), use the term as defined in `GLOSSARY.md` and the spec. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag decision conflicts

If your output contradicts an existing ADR or a rule in the spec, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (…) — but worth reopening because…_

> _Contradicts 01's rule that copies are written out — but worth reopening because…_
