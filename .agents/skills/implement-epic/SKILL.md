---
name: implement-epic
description: Implement an epic's sub-issues in parallel lanes, one fresh /implement subagent per issue, merging each approved pull request.
disable-model-invocation: true
---

# Implement epic

You orchestrate an **epic**: an issue whose sub-issues, and the blocking edges between them, lay out all of its work. You get every sub-issue built and merged, each in a **lane** of its own, where a fresh implementer subagent runs `/implement` on it and takes its pull request through review with a reviewer of its own. Your work is the graph, the lanes and the merges.

You are given the epic's issue, and may be given a number of lanes; it is 2 when none is given.

## 1. Check the epic is executable

Read the epic, its sub-issues, and each open sub-issue's blockers:

```sh
gh issue view <epic> -R rayo-lang/rayo --comments
gh api repos/rayo-lang/rayo/issues/<epic>/sub_issues --paginate \
  --jq '[.[] | {number, title, state, url: .html_url, labels: [.labels[].name], assignees: [.assignees[].login]}]'
gh api repos/rayo-lang/rayo/issues/<sub-issue>/dependencies/blocked_by --paginate --jq '[.[] | {number, state}]'
```

The epic is executable when all of these hold:

- the epic has sub-issues, and carries none of `needs-triage`, `needs-info` or `wontfix`;
- every open sub-issue is labelled `ready-for-agent`;
- every blocker of an open sub-issue is a sub-issue of the epic, or closed;
- the blocking edges between the sub-issues form no cycle.

When one fails, the epic is not executable yet: label it `needs-triage` (`gh issue edit <epic> -R rayo-lang/rayo --add-label needs-triage`), tell the user each condition that fails and the sub-issues behind it, and stop.

**Done when:** every condition holds, or the epic is labelled `needs-triage` and the user has the list.

## 2. Fill the lanes

The **frontier** is every open sub-issue whose blockers are all closed, with no assignee, and in no lane, in the epic's sub-issue order.

Each lane ends in an open pull request, so the lanes running at once fit the repo's limit on open pull requests: count the open pull requests with `gh pr list -R rayo-lang/rayo --state open`, and leave out those that lanes of this epic opened. When no lane fits, tell the user what holds the slots, and stop.

For each free lane that fits, take the first issue of the frontier:

1. Claim it: `gh issue edit <n> -R rayo-lang/rayo --add-assignee @me`.
2. Start a new implementer subagent for it, in the background and in a worktree of its own, whose whole prompt is `/implement <issue URL>`.

A new issue always gets a new implementer. An implementer's context belongs to its own issue, so continue one only about that issue's pull request.

A free lane with an empty frontier waits for a merge to unblock a sub-issue.

**Done when:** every free lane that fits holds an issue, or the frontier is empty.

## 3. Merge what comes back

Implementers notify you when they hand back; wait for those notifications rather than checking on them. An implementer hands back once its pull request's review approves, with the pull request, the approved head, and its branch and worktree. For each hand-back:

1. Check that the pull request's head is still the approved head: `gh pr view <N> -R rayo-lang/rayo --json headRefOid,state,mergeable`.
2. Merge it as the repo's pull request rules say: auto-merge, pinned to the approved head, with a squash subject and message.
3. Wait in the background with `gh pr checks <N> -R rayo-lang/rayo --watch`, then read the pull request's state again.
   - **Merged:** go to step 4.
   - **CI failed, or the pull request conflicts with `main`:** continue that implementer with what failed. It fixes the failure, takes the round through its reviewer, and hands back again; start this step over when it does.

An implementer that hands back waiting on something else waits in its lane:

- **A free slot under the open pull request limit:** continue it once a pull request closes and a slot is free.
- **A decision or question only the user can answer:** put it to the user, and continue the implementer with the user's answer, in the user's words.

**Done when:** the lane's pull request has merged.

## 4. Free the lane

1. Check that the merge closed the sub-issue, and close it with `gh issue close <n> -R rayo-lang/rayo` if not.
2. Remove the lane's worktree with `git worktree remove <path>`, and delete its local branch.
3. Go back to step 2: the merge may have unblocked more of the frontier.

## 5. Close the epic

When every sub-issue is closed, close the epic with a comment that lists each sub-issue and the pull request that closed it, and report the same list to the user.

**Done when:** every sub-issue is closed by a merged pull request, the epic is closed, and no lane's worktree is left.
