---
name: pr-workflow
description: Pull requests and stacks of them on rayo-lang/rayo, from branch to merge. Use before opening a pull request, to take one through review and CI, to merge one, and to move (rebase) a branch onto a new base after the one below it merges or `main` moves.
---

# Pull request workflow

Pull requests on `rayo-lang/rayo` land one at a time, squashed, from the bottom of each stack.

**The bottom** is the pull request into `main`. A pull request opened with another's branch as its base is **stacked** on it, and the chain of them is a **stack**. A branch that is pushed but waits, without a pull request, until step 2 lets it open is **held**. A branch **moves** when its own commits are rebased onto a new base, as [Move a branch](#move-a-branch) says.

## 1. Check the change fits a pull request

A pull request carries one subject, and fewer than 1000 changed lines against its base, `main` or the branch it is stacked on: `git fetch origin`, then `git diff --shortstat origin/<base>...HEAD`, insertions and deletions together. A change with two subjects splits into a stack, one subject to each pull request; one subject over the limit splits into a stack of parts, each under it.

**Done when:** the branch holds one subject, which one Conventional Commits title states in full, and its diff against its base is under 1000 changed lines.

## 2. Check a pull request may open

At most three pull requests are open on `rayo-lang/rayo` at a time, whoever opened them, drafts included and counting each pull request in a stack: `gh pr list -R rayo-lang/rayo --state open --json number -q length` counts them. With three or more open, or the branch below it held, the branch is held: push it with `git push -u origin <branch>`, and tell the user it waits and what it is stacked on. Held branches open in stack order, each once a place is free and the one below it is open or merged; when held branches in more than one stack may open, ask the user which goes first.

