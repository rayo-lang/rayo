---
name: implement
description: "Implement an issue, spec or set of tickets end to end: build it test-first, open its pull request, and take it through review until approved. Use when handed work to implement."
---

Implement the work described by the spec, tickets or issue you were given. Branches, pull requests and reviews follow the repo's rules.

Work on a branch of your own. Use /tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Commit your work, and open a pull request.

## Review

Start a fresh reviewer agent on the pull request. Fix every finding that blocks approval, and apply the nits you judge worth it. Send each round back to the same reviewer, with what you fixed and what you declined and why, until it approves.

## Hand back

Report the pull request and its approved head to whoever gave you the work, and stop: the merge is theirs. Hand back early with any decision only they can make. When they send you back, because CI failed or the pull request conflicts, fix it and take it through the same reviewer again.
