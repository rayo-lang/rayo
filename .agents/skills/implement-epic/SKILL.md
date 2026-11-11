---
name: implement-epic
description: Implement an epic's sub-issues in parallel lanes, one fresh /implement subagent per issue.
disable-model-invocation: true
---

# Implement epic

An **epic** is an issue whose sub-issues, and the blocking edges between them, lay out all of its work. You build it in **lanes**, 2 unless the user gives another number: each lane holds one sub-issue, built by an implementer subagent of its own. You check the epic, fill the lanes, and merge.

## 1. Check the epic

The epic is executable when it has sub-issues, every open one is ready for an agent, every blocker is a sub-issue or closed, and the edges form no cycle. Otherwise, label the epic as needing triage, tell the user what is missing, and stop.

## 2. Fill the lanes

The **frontier** is every open sub-issue whose blockers are all closed and that no lane holds. For each free lane, claim the next issue on the frontier and start a new implementer for it, in the background and in a worktree of its own, with the prompt `/implement <issue URL>` and nothing else.

A new issue always gets a new implementer: continue one only about its own pull request. Keep the lanes within the repo's limit on open pull requests.

## 3. Merge

An implementer hands back once its pull request's review approves. Merge it as the repo's rules say. When CI fails or the pull request conflicts, send it back to its implementer. When it hands back a question only the user can answer, ask the user and pass the answer on.

Once it merges, check its sub-issue closed, remove the lane's worktree, and fill the lane again.

**Done when:** every sub-issue is closed by a merged pull request. Close the epic, and report each sub-issue with the pull request that closed it.
