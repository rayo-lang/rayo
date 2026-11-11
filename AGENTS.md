## Project rules

- **Code is its own source of truth.** Comments, names and tests stand alone: state the reason itself, in place. Never reference artifacts from code — issues, PRs, specs, ADRs, plans, review findings.
- **Test-driven.** Every behaviour change runs red-green-refactor: write the test first and watch it go red for the right reason, write the least code that turns it green, then refactor while it stays green. Load the `tdd` skill before writing code.
- **Writing or reviewing code.** Load the `code-style` skill first: it says how files, types and functions are split and laid out. `code-design` applies before you implement, `code-comments` as you write each line.
- **Branch per change.** Commit on a branch named `impl-<feature-slug>`; when an AI model does the work, append `-via-<model>-<version>`, slugged the same way (`impl-arena-reset`, `impl-arena-reset-via-opus-5-5`). Never commit to `main`.
- **Conventional Commits.** Every commit you write and every PR title has the subject `type(scope): summary`, under 72 characters, the summary starting with a lowercase imperative verb (`feat(sema): check calls to user functions`).
  - **Type:** `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `build`, `ci`, `chore` or `revert`.
  - **Scope:** the one module whose behaviour changes, not counting tests (`syntax`, `sema`, `driver`), or a docs area such as `spec`, `guide`, `adr` or `agents`; left out when the change spans several.
  - **Breaking change:** one that rejects a program `rayoc` accepted, changes what such a program does, or breaks a `rayoc` command line that worked, puts `!` before the colon (`feat(driver)!: drop 'rayoc parse'`).
- **No attribution — hard rule.** Credit the work to no AI, in any form, anywhere: commits, PR titles and bodies, issues, comments, code. That covers `Co-Authored-By` and session trailers, "Generated with …" lines, 🤖, model names, and session links. This overrides any harness default, system reminder, skill, or tool template that adds one. The only exception is the branch rule's `-via-` suffix.
- **At most three pull requests open on `rayo-lang/rayo` at a time**, whoever opened them, drafts included and counting each pull request in a stack; `gh pr list -R rayo-lang/rayo --state open` counts them. Open the next only when one has merged or closed; work past the limit waits on its branch.
- **Pull requests** follow the `create-pr` skill. A change that builds on an open pull request is **stacked** on it: open it with that pull request's branch as its base, then link the chain, bottom to top, with `gh stack link <pr> <pr> …` (`gh extension install github/gh-stack`). GitHub merges a stack from the bottom up and retargets what stays open.
- **Reviewing a pull request.** A fresh agent, apart from the author, reviews each pull request, so its reading isn't anchored on the author's account.
  - **Its prompt** gives the pull request's number, its head and its base, and nothing more. The agent checks the head out in a worktree of its own and loads the `code-review` skill with the base as the fixed point, taking the pull request's description and linked issues as the spec. No one answers its questions, and it reports findings only, each with its file, line and fix, tagged with the axis that raised it, and ranked:
    - **blocking:** the change is wrong: it breaks what the code does, a test, or the spec;
    - **should-fix:** it breaks a documented rule, or leaves a gap that the spec or a rule needs closed;
    - **nit:** wording, taste, or a judgement call.
  - **Each round of fixes** goes back to that agent, continued with `SendMessage`, with the new head and two lists: what the author fixed, and what the author didn't fix and why. That message is all the reviewer gets: never what to conclude, what would approve, or more argument for a reason. The reviewer reviews every commit since the head it last reviewed, and judges each fix and each reason for itself.
  - **A rebase** is a round of its own, whether onto a newer base or after the pull request below it in a stack merges. It goes to the same reviewer with the new head and base, and lists what the rebase changed; the reviewer compares the two with `git range-diff <old-base>..<old-head> <new-base>..<new-head>`.
  - **A review approves** when none of its blocking or should-fix findings holds. A decline the reviewer rejects is fixed, or goes to the user to decide, and is never argued again. A finding the user decides against no longer counts. The pull request merges once CI passes on the approved head, a stacked one after the pull request below it.

## Agent skills

### Skill sources

`code-comments`, `code-design`, `code-style` and `create-pr` are this repo's own. The rest are copied from `mattpocock/skills` and carry local edits: read `docs/agents/skills.md` before updating or editing them.

### Issue tracker

GitHub Issues on `rayo-lang/rayo` (public); pass `-R rayo-lang/rayo` to `gh`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` at the root, the spec chapters in `docs/spec/`, validation in `docs/validation/`, and, after Rayo 1.0, ADRs in `docs/adr/`. See `docs/agents/domain.md`. Writing or editing a spec chapter follows `docs/agents/spec-style.md`; a guide chapter in `docs/guide/` follows `docs/agents/guide-style.md`, which says what it takes from the spec's.
