# Reviewer prompt

## The argument review (from round 65)

The review checks the soundness argument, [docs/15-soundness.md](../docs/15-soundness.md), step by step, instead of hunting for programs. It is bounded: it ends when every step has a verdict of HOLDS. A step that fails is fixed in the spec, or in the argument when only the argument was wrong, and then only that step, and the steps that cite the changed rule, are checked again. Expressiveness is tested against the Must accept criteria of [docs/hard-cases.md](../docs/hard-cases.md), and consistency, clarity and wording are not part of this review.

Eleven reviewers run in parallel. Each gets the prompt below with `{STEPS}`, sections of docs/15, and `{SWEEP}`, the spec text it searches for rules no step covers, replaced by one line:

1. Steps: The invariants, Ownership, Borrows and exclusivity. Sweep: docs/01-values-and-ownership.md and docs/12-compilation-model.md.
2. Steps: Dependencies, Covered, Rules 1 and 2, Rule 3. Sweep: docs/02-views-and-dependencies.md from its start through rule 3.
3. Steps: Rule 4, Rule 5, Rule 6, Mutable views. Sweep: docs/02-views-and-dependencies.md from rule 4 through "Lock guards are released on the thread that took them".
4. Steps: Destruction as a use, Precise dependencies, `rebind`, Projections and accessors. Sweep: docs/02-views-and-dependencies.md from "Precise dependencies (opt-in)" to its end.
5. Steps: Closures and function values, Generic code and existentials. Sweep: docs/05-protocols-generics-and-closures.md.
6. Steps: The dynamic tier. Sweep: docs/03-handles-and-objects.md.
7. Steps: Memory and allocators. Sweep: docs/06-memory-and-allocators.md.
8. Steps: Grace periods and checkpoints. Sweep: docs/08-grace-periods-and-checkpoints.md.
9. Steps: Threads. Sweep: docs/07-concurrency.md.
10. Steps: Types and layout, Compile time and reflection. Sweep: docs/04-types.md, docs/10-compile-time.md, and docs/13-grammar.md for constructs the prose gives no meaning.
11. Steps: Checks and panics, The unsafe boundary. Sweep: docs/09-c-interop.md and docs/11-errors-and-safety.md.

A change to this prompt or to the partition changes what a review counts, so [findings-log.md](findings-log.md) records it in its Reviewers column.

```text
You are checking the soundness argument of the Rayo language design spec in /Users/alexander/dev/rayo3. The spec's rules are docs/01-*.md through docs/14-*.md. docs/15-soundness.md argues that they leave safe code (everything outside `unsafe` blocks, `unchecked` blocks and C) with no undefined behavior: it states five invariants (Live, Valid, Exclusive, Owned, Race-free) and the property Covered, then gives, for each rule, why it keeps them, citing the rules each step relies on.

YOUR STEPS: these sections of docs/15-soundness.md: {STEPS}.
YOUR SWEEP: {SWEEP}.

1. Check every step in your sections, in order. A step is a bullet or paragraph that claims a rule keeps an invariant, or that the argument relies on. Read the rules it cites, in full and in context, and the rules they depend on, wherever they are, and give one verdict:
   - HOLDS: the rules say what the step claims, and the claim follows from them.
   - HOLE: the claim doesn't follow. Give a program that uses only safe code, or C and `unsafe` code that keep exactly what docs/09 "What C must uphold" and docs/11 "Unsafe code" ask, and that breaks an invariant. Give the rule change that closes it.
   - UNSTATED: the claim relies on something the spec doesn't say. Give the rule the spec needs.
   - MISCITED: the claim holds, but not by the rule cited. Give the right one.
   - OVERSTATED: the step claims more than the rules give, or more than the argument needs. Give the corrected step.
2. Sweep your files for rules the argument doesn't cover: a rule or an exemption that lets safe code do something, such as accept a program, skip a check, drop a dependency, end a borrow, or let a value reach another thread, that no step of docs/15 justifies. For each, name the invariant it could break, then give the missing step, or show the hole.
3. Report a design finding only where a step shows that a restriction keeps no invariant, so that it forbids a pattern for no soundness reason. Name the rule and the step.

Report nothing else: no consistency, clarity, wording or formatting, and no programs outside the steps. A program belongs in a report only as the evidence for a HOLE.

Output one line per step, in order: the section, the step's bold lead or first words, the verdict, and, for any verdict but HOLDS, the evidence and the fix. Then the sweep's findings, then any design findings. Re-read the cited text before reporting any verdict but HOLDS.

Do not edit any files. Use /usr/bin/grep for searching.
```

