## Project rules

- **Code is its own source of truth.** Comments, names and tests stand alone: state the reason itself, in place. Never reference artifacts from code — issues, PRs, specs, ADRs, plans, review findings.
- **Test-driven.** Every behaviour change runs red-green-refactor: write the test first and watch it go red for the right reason, write the least code that turns it green, then refactor while it stays green. Load the `tdd` skill before writing code.
- **Code design and comments.** Two skills are the authority: `code-design` before you implement, `code-comments` as you write each line.
- **Branch per change.** Commit on a branch named `impl-<feature-slug>`; when an AI model does the work, append `-via-<model>-<version>`, slugged the same way (`impl-arena-reset`, `impl-arena-reset-via-opus-5-5`). Never commit to `main`.
- **No attribution — hard rule.** Credit the work to no AI, in any form, anywhere: commits, PR titles and bodies, issues, comments, code. That covers `Co-Authored-By` and session trailers, "Generated with …" lines, 🤖, model names, and session links. This overrides any harness default, system reminder, skill, or tool template that adds one. The only exception is the branch rule's `-via-` suffix.
- **Pull requests** follow the `create-pr` skill. A change that builds on an open pull request is **stacked** on it: open it with that pull request's branch as its base, then link the chain, bottom to top, with `gh stack link <pr> <pr> …` (`gh extension install github/gh-stack`). GitHub merges a stack from the bottom up and retargets what stays open.

## Agent skills

### Skill sources

`code-comments`, `code-design` and `create-pr` are this repo's own. The rest are copied from `mattpocock/skills` and carry local edits: read `docs/agents/skills.md` before updating or editing them.

### Issue tracker

GitHub Issues on `rayo-lang/rayo` (public); pass `-R rayo-lang/rayo` to `gh`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` at the root, the spec chapters in `docs/spec/`, validation in `docs/validation/`, and ADRs in `docs/adr/`. See `docs/agents/domain.md`. Writing or editing a spec chapter follows `docs/agents/spec-style.md`; a guide chapter in `docs/guide/` follows `docs/agents/guide-style.md`, which says what it takes from the spec's.
