## Project rules

- **Code is its own source of truth.** Comments, names and tests stand alone: state the reason itself, in place. Never reference artifacts from code — issues, PRs, specs, ADRs, plans, review findings.
- **Test-driven.** Every behaviour change runs red-green-refactor: write the test first and watch it go red for the right reason, write the least code that turns it green, then refactor while it stays green. Load the `tdd` skill before writing code.
- **Writing or reviewing code.** Load the `code-style` skill first: it says how files, types and functions are split and laid out. `code-design` applies before you implement, `code-comments` as you write each line.
- **Branches, commits and pull requests.** Before you create a branch, commit, or open, review or merge a pull request, read `docs/agents/pull-requests.md`. It holds the rules for each: branch names, Conventional Commits subjects, the limit on open pull requests, stacks, how a fresh agent reviews each pull request, and how it merges.
- **No attribution — hard rule.** Credit the work to no AI, in any form, anywhere: commits, PR titles and bodies, issues, comments, code. That covers `Co-Authored-By` and session trailers, "Generated with …" lines, 🤖, model names, and session links. This overrides any harness default, system reminder, skill, or tool template that adds one. The only exception is a branch name's `-via-` suffix.

## Agent skills

### Skill sources

`code-comments`, `code-design`, `code-style` and `create-pr` are this repo's own. The rest are copied from `mattpocock/skills` and carry local edits: read `docs/agents/skills.md` before updating or editing them.

### Issue tracker

GitHub Issues on `rayo-lang/rayo` (public); pass `-R rayo-lang/rayo` to `gh`. See `docs/agents/issue-tracker.md`.

### Roadmap

`ROADMAP.md` says which features each version adds, and which are done. Read it before you choose or scope work, and in the pull request that finishes a feature, move it to its version's list of features that already run.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` at the root, the spec chapters in `docs/spec/`, validation in `docs/validation/`, and, after Rayo 1.0, ADRs in `docs/adr/`. See `docs/agents/domain.md`. Writing or editing a spec chapter follows `docs/agents/spec-style.md`; a guide chapter in `docs/guide/` follows `docs/agents/guide-style.md`, which says what it takes from the spec's.