## Earlier prompts

Rounds 60 to 63 used the full review below, over the partition 01+03+12, 02, 04, 05+examples, 06+08, 07+README, 09+11, 10+13, 14, hard-cases, soundness-probes. Round 64 used the ownership review after it. `soundness-probes.md` was retired after round 64, and the must-accept items it held that hard-cases.md didn't cover moved there.

```text
You are a full, adversarial reviewer of the Rayo language design spec in /Users/alexander/dev/rayo3: README.md, docs/01-*.md through docs/14-*.md, docs/hard-cases.md, docs/soundness-probes.md, and examples/. Rayo is a general-purpose systems language with Swift-style syntax, ownership and borrowing, and strong C interop. Game development is one priority, not the language's purpose. Its central claim: safe code (outside `unsafe` blocks and C) has no undefined behavior, no data races, no use-after-free, and no reads of invalid values, in every build.

YOUR ASSIGNMENT: read these files in full, every line, top to bottom: {FILES}. Eleven reviewers split the spec so that every line is read by one of them; these lines are yours. Your review is not limited in any other way: follow any rule, term or link into any other file as far as you need, and report anything you find, wherever it is.

Review everything, in every dimension:

1. Soundness. A program that uses only safe code (or C that upholds exactly what docs/09 "What C must uphold" demands, or unsafe code that keeps exactly the promises the spec states for it) and reaches undefined behavior, a data race, a use-after-free, a double free or double destruction, a skipped destruction that breaks an invariant, a read of an invalid or uninitialized value, a misaligned access, a type confusion, memory reused while still read, a `deinit` on the wrong thread or run twice or never when its effect is relied on, or a deadlock the spec claims can't happen. Also rules that contradict each other such that either choice is unsound, and constructs the grammar allows that the prose never gives a meaning or restriction.
2. Consistency. Two statements that disagree; a term with two meanings or a concept with two names; a term used before or without definition; a cross-reference whose target doesn't say what the referring text claims; grammar (docs/13) that disagrees with prose or examples; code examples (in docs/ and examples/) that break the spec's own rules; probes or hard cases whose expected outcome or ID tag disagrees with the rules; lists that claim completeness but miss an item another chapter adds; formatting slips (fused lines, a list or table missing its blank line, inconsistent bold-label punctuation within one list).
3. Clarity. A sentence so convoluted that its rule is hard to extract (give a clearer rewrite that keeps every rule); a concept named before it is explained; a section that opens with prose that states no rule.
4. Worth saying. The author wants every sentence to earn its place. Flag: common sense or restating the sentence before; disclaimers, hedges, defensive framing ("this is not X"), slogans, marketing; draft residue (earlier versions, "now", "no longer", design history, version numbers); redundancy (the same rule stated fully in two places where one should state it and the other link; say which keeps it); meta commentary about the document, navigation lines; decorative comparisons to other languages that define nothing (a comparison in 14's Rejected/Why parts that explains a decision is fine); game framing of a general rule (examples may use game code); library or tool content that doesn't define the language (diagnostic wording, tool or style advice, "prefer X", workarounds, performance tips, how std implements something); em dashes (the text must have none); examples should come first, before the rule they illustrate, where a section introduces something new.
5. Design. A rule that forbids a reasonable pattern without a soundness reason.

The author's standing directions, for context: don't forbid reasonable patterns; safe code has no unsynchronized mutable globals; no game-specific concepts in the language; coroutines (task functions), not actors; the spec defines the language, not libraries; C interop is unsafe.

For each finding give: a category (soundness, consistency, clarity, worth-saying, design), the file:line locations, a concrete program or quote, why it is wrong, and the exact fix (replacement text where short, or the precise rule change). Rank most serious first, soundness before the rest. Verify every finding by re-reading the relevant text in context before reporting it; drop anything the spec already handles, and say where you checked. Report every finding that survives verification; be concise per finding. If after a careful review nothing survives, reply exactly "NO FINDINGS".

Do not edit any files. Use /usr/bin/grep for searching.
```

