---
name: implement
description: "Implement an issue, spec or set of tickets end to end: build it test-first, open its pull request, and take it through review until the review approves. Use when handed work to implement, such as `/implement <issue>`."
---

Implement the work described in the spec, tickets or issue you were given. Fetch each from the issue tracker with its comments, and read what each points to.

Every step below that touches a branch, a commit or a pull request follows `docs/agents/pull-requests.md`.

## 1. Build

Work on a branch of your own, cut from `main` and named as `docs/agents/pull-requests.md` says.

Use /tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Commit your work to that branch.

**Done when:** every acceptance criterion holds, the full test suite passes, and every change is committed.

## 2. Review

Open the pull request with `create-pr`. When the open pull request limit is already reached, the work waits on its branch: hand back (step 3) saying so, and open the pull request when you are sent back.

Then run the review loop with a reviewer agent of your own, as the Reviewing section of `docs/agents/pull-requests.md` says:

1. Start one fresh reviewer agent, whose prompt gives the pull request's number, head and base, and nothing more.
2. Fix every blocking and should-fix finding, or decline it with a reason. Apply each nit you judge improves the change, and decline the rest with a reason.
3. Push, and continue the same reviewer with the round: the new head, what you fixed, and what you didn't and why.
4. Repeat from 2 until a round approves. A decline the reviewer rejects is fixed, or goes to whoever gave you the work to decide (step 3), and is never argued again.

Every later round of this pull request goes to the same reviewer.

**Done when:** the reviewer's latest round approves the pull request's current head.

## 3. Hand back

Report to whoever gave you the work, and stop: the merge is theirs. The report gives:

- the pull request's number and URL, and the head its reviewer approved;
- the branch and the worktree it is checked out in;
- each finding you declined, with its reason, one line each.

A hand-back before approval says instead what it waits on: a decision on a rejected decline, a question only the user can answer, or a free slot under the open pull request limit.

## 4. When the work comes back

Whoever gave you the work may send you back to it:

- **A slot is free under the open pull request limit:** open the pull request and review it, from step 2.
- **Its CI failed, or it no longer merges cleanly into `main`:** turn its auto-merge off if it is on, fix the failure in a new commit or rebase onto `main`, and push. Send the round to the same reviewer; a rebase round lists what the rebase changed. Then hand back again as step 3 says, once the round approves.
