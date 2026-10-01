# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues in [`rayo-lang/rayo`](https://github.com/rayo-lang/rayo). Use the `gh` CLI for all operations.

The repo is **public**: every issue, comment and label posted there is visible to anyone.

Pass `-R rayo-lang/rayo` to every `gh issue`, `gh pr` and `gh label` command, and use `repos/rayo-lang/rayo/...` in `gh api` paths, so each command reaches this repo even from a fork's clone, where `gh` would otherwise pick the fork or ask.

## Conventions

- **Create an issue**: `gh issue create -R rayo-lang/rayo --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> -R rayo-lang/rayo --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list -R rayo-lang/rayo --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> -R rayo-lang/rayo --body "..."`
- **Apply / remove labels**: `gh issue edit <number> -R rayo-lang/rayo --add-label "..."` / `--remove-label "..."`. A label must exist before it can be applied: if `--add-label` fails because the label is missing, create it with `gh label create -R rayo-lang/rayo "<name>"` and retry.
- **Close**: `gh issue close <number> -R rayo-lang/rayo --comment "..."`

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> -R rayo-lang/rayo --comments` and `gh pr diff <number> -R rayo-lang/rayo` for the diff.
- **List external PRs for triage**: `gh pr list -R rayo-lang/rayo --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`, each with `-R rayo-lang/rayo`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either — resolve with `gh pr view 42 -R rayo-lang/rayo` and fall back to `gh issue view 42 -R rayo-lang/rayo`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue in `rayo-lang/rayo`.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> -R rayo-lang/rayo --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create -R rayo-lang/rayo --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api` on the sub-issues endpoint, `repos/rayo-lang/rayo/issues/<map>/sub_issues`). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies** — the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/rayo-lang/rayo/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/rayo-lang/rayo/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only — the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list -R rayo-lang/rayo --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> -R rayo-lang/rayo --add-assignee @me` — the session's first write.
- **Resolve**: `gh issue comment <n> -R rayo-lang/rayo --body "<answer>"`, then `gh issue close <n> -R rayo-lang/rayo`, then append a context pointer (gist + link) to the map's Decisions-so-far.