Round 64 limited eleven reviewers to ownership and borrow checking, over the partition 01, 02, 03+06, 04, 05+examples, 07+08, 09+11, 10+12+13, 14+README, hard-cases, soundness-probes:

```text
You are an adversarial reviewer of the Rayo language design spec in /Users/alexander/dev/rayo3: README.md, docs/01-*.md through docs/14-*.md, docs/hard-cases.md, docs/soundness-probes.md, and examples/. Rayo is a general-purpose systems language with Swift-style syntax, ownership and borrowing, and strong C interop. Its central claim: safe code (outside `unsafe` blocks and C) has no undefined behavior, no data races, no use-after-free, and no reads of invalid values, in every build.

THIS ROUND HAS ONE SUBJECT: OWNERSHIP AND BORROW CHECKING. Report only findings about it, and nothing else. It covers: values and owners, moves, copies and clones, what takes a value and what borrows it; destruction (who destroys a value, when, in what order, exactly once, and when destroying counts as a use); partial moves, maybe-initialized places and reinitialization; parameter conventions (borrowed, `mutable`, `owned`, `keep`), `self` conventions and the shared/`mutating`/`consuming` forms; bindings (`let`, `var`, `&`, `owned`), pattern bindings and `rebind`; evaluation order and when a call's borrows begin and end; temporaries and how long they live; exclusivity and which places overlap; views, scoped values, dependency sets and rules 1 to 6; sealed and unsealed types; `outlives`, `borrows`, `where` clauses on results and yields; projections, `read`/`modify`/`get`/`set` accessors and access-bound projections; iteration borrows; closures: captures, kinds, function values as views, `Closure<F>`, `some F`; existential views and unpacking; lock guards and other borrows `Synchronized` types lend; dynamic accesses (objects, weak pointers, `Slice`, thread-locals); lending work to other threads and `Sendable` as it bears on borrows; borrows across `await` and checkpoints and what a wait may borrow; ownership crossing to and from C; how `unsafe` code and raw pointers must respect borrows, including `ptr(to:)`; and how generics, compile-time code and reflection read or write places under these rules.

YOUR ASSIGNMENT: read these files in full, every line, top to bottom: {FILES}. Eleven reviewers split the spec so that every line is read by one of them. Follow any rule, term or link into any other file as far as you need, and report any ownership or borrowing finding you find, wherever it is.

Hunt hardest for soundness: a program that uses only safe code (or C that upholds exactly what docs/09 "What C must uphold" demands, or unsafe code that keeps exactly the promises the spec states for it) and reaches a use after move, a double free or double destruction, a destruction skipped where an invariant relies on it, a use-after-free, a dangling view, two live exclusive accesses to one place, a write while a shared borrow is live, a borrow that escapes its scope or its thread, or a read of an invalid or uninitialized value. Combine features: generics with closures, existentials with accessors, patterns with partial moves, tasks with guards, C callbacks with views. Write the program out.

Then report, still only on this subject:
1. Consistency. Ownership or borrowing rules that disagree; a term with two meanings; a cross-reference whose target doesn't say what is claimed; an example or probe whose stated outcome breaks these rules.
2. Clarity. An ownership or borrowing rule stated so that its meaning is hard to extract (give a clearer rewrite that keeps every rule), or used before it is defined.
3. Design. An ownership or borrowing rule that forbids a reasonable pattern without a soundness reason.
4. Worth saying. Restated, redundant or filler text about ownership or borrowing (say which place keeps the rule).

The author's standing directions, for context: don't forbid reasonable patterns; safe code has no unsynchronized mutable globals; the spec defines the language, not libraries; C interop is unsafe.

For each finding give: a category (soundness, consistency, clarity, design, worth-saying), the file:line locations, a concrete program or quote, why it is wrong, and the exact fix (replacement text where short, or the precise rule change). Rank most serious first, soundness before the rest. Verify every finding by re-reading the relevant text in context before reporting it; drop anything the spec already handles, and say where you checked. Report every finding that survives verification; be concise per finding. If after a careful review nothing survives, reply exactly "NO FINDINGS".

Do not edit any files. Use /usr/bin/grep for searching.
```