**A held branch follows the branch below it.** After each push of a branch `<lower-branch>`, whether a move or a new commit, move each held branch stacked on it onto `origin/<lower-branch>` by [Move a branch](#move-a-branch), its `<heads>` the heads of `<lower-branch>`. The held branches stacked on it are those `git branch -r --contains <old> --format='%(refname:short)'` lists, `<old>` its head before the push, that have no open pull request (`gh pr list -R rayo-lang/rayo --head <held-branch> --state open` prints nothing). Move the one directly on it first; it moves the ones above it in turn.

**Done when:** fewer than three are open and the branch below this one, if any, has its pull request open or merged; or the branch is pushed, and the user knows it is held.

## 3. Open it

Write and open it with the `create-pr` skill, its base the branch of the open pull request it builds on, or `main`. Then link a stacked one into its stack, so GitHub shows the stack and retargets it as it merges:

```sh
gh extension install github/gh-stack   # once
gh api 'repos/rayo-lang/rayo/stacks?pull_request=<below>' \
  -q '.[] | "\(.number): \([.pull_requests[].number] | map(tostring) | join(" "))"'   # <stack>: its pull requests, bottom to top
gh stack link <stack> <n>              # adds <n> to the top of that stack
gh stack link <below> <n>              # where it prints nothing: starts a stack of the two, bottom to top
```

If `<below>` is not the last number the stack lists, show it to the user: a stack is one chain.

**Done when:** the pull request is open with the right base, and a stacked one is linked into its stack: `gh api 'repos/rayo-lang/rayo/stacks?pull_request=<n>' -q '.[].pull_requests[].number'` lists it right after the one below it.

## 4. Work the bottom

Work only on a bottom pull request: one per stack. Those above it wait as they are, unreviewed and without CI, since a change below can change them; until their turn they show the bottom's old commits.

Take the bottom through this loop, where `<head>` is `git rev-parse HEAD` after your last push:

1. **Review.** Start a fresh agent, isolated: it knows only the diff between the pull request and its base. Give it this prompt word for word, with `<base>` the base branch's commit (`gh pr view <n> -R rayo-lang/rayo --json baseRefOid -q .baseRefOid`) and `<head>` filled in, and nothing more: no number, no description, nothing of the change's history or of earlier reviews.

   > In a new worktree of this repository, check out `<head>` detached, and there load the `code-review` skill with `<base>` as the fixed point. No one will answer a question: where the skill would ask one, go on as it says to when there is no answer. Report the findings only, ranked blocking, should-fix and nit, each with its file, line and fix.
2. **Fix.** Fix every blocking and should-fix finding that holds, and the nits you judge worth fixing, keeping the diff under 1000 changed lines. A review that leaves no blocking or should-fix finding that holds approves the pull request: the nits are yours to settle, and fixing them needs no other review. Commit the fixes on top of the pushed head, which stays as it is. Correct the title and body with `create-pr` where the change moved under them. Run `swift test`; `python3 -I scripts/check_docs.py` when it changes Markdown or `scripts/`, or deletes a file; and `python3 -m unittest discover -s scripts` when it changes `scripts/`. Once they pass, push with `git push origin <branch>`, and move each held branch stacked on it, as step 2 says.
3. **Review again.** After fixing a blocking or should-fix finding, go back to **Review** with a fresh reviewer on the new head.
4. **CI.** Wait for the pull request to show `<head>`, then for `CI`, the one check `main` requires, to report on it:

   ```sh
   gh pr view <n> -R rayo-lang/rayo --json headRefOid -q .headRefOid               # repeat until it prints <head>;
                                                                                # a head you didn't push: show it to the user
   gh pr checks <n> -R rayo-lang/rayo --watch --interval 30                       # repeat until a row named CI shows
   gh pr view <n> -R rayo-lang/rayo --json mergeStateStatus -q .mergeStateStatus  # CLEAN
   ```

   `CI` registers last, once every job it waits on has finished. Act on what the watch ends with:

   - **No `CI` row**, whatever the other rows show; or exit 1 and "no checks reported", before the run registers: wait 30 seconds and watch again.
   - **No checks five minutes after the push:** ask for the merge state first, since GitHub runs no CI on a `DIRTY` pull request; move a `DIRTY` one as below. Otherwise the push lost its event: run `git commit --allow-empty -m "ci: run the checks again"` and push it with `git push origin <branch>`; the empty commit changes no file, so the review of the head before it stands.
   - **`CI` fails:** ask how its run ended, with `<head>` in full: `gh run list -R rayo-lang/rayo --commit <head> --workflow CI --json databaseId,conclusion -q '.[] | "\(.databaseId) \(.conclusion)"'`. `cancelled`: rerun it with `gh run rerun <run-id> -R rayo-lang/rayo` and watch again. `failure`: read the failed jobs with `gh run view <run-id> -R rayo-lang/rayo --log-failed`. A failing build, test or docs check is a finding; fix it under **Fix**. A step that failed fetching packages or reaching a server before the build ran is the runner's: rerun the failed jobs with `gh run rerun <run-id> -R rayo-lang/rayo --failed` and watch again, and show it to the user if the rerun fails the same way. Any other conclusion: show it to the user and wait.
   - **`UNKNOWN`:** GitHub is still computing the state; ask again after 30 seconds. **`DIRTY`:** `main` moved under it with a conflicting change; move it as step 5 says for a `main` that moved past it. **Any other state:** show it to the user and wait.

**Done when:** a review approved a head `<reviewed>`, leaving no blocking or should-fix finding that holds, and `<head>` is `<reviewed>` with at most the nit fixes you made after it, or keeps that head whole: one with the same tree (`git rev-parse <reviewed>^{tree} <head>^{tree}` prints one tree twice), or one that the move's `git range-diff --creation-factor=100 <fork>..<reviewed> <onto>..<head>` shows as the same commits moved, every pair marked `=`. The pull request's head is `<head>`, its `CI` row shows `pass`, and GitHub reports it `CLEAN`.

## 5. Merge it

Merge it yourself, squashed, at `<head>`, once its base is `main`: `gh pr view <n> -R rayo-lang/rayo --json baseRefName -q .baseRefName` prints `main`. Its head holds `main` as it is now, since GitHub merges a stack only with a linear history and CI tested its head on the `main` it saw: `git merge-base --is-ancestor origin/main <head>` after `git fetch origin`. When `main` moved past it, move it onto `origin/main`, its `<heads>` `git rev-parse origin/main`, and take it through step 4 again: at **CI** when the move's `git range-diff --creation-factor=100` marks every pair `=`, at **Review** otherwise.

Merge it through the asynchronous endpoint, the only merge GitHub runs for a pull request linked into a stack. It merges every open pull request below `<n>` along with it, so `<n>` must be the bottom, or the ones below it merge unreviewed; and `sha` merges `<head>` and nothing pushed after it, which `gh stack merge` doesn't send:

```sh
gh api -X PUT repos/rayo-lang/rayo/pulls/<n>/merge-async \
  -f merge_method=squash -f merge_action=direct_merge -f sha=<head> \
  -q '.status + " " + (.details.uuid // .details.message)'
gh api repos/rayo-lang/rayo/pulls/<n>/merge-async/<uuid> \
  -q '.status + " " + (.details.sha // .details.message)'   # pending, then merged or failed
```

Act on what each call prints:

- **`pending <uuid>`**, a 202: poll it every 10 seconds until it prints `merged` or `failed`; still `pending` after 10 minutes, show it to the user. A 409, with `gh: HTTP 409` and exit 1, is a merge of `<n>` someone else started, maybe with other options: show it to the user and wait for it.
- **`merged <commit>`** from the poll: the merge is done. `merged` from the submit means `<n>` had merged already.
- **`failed <reason>`** with `gh: HTTP 400`, from the submit: `<n>` is a draft or closed; show it to the user.
- **`failed <reason>`** from the poll: a head past `<head>`, pushed from another clone: `git fetch origin` and `git merge --ff-only origin/<branch>` (where it isn't a fast-forward, show it to the user), take the pull request's new head as `<head>`, move each held branch stacked on it as step 2 says, and take it through step 4 again from **Review**; a conflict: `main` moved, so move it as this step says for a `main` that moved past it; a rule, or any other reason: show it to the user and wait. Then merge again.
- **A JSON body printed whole**, with `gh: <message> (HTTP <code>)`: GitHub refused the request before it started; show it to the user.

After a merge, the branch directly above `<n>`, if any, moves by step 6, and if it is held, it has first claim on the place the merge freed, and opens after its move. A pull request closed unmerged leaves each branch above it holding its commits: show the user those branches and wait. Then open held branches by steps 2 and 3 while places are free.

**Done when:** `gh pr view <n> -R rayo-lang/rayo --json state,mergeCommit -q '.state + " " + .mergeCommit.oid'` prints `MERGED` and a commit for which `git merge-base --is-ancestor <commit> origin/main` exits 0 after `git fetch origin`.

## 6. Move the next one onto `main`

When the bottom merges, GitHub retargets the pull request above it to `main` and leaves its branch as it was: below its own commits it still holds the merged one's, which the squash replaced with one commit on `main`, and maybe older copies of ones that merged before. Check the retarget with `gh pr view <next> -R rayo-lang/rayo --json baseRefName -q .baseRefName`: a base still not `main` a minute after the merge is a retarget that failed, so run `gh pr edit <next> -R rayo-lang/rayo --base main` before the move pushes, since a push to a pull request into any other branch runs no CI. A held branch above it has no pull request to retarget.

Move it onto `origin/main`, its `<heads>` the heads of the merged pull request's branch, which `gh pr view <merged> -R rayo-lang/rayo --json headRefName -q .headRefName` names.

Then an open pull request gets its body corrected with `create-pr` for the diff it now has against `origin/main`, and the move's push runs CI on it; a held branch opens by steps 2 and 3 if a place is free. An open pull request is the bottom now: go back to step 4. A held branch stays held until step 2 lets it open.

**Done when:** [Move a branch](#move-a-branch)'s Done check passes with `<onto>` `origin/main`; an open pull request's `baseRefName` prints `main`, and a held branch has passed step 2's Done.

## Move a branch

A branch moves onto `<onto>`, `origin/main` or `origin/<lower-branch>`, carrying only its own commits: those above `<heads>`, the commits of what sat below it as this branch saw them. The step that moves it says what `<onto>` and `<heads>` are.

**The heads of a branch** are every commit it has pointed at on GitHub, pushed from any clone, with a pull request or without one. GitHub's activity record of the branch lists them:

```sh
gh api --paginate 'repos/rayo-lang/rayo/activity?ref=refs/heads/<lower-branch>&per_page=100' \
  -q '.[] | .before, .after' | grep -v '^0\{40\}$' | sort -u
```

Paste them in place of `<heads>`, one argument each. A record that prints nothing has lost the branch's heads: show it to the user. Work in the worktree that has `<branch>` checked out (`git worktree list`), or run `git switch <branch>` where none does:

```sh
git fetch origin
git rev-list --left-right --count <branch>...origin/<branch>   # 0 0: level with origin/<branch>
git rev-parse origin/<branch>                     # <old>
git fetch origin <heads>
git merge-base <old> <heads>                      # <fork>
git log --oneline <old> --not <heads>             # its own commits
git rebase --onto <onto> <fork> <branch>
git range-diff --creation-factor=100 <fork>..<old> <onto>..<branch>
```

`<fork>` is the newest commit `<old>` shares with `<heads>`: the commits above it are this branch's own, which the `git log` line lists. `range-diff` pairs each of them with its rebased copy, `=` where the patch is unchanged and `!` where its patch changed, by a resolved conflict or by context `<onto>` changed, and lists no other; a commit marked `<` alone was dropped as empty, so check its change is on `<onto>`. Act on what the lines show:

- **Behind**, `rev-list` printing `0` and a count above `0`: run `git merge --ff-only origin/<branch>` first.
- **Ahead or diverged**, a first count above `0`: show it to the user.
- **`git fetch origin <heads>` fails:** show it to the user.
- **No commit of its own**, a `git log` line that lists none: `<heads>` aren't the branch below's; take them again before you rebase.
- **`<onto>` moved after the push**, a Done check that fails only because a later `git fetch` moved it: move it again onto `<onto>`, its `<heads>` `git rev-parse origin/main` when `<onto>` is `origin/main`, or the heads of the branch below otherwise; a bottom then goes through step 5 again.
- **Any other failing Done check:** put the branch back with `git reset --hard <old>`, and, if you pushed, `git push --force-with-lease=<branch>:<pushed> origin <branch>`, `<pushed>` the head you pushed; then take its `<heads>` again and move it again, and show it to the user if the check fails again.

Resolve each conflict to keep both sides: the change this branch makes, and everything `<onto>` gained since `<fork>`, every review fix among it. Check both are still there after the rebase, in the files this branch moved or renamed too. Run the checks step 4's **Fix** names, then push with `git push --force-with-lease=<branch>:<old> origin <branch>`, which pushes only over the `<old>` you moved. Then move each held branch stacked on this one, as step 2 says.

**Done when:**

- `git merge-base --all <old> <heads>` prints one commit, `<fork>`, and `git log --oneline <old> --not <heads>` lists at least one.
- None of the subjects `git log --format=%s <fork>..<old>` prints is among those `git log --format=%s <fork>..<onto> | sed 's/ (#[0-9]*)$//'` prints (a squash merge's subject, less the ` (#<n>)` GitHub adds to it), nor, after a merge, among the merged pull request's (`gh pr view <merged> -R rayo-lang/rayo --json commits -q '.commits[].messageHeadline'`), unless `git show` shows that commit makes a change neither makes.
- `git merge-base --is-ancestor <onto> origin/<branch>` exits 0.
- `git range-diff --creation-factor=100 <fork>..<old> <onto>..origin/<branch>` pairs each commit above `<fork>` with its rebased copy, `=`, or `!` with nothing changed under `## Commit message ##` and only hunks a resolved conflict or `<onto>`'s context changed, or marks it `<` alone with its change already on `<onto>`, and lists no other. A hunk header that reads `@@ Commit message` is context: only the lines under `## Commit message ##` are the message.
- The checks pass, and each held branch stacked on it has moved too.
