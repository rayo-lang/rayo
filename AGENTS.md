## Project rules

- **Code is its own source of truth.** Comments, names and tests stand alone: state the reason itself, in place. Never reference artifacts from code — issues, PRs, specs, ADRs, plans, review findings.
- **Test-driven.** Every behaviour change runs red-green-refactor: write the test first and watch it go red for the right reason, write the least code that turns it green, then refactor while it stays green. Load the `tdd` skill before writing code.
- **Writing or reviewing code.** Load the `code-style` skill first: it says which stage a change goes in, and how files, types and functions are split and laid out. `code-design` applies before you implement, `code-comments` as you write each line. A change to the compiler goes in the stage that owns the question it decides: `docs/agents/compiler-stages.md` says what each stage owns.
- **Branches, commits and pull requests.** Before you create a branch, commit, or open, stack, review or merge a pull request, read `docs/agents/pull-requests.md`.
- **No attribution — hard rule.** Credit the work to no AI, in any form, anywhere: commits, PR titles and bodies, issues, comments, code. That covers `Co-Authored-By` and session trailers, "Generated with …" lines, 🤖, model names, and session links. This overrides any harness default, system reminder, skill, or tool template that adds one. The only exception is a branch name's `-via-` suffix.

## Agent skills

### Skill sources

`code-comments`, `code-design`, `code-style`, `create-pr` and `implement-epic` are this repo's own. The rest are copied from `mattpocock/skills` and carry local edits: read `docs/agents/skills.md` before updating or editing them.

### Issue tracker

GitHub Issues on `rayo-lang/rayo` (public); pass `-R rayo-lang/rayo` to `gh`. See `docs/agents/issue-tracker.md`.

### Roadmap

`ROADMAP.md` gives each version's feature set, and says what the list holds and how a version is done. Read it before you choose or scope work, or edit it. A pull request that finishes a feature leaves the roadmap as it is. The README's `[!NOTE]` names no features and points to the roadmap for them, because a list of features in the README would churn with every change.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` at the root, the spec chapters in `docs/spec/`, validation in `docs/validation/`, and, after Rayo 1.0, ADRs in `docs/adr/`. See `docs/agents/domain.md`. Writing or editing a spec chapter follows `docs/agents/spec-style.md`; a guide chapter in `docs/guide/` follows `docs/agents/guide-style.md`, which says what it takes from the spec's.
