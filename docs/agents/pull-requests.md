# Branches, commits and pull requests

How a change reaches `main` on `rayo-lang/rayo`: the branch it is made on, its commits, the pull request that carries it, its review, and its merge. Issues are in `issue-tracker.md`.

## Branches

**Commit on a branch named `impl-<feature-slug>`**; when an AI model does the work, append `-via-<model>-<version>`, slugged the same way (`impl-arena-reset`, `impl-arena-reset-via-opus-5-5`). Never commit to `main`.

## Commits

**Every commit you write and every pull request title has the Conventional Commits subject `type(scope): summary`**, the summary starting with a lowercase imperative verb (`feat(sema): check calls to user functions`). Aim for a commit subject under 72 characters, and a pull request title under 65, so that with the ` (#N)` its merge commit adds, `git log --oneline` and GitHub show each whole; a reviewer treats the length as advice, never a finding.

- **Type:** `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `build`, `ci`, `chore` or `revert`.
- **Scope:** the one module whose behaviour changes, not counting tests (`syntax`, `sema`, `driver`), or a docs area such as `spec`, `guide`, `adr` or `agents`; left out when the change spans several.
- **Breaking change:** one that rejects a program `rayoc` accepted, changes what such a program does, or breaks a `rayo` or `rayoc` command line that worked, puts `!` before the colon (`feat(driver)!: drop 'rayo check'`).

## Opening a pull request

**At most three pull requests are open on `rayo-lang/rayo` at a time**, whoever opened them, drafts included and counting each pull request in a stack; `gh pr list -R rayo-lang/rayo --state open` counts them. Open the next only when one has merged or closed; work past the limit waits on its branch.

**Pull requests follow the `create-pr` skill.**

## Stacked pull requests

A change that builds on an open pull request is **stacked** on it: its base is the branch below it, and the stack's branches are kept with `gh stack` (`gh extension install github/gh-stack`), so that a change in one reaches every branch above it. `gh stack <command> --help` says what each command does; this is what it doesn't:

- **Start:** `gh stack init <branch> …`, bottom to top, adopts the branches, and `gh stack add <branch>` starts the next. Each pull request opens as `create-pr` says, within the limit above, and `gh stack link <pr> <pr> …` then links them. `gh stack submit` would open them past the limit, with generated titles and bodies, not create-pr's.
- **Change:** after a commit to one branch, `gh stack rebase --no-trunk` rebases the branches above it without moving the stack onto a newer `main`, and `gh stack push` pushes them.
- **Merge:** the bottom pull request merges as [Merging](#merging) says for a stacked one. Once it has, GitHub retargets the next onto `main` and rebases the rest, and `gh stack sync` then brings the local branches level and pushes them. Where it stops on a conflict, `gh stack rebase` and `gh stack push` finish the job; `gh stack sync --help` lists the other ways it stops.
- **Rebase rounds:** note each pull request's head and base before the bottom merges, and before `rebase` or `sync` rewrites them, then take the new ones from GitHub once the branches are pushed, for the review round each rebase is ([below](#reviewing)).

## Reviewing

A fresh agent, apart from the author, reviews each pull request, so its reading isn't anchored on the author's account.

- **Its prompt** gives the pull request's number, its head and its base, and nothing more. The agent checks the head out in a worktree of its own and loads the `code-review` skill with the base as the fixed point, taking the pull request's description and linked issues as the spec. No one answers its questions, and it reports findings only, each with its file, line and fix, tagged with the axis that raised it, and ranked:
  - **blocking:** the change is wrong: it breaks what the code does, a test, or the spec;
  - **should-fix:** it breaks a documented rule, or leaves a gap that the spec or a rule needs closed;
  - **nit:** wording, taste, or a judgement call.
- **Each round of fixes** goes back to that agent, continued with `SendMessage`, with the new head and two lists: what the author fixed, and what the author didn't fix and why. That message is all the reviewer gets: never what to conclude, what would approve, or more argument for a reason. The reviewer reviews every commit since the head it last reviewed, and judges each fix and each reason for itself. A change to the pull request's title or body alone is a round too, with the head unchanged.
- **A rebase** is a round of its own, whether onto a newer base or after the pull request below it in a stack merges. It goes to the same reviewer with the new head and base, and lists what the rebase changed; the reviewer compares the two with `git range-diff <old-base>..<old-head> <new-base>..<new-head>`. A merge of `main` into the branch, in place of a rebase, is such a round too, and the reviewer adds `--remerge-diff` to the same command to check that the pull request's own diff is unchanged: its commits match, and the merge commit shows only what resolving a conflict changed, nothing when it merged clean.
- **A review approves** when none of its blocking or should-fix findings holds. A decline the reviewer rejects is fixed, or goes to the user to decide, and is never argued again. A finding the user decides against no longer counts.

## Merging

**A pull request merges as one squashed commit, once CI passes on the head its reviewer approved.** As soon as the review approves, turn on auto-merge for that head, so GitHub merges it when CI passes and no one waits on CI:

```sh
gh pr merge <N> -R rayo-lang/rayo --auto --squash --match-head-commit <approved head> \
  --subject "<pull request title> (#<N>)" --body-file <message file>
```

- **The message file** is a plain paragraph, wrapped at 72 columns, that says what the change does, written from the diff as the pull request body is, with no section headings and no attribution.
- **If GitHub refuses auto-merge because the pull request can already merge**, run the same command without `--auto`: it merges at once.
- **Before you push to a pull request whose auto-merge is on, or edit its title or body**, turn it off with `gh pr merge <N> -R rayo-lang/rayo --disable-auto`, so nothing the next round hasn't approved can merge, whether a new head or the old subject and message. Turn it on again, with the subject and message that round's head and title call for, once that round approves.
- **Once `main` moves ahead of a pull request based on it, rebase it onto `main`** and send it to the reviewer as a round, since `main` takes only a branch that is up to date with it; CI runs again on the new head. Where you can't force-push, merge `main` into the branch and push it normally instead: the squash merge gives `main` the same result. The bottom of a stack moves only with the branches above it, through `gh stack rebase` and `gh stack push`, a round for each pull request that moves.
- **A stacked pull request merges by hand, through GitHub's asynchronous merge API**: GitHub refuses `gh pr merge` for one and has no auto-merge for it. Only the bottom of a stack merges, since GitHub merges every pull request below the one it is given along with it. Once its review has approved its head and CI has passed on that head, give the API that head, the subject and the message file as above; `gh stack merge` passes none of the three. The call returns before the merge runs, so it has merged only once GitHub shows the pull request as merged.
- **A pull request whose CI fails doesn't merge.** Fix the failure in a new commit, and send it to the reviewer as a round.
