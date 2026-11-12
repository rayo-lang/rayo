---
name: implement-epic
description: Implement an epic's sub-issues in parallel lanes, one fresh /implement subagent per issue.
disable-model-invocation: true
---

# Implement epic

An **epic** is an issue whose sub-issues, and the blocking edges between them, lay out all of its work. You build it in **lanes**, 2 unless the user gives another number: each lane holds one sub-issue, built by an implementer subagent of its own. You check the epic, fill the lanes, and merge.

## 1. Check the epic

The epic is executable when it has sub-issues, every open one is triaged as ready for an agent or ready for a human, every blocker is a sub-issue or closed, and the edges form no cycle. Otherwise, move the epic's triage state to needing triage, tell the user what is missing, and stop.

## 2. Fill the lanes

The **frontier** is every open sub-issue whose blockers are all closed, that no lane holds, and that no one else has claimed. For each free lane, claim the next issue on the frontier that is ready for an agent, and start a new implementer for it, in the background and in a worktree of its own, with the prompt `/implement <issue URL>` and nothing else.

An issue ready for a human is the user's to build. Tell them once, when it reaches the frontier, and fill the lanes with the rest: it holds back only the issues it blocks.

A new issue always gets a new implementer: continue one only about its own pull request. Keep the lanes within the repo's limit on open pull requests, and count the free slots again on each hand-back. When no lane is running and none can start while sub-issues stay open, tell the user what each open one waits on, and stop.

## 3. Merge

An implementer hands back once its pull request's review approves. Merge it as the repo's rules say. When it can't merge, because CI fails or it conflicts with or falls behind the main branch, send it back to its implementer. When it hands back a pull request that can't open yet, send it back once a slot is free. When it hands back a decision for the user, such as a decline its reviewer rejected, ask the user and pass the answer on in their words.

Once it merges, check its sub-issue closed, remove the lane's worktree, and fill the lane again.

**Done when:** every sub-issue is closed. Close the epic, and report each sub-issue with the pull request that closed it.
