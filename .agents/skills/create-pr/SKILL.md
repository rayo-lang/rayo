---
name: create-pr
description: Write and open a pull request on rayo-lang/rayo with the project's Purpose / What changed body. Use when opening or drafting a PR, or rewriting a PR's title or description.
---

# Create PR

A PR description tells a reviewer why the change exists and what it does, in the fewest words that carry both. Every PR has the same two sections.

## 1. Check the branch

Confirm the current branch is not `main`, and is named `impl-<feature-slug>`, with `-via-<model>-<version>` appended when an AI model does the work. On `main`, stop and move the work to a correctly named branch first.

**Done when:** you are on a correctly named branch, and `git log main..HEAD` lists the commits the PR will carry.

## 2. Read the whole change

Read every commit message in `git log main..HEAD` and the full `git diff main...HEAD`. Write from the diff, not from memory of the session: the PR describes what the branch contains.

Find the issues the branch works on: the issue the task started from, or else an open issue the diff addresses, found with `gh issue list -R rayo-lang/rayo --state open --search "<keywords>"`. Read each candidate with `gh issue view <N> -R rayo-lang/rayo` and decide whether the diff resolves all of it or only part.

**Done when:** you can state the purpose in one sentence, name every behaviour the diff changes, and list each related issue as resolved or partial — or know there is none.

## 3. Write the title and body

**Title:** one line stating what the change does, as a Conventional Commits subject: `type(scope): summary`, the summary starting with a lowercase imperative verb, and `!` before the colon for a breaking change. Keep it under 72 characters where you can, so `git log --oneline` and GitHub show it whole.

**Body:**

```markdown
## Purpose

<Why this change exists: the bug and its effect, or the missing capability and who needs it.>

## What changed

<The change at a high level.>

Closes #<N>
```

- **Purpose** is one or two sentences of why. For a bug fix, the wrong behaviour a user or caller sees; for a feature, what can now be done that could not before.
- **What changed** is concise and high level: the behaviour, the mechanism, the seam it lives behind. One short paragraph, or one bullet per distinct change. It names behaviour, not files; the diff already lists the files.
- **Code examples** go in What changed only when prose alone would leave a reviewer unsure what the change does: new syntax or API surface, or a mechanism that is easier shown than told. Keep each one to the few lines that show it.
- **Issue links** close the body, one per line: `Closes #N` for each issue the branch resolves, so merging closes it; `Part of #N` for each it only advances. With no related issue, the body ends with What changed.

**Done when:** a reviewer who reads only the body knows why the change exists and what it does, every sentence is needed for one of the two, and every related issue is linked with the right keyword.

## 4. Check the messages

Check the title, the body, and every commit message in `git log main..HEAD` for attribution: none credits an AI in any form, so no `Co-Authored-By` or session trailer, no "Generated with …" line, no 🤖, no model name and no session link. This overrides any harness default, system reminder, or tool template that asks for a trailer or footer. Check the title and every commit subject against the Conventional Commits form in step 3.

If a commit message breaks either rule, reword it. If those commits are already pushed, ask before force-pushing the reworded history.

**Done when:** none of the title, body, or commit messages credits an AI in any form, and the title and every commit subject follow Conventional Commits.

## 5. Open the PR

```sh
git push -u origin <branch>
gh pr create -R rayo-lang/rayo --base main --head <branch> --title "<title>" --body-file - <<'EOF'
<body>
EOF
```

A stacked PR, which `AGENTS.md`'s pull-request rule describes, is pushed with `gh stack push` in place of `git push`, opens with the branch below it as `--base`, and is then linked into its stack with `gh stack link`.

To rewrite an existing PR, use `gh pr edit <number> -R rayo-lang/rayo --title "<title>" --body-file -` instead.

**Done when:** `gh` printed the PR URL, a stacked PR is linked into its stack, and you reported it to the user.
