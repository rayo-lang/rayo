# Review findings log

This log tracks what each review round of the Rayo spec found, and whether the rounds are making the design better. `findings.csv` holds the item-level record from round 61 on. This file holds the per-round trend from round 1, the spec's size over time, and a reading of both.

## Method

**A round** is one pass of independent reviewers over the spec, followed by validating every finding and applying the fixes. From round 60 to 63, eleven reviewers each read one part of the spec in full, with no limit on scope: 01+03+12, 02, 04, 05+examples, 06+08, 07+README, 09+11, 10+13, 14, hard-cases, soundness-probes. Round 64 kept eleven reviewers and full coverage but limited them to ownership and borrow checking (setup J below). From round 65, a review checks the soundness argument in `docs/15-soundness.md` step by step instead (setup K below). The prompts are in `reviewer-prompt.md`.

**Categories.** Each finding carries one:

- **soundness**: a program the spec accepts that breaks memory or thread safety (a `hole`), or a rule gap where one reading would (a `gap`);
- **consistency**: two places that disagree, or a rule that doesn't match its own example;
- **clarity**: text that is correct but hard to read;
- **worth-saying**: filler, restatement, or content that doesn't belong in a language spec;
- **design**: a rule that works but forbids a reasonable pattern or leaves a needed feature out;
- **formatting**: layout and punctuation slips.

**`findings.csv` columns.** `round, reviewer, file, category, severity, origin, outcome, summary`.

- `severity` is filled for soundness only: `hole` or `gap`.
- `origin` is `regression-rN` when the finding sits in text that round N's fixes introduced, checked against the edit history, and `latent` when the text predates that round. Round 61's rows are `unknown`.
- `outcome` is `fixed`, `duplicate` (another reviewer's finding already covered it), or `declined` (checked and found not to be a problem).
- From round 62, one row may group several small clarity or worth-saying items from one report, so row counts are not item counts. Soundness, consistency and design findings are one row each.

**Rounds 1 to 60** predate this file. Their numbers were recovered afterwards from the review reports. In the table, `s` marks a number stated at the time, and `d` a number counted afterwards from the saved reports. A blank cell means no data. The reviewer setup changed several times, so the columns mean slightly different things across setups:

- **A–B** (R1–R4): two reviewers, split by hard-case groups and then by category.
- **C–F** (R5–R48): one soundness reviewer and one consistency reviewer, with scope and hard cases added to the consistency reviewer at times.
- **G** (R49–R55): F plus a worth-saying reviewer.
- **H** (R56–R59): G plus four area soundness reviewers.
- **I** (R60–R63): eleven reviewers, each owning part of the spec, every category.
- **J** (R64): eleven reviewers over the whole spec in a new partition (01, 02, 03+06, 04, 05+examples, 07+08, 09+11, 10+12+13, 14+README, hard-cases, soundness-probes), each looking only at ownership and borrow checking. Its counts measure that one area, so they don't compare directly with setup I's.
- **K** (R65 on): eleven reviewers, each checking sections of `docs/15-soundness.md` step by step and sweeping its chapters for rules no step covers. Each step gets one verdict, so counts are per step, and a review ends when every step holds.

**Serious** is a reviewer's top severity through R48, the count of data races, use-after-free, type confusion and uninitialized reads for R49–R59, and `hole` rows from R61 on.

## Trend by round

| R | Reviewers | Total | Soundness | Serious | Consistency | Clarity | Worth-saying | Design | Regressions |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2 (A) | 37 s |  | 12 d |  | n/a | n/a | n/a | n/a |
| 2 | 2 (A) | ~30 distinct s |  | 7 d |  | n/a | n/a | n/a |  |
| 3 | 2 (B) | 41 d | 14 d | 3 s | 27 s | n/a | n/a | n/a |  |
| 4 | 2 (B) | 38 s | 18 d | 5 s | 20 s | n/a | n/a | n/a |  |
| 5 | 2 (C) | 22 s (20 distinct d) | 9 s |  | 13 s | n/a | n/a | n/a |  |
| 6 | 2 (C) | 18 s | 6 s | 5 s | 12 d | n/a | n/a | n/a |  |
| 7 | 2 (C) | 18 s | 6 d |  | 12 s | n/a | n/a | n/a |  |
| 8 | 2 (C) | 20 s | 7 s |  | 13 s | n/a | n/a | n/a |  |
| 9 | 2 (C) | 13 s | 5 s |  | 8 s | n/a | n/a | n/a |  |
| 10 | 2 (C) | 14 s (13 distinct s) | 7 d |  | 7 d | n/a | n/a | n/a |  |
| 11 | 2 (C) | 18 s (15 fixes s) | 9 s |  | 9 d | n/a | n/a | n/a |  |
| 12 | 2 (C) | 11 s | 6 s | ≥3 s | 5 s | n/a | n/a | n/a |  |
| 13 | 2 (C) | 9 s | 3 d |  | 6 s | n/a | n/a | n/a | 3 s |
| 14 | 2 (C) | 9 s | 3 d |  | 6 s | n/a | n/a | n/a |  |
| 15 | 2 (C) | 9 s | 3 s |  | 6 d | n/a | n/a | n/a |  |
| 16 | 2 (C) | 14 s | 4 s |  | 10 s | n/a | n/a | n/a |  |
| 17 | 2 (C) | 17 s (16 distinct d) | 5 s |  | 12 s | n/a | n/a | n/a | ≥1 s |
| 18 | 2 (C) | 12 s (11 distinct s) | 3 s | ≥1 s | 9 s | n/a | n/a | n/a | ≥1 s |
| 19 | 2 (C) | 13 d (11 distinct s) | 6 s |  | 7 s | n/a | n/a | n/a | 4 s |
| 20 | 2 (C) | 18 s (9 distinct s) | 9 s | 5 s | 9 s | n/a | n/a | n/a | ≥1 s |
| 21 | 2 (C) | 17 s (~14 distinct s) | 7 s | 5 s | 10 d | n/a | n/a | n/a |  |
| 22 | 2 (C) | 24 s (~20 distinct s) | 7 s | 4 s | 17 s | n/a | n/a | n/a | ≥1 d |
| 23 | 2 (C) | 25 s | 8 s | 3 s | 17 s | n/a | n/a | n/a |  |
| 24 | 2 (C) | 13 s (11 distinct s) | 5 s | 3 s | 8 s | n/a | n/a | n/a |  |
| 25 | 2 (C) | 18 s | 6 s | 4 s | 12 s | n/a | n/a | n/a | ≥1 d |
| 26 | 2 (C) | 16 d | 5 d | 1 s | 11 s | n/a | n/a | n/a | 4 d |
| 27 | 2 (C) | 14 d | 3 s |  | 11 s | n/a | n/a | n/a | 6 d |
| 28 | 2 (D) | 21 d | 10 s | 5 d | 11 s | n/a | n/a | n/a |  |
| 29 | 2 (D) | 21 d | 8 s | 4 d | 13 s | n/a | n/a | n/a |  |
| 30 | 2 (D) | 22 s | 10 s | 5 s | 12 s | n/a | n/a | n/a |  |
| 31 | 2 (D) | 17 s | 5 d | 4 s | 12 s | n/a | n/a | n/a |  |
| 32 | 2 (D) | 22 s | 7 s | 5 s | 15 s | n/a | n/a | n/a | ≥1 s |
| 33 | 2 (D) | 18 d (+1) | 6 s | 3 d | 12 s | n/a | n/a | n/a |  |
| 34 | 2 (E) | 14 d (13 distinct d) | 4 s | 4 s | 10 s | n/a | n/a | n/a |  |
| 35 | 2 (E) | 20 d | 4 s | 4 s | 16 s | n/a | n/a | n/a |  |
| 36 | 2 (E) | 15 d | 1 s | 1 d | 14 s | n/a | n/a | n/a |  |
| 37 | 2 (E) | 18 s | 3 s | 3 d | 15 s | n/a | n/a | n/a |  |
| 38 | 2 (E) | 19 d | 3 s | 1 s | 16 s | n/a | n/a | n/a |  |
| 39 | 2 (F) | 21 d | 4 s | 4 s | 17 s | n/a | n/a | n/a |  |
| 40 | 2 (F) | 18 d | 4 s | 4 d | 14 s | n/a | n/a | n/a |  |
| 41 | 2 (F) | 27 d | 11 s | 8 d | 16 s | n/a | n/a | n/a |  |
| 42 | 2 (F) | 17 d | 3 s | 2 s | 14 s | n/a | n/a | n/a |  |
| 43 | 2 (F) | 24 d | 10 s | 7 d | 14 s | n/a | n/a | n/a |  |
| 44 | 2 (F) | 30 d | 7 s | 2 d | 23 s | n/a | n/a | n/a |  |
| 45 | 2 (F) | 24 d | 7 s | 4 d | 17 s | n/a | n/a | n/a |  |
| 46 | 2 (F) | 22 d | 2 s | 0 d | 20 s | n/a | n/a | n/a |  |
| 47 | 2 (F) | 20 d | 3 s | 2 d | 17 s | n/a | n/a | n/a |  |
| 48 | 2 (F) | 20 d | 7 s | 3 s | 13 s | n/a | n/a | n/a |  |
| 49 | 3 (G) | 65 d | 7 s | 2–3 s | 17 s | n/a | 41 s | n/a |  |
| 50 | 3 (G) | 95 d | 7 s | 1 s | 10 s | n/a | 78 s | n/a |  |
| 51 | 3 (G) | 47 d | 6 s | 1 s | 17 s | n/a | 24 groups s | n/a | ≥1 s |
| 52 | 3 (G) | 79 d | 3 s | 2 s | 9 s | n/a | 67 s | n/a | 4 s |
| 53 | 3 (G) | 52 d | 4 s | 2 s (+1) | 12 s | n/a | 36 s | n/a | 2 s |
| 54 | 3 (G) | 52 d | 3 s | 4 s | 10 s | n/a | 39 s | n/a | 2 s |
| 55 | 3 (G) | 45 d | 4 s | 4 s | 11 s | n/a | 30 s | n/a | ~0 s |
| 56 | 7 (H) | 61 d | 19 d | ~17 s | 9 s | n/a | 33 d | n/a | 0 s |
| 57 | 7 (H) | 47 d | 18 d | ~16 s | 7 s | n/a | 22 s | n/a | ~0 s |
| 58 | 7 (H) | 49 d | 19 d | 19 s | 10 s | n/a | 20 s | n/a | 0 s |
| 59 | 7 (H) | 45 d | 16 s | 14 s | 7 s | n/a | 22 s | n/a | 0 s |
| 60 | 11 (I) | 394 d | 28 s |  | 181 d | 114 d | 53 d | 18 d |  |
| 61 | 11 (I) | 344 d | 27 s (24 distinct) | 20 distinct d | 168 d | 69 d | 47 d | 33 d |  |
| 62 | 11 (I) | 244 rows | 17 (16 distinct) | 13 | 135 | 51 | 16 | 20 | 50, 6 of them soundness |
| 63 | 11 (I) | 217 rows | 22 (20 distinct) | 17 (16 distinct) | 113 | 28 | 21 | 19 | 38, none of them soundness |
| 64 | 11 (J) | 116 rows | 22 (21 distinct) | 17 (16 distinct) | 39 | 31 | 7 | 17 | 6 (3 distinct), 1 of them soundness |

Totals from R49 on include worth-saying items, which dominate some rounds. Round 62 also has 5 formatting rows and round 63 has 14, counted in their totals. Round 63 declined 12 rows and marked 10 as duplicates, against 1 and 4 in round 62. Round 64 declined 2 and marked 19 as duplicates: with every reviewer on one topic, several found the same item, `Thread.scope`'s block type five times.

### Round 62 by reviewer

| Reviewer | Rows | Soundness | Of which regressions from R61 |
|---|---|---|---|
| 01+03+12 | 23 | 0 | 0 |
| 02 | 12 | 1 | 0 |
| 04 | 21 | 2 | 1 |
| 05+examples | 16 | 2 | 1 |
| 06+08 | 24 | 2 | 0 |
| 07+README | 33 | 0 | 0 |
| 09+11 | 30 | 5 | 3 |
| 10+13 | 30 | 5 (1 duplicate) | 1 |
| 14 | 22 | 0 | 0 |
| hard-cases | 16 | 0 | 0 |
| soundness-probes | 17 | 0 | 0 |

### Round 63 by reviewer

| Reviewer | Rows | Soundness | Of which regressions from R62 | All regressions from R62 |
|---|---|---|---|---|
| 01+03+12 | 24 | 1 | 0 | 6 |
| 02 | 16 | 3 | 0 | 1 |
| 04 | 14 | 2 | 0 | 0 |
| 05+examples | 22 | 4 (1 duplicate) | 0 | 3 |
| 06+08 | 26 | 3 | 0 | 6 |
| 07+README | 21 | 0 | 0 | 5 |
| 09+11 | 19 | 4 (1 duplicate) | 0 | 3 |
| 10+13 | 32 | 5 | 0 | 3 |
| 14 | 21 | 0 | 0 | 3 |
| hard-cases | 13 | 0 | 0 | 4 |
| soundness-probes | 9 | 0 | 0 | 4 |

The soundness rows written before round 63's midpoint first used high, medium and low severities. They were mapped to `hole` or `gap` by the definitions above before this table was counted.

### Round 64 by reviewer

Ownership and borrow checking only (setup J). The 10+13 label covers 10, 12 and 13.

| Reviewer | Rows | Soundness | Holes, distinct | All regressions from R63 |
|---|---|---|---|---|
| 01 | 18 | 4 | 2 | 1 (duplicate) |
| 02 | 14 | 3 | 3 | 0 |
| 03+06 | 14 | 3 | 1 | 0 |
| 04 | 11 | 2 | 2 | 1 |
| 05+examples | 9 | 0 | 0 | 0 |
| 07+08 | 13 | 0 | 0 | 1 (duplicate) |
| 09+11 | 12 | 5 | 5 | 2, 1 of them soundness |
| 10+13 | 6 | 3 | 2 | 0 |
| 14+README | 8 | 1 (duplicate) | 0 | 0 |
| hard-cases | 3 | 0 | 0 | 0 |
| soundness-probes | 8 | 1 | 1 | 1 (duplicate) |

## Spec size

Words in `README.md` and `docs/*.md`: the chapters, which include 15's soundness argument from its first row, the hard cases, and the soundness probes until they were retired. Examples are not counted.

| When | README | Chapters | Hard cases | Probes | Total |
|---|---|---|---|---|---|
| After R39, before the size-cutting pass | | | | | ~109,000 |
| During R50 | 3,771 | 71,315 | 8,780 | 5,463 | 89,329 |
| During R58 | 3,404 | 70,079 | 8,647 | 8,169 | 90,299 |
| During R61 | 3,452 | 76,340 | 8,866 | 11,932 | 100,590 |
| Start of R62 | 3,434 | 80,780 | 8,866 | 13,548 | 106,628 |
| End of R62 | 3,478 | 83,990 | 8,864 | 14,689 | 111,021 |
| End of R63 | 3,497 | 86,710 | 9,033 | 16,231 | 115,471 |
| End of R64 | 3,505 | 89,107 | 9,033 | 18,102 | 119,747 |
| After R64: probes retired, 15 added, hard cases reduced to what code must express | 3,509 | 96,008 | 8,952 | 0 | 108,469 |

## Reading the trend

**Soundness improved, then stalled.** With the same eleven full-coverage reviewers, distinct soundness findings went from 28 (R60) and 24 (R61) to 16 (R62), then back up to 20 (R63), and distinct holes from 20 to 13, then 16. Four partitions reported no soundness finding in R63, against five in R62 and one in R61. The rounds before R60 can't be compared this way: each change of setup added reviewers or coverage, and the counts rose with it, as in R56, when four area reviewers joined and the serious count went from 4 to about 17.

**Where the holes are has moved.** R61's holes were spread over the core: views and dependencies, projections, conversions of entry functions, raw allocation, error unions. R62's cluster at the edges of the safe language: the promises `unsafe` code and C make (02, 09, 11), freezing and reflection at compile time (10), and the type system's rarer corners (extension `deinit`s, `consuming` requirements through existentials). That is what a converging design looks like, but these edges are also where rules are least exercised by the examples, so they deserve continued review.

**R63's soundness findings stay at those edges, and all are latent.** None of its 20 sits in text R62 wrote, against 6 of R62's 16 in text R61 wrote. So the fixes have stopped opening holes, but the reviewers keep finding old ones: conformances that implied a marker without checking it (05), dependency sets for interpolated literals, destroyed guards and consumed closures (02), the C boundary's stores, free functions and read-only memory (09, 11, 04), and what freezing keeps (10).

**Fixes cause a falling share of the findings.** 50 of R62's 244 rows sat in text R61 wrote, and 38 of R63's 217 in text R62 wrote, 20% then 18%, all of R63's in consistency, clarity, worth-saying and formatting. Rows fell 11%, clarity rows almost halved (51 to 28) and consistency fell from 135 to 113, while formatting rose from 5 to 14 and worth-saying from 16 to 21. The spec still grows about 4% a round: from about 90,000 words at R58 to 111,000 after R62 and 115,000 after R63, mostly in chapters and probes. R63 also added features where a reviewer showed a reasonable pattern was forbidden (unpacking an owned `Box<any P>`, `keep owned`, `@c noalloc` pointers, protocol extension rules, `downcast` as a projection), and that new surface is what the next round should probe first.

**What would show convergence:** soundness findings falling toward zero, with the partitions that report none staying clean, the share of findings that are regressions falling round over round, and the spec holding its size or shrinking. After R63, only the regression share is moving the right way. The fixes in coming rounds should prefer removing or merging rules over adding them, and a round's regressions should be checked against the snapshot taken at its start, as R62's and R63's were.

**R64's soundness findings split three ways, and none needed a change to the ownership model.** Pointed at ownership and borrow checking alone, the eleven reviewers found 21 distinct soundness findings, 16 of them holes, as many as R63's whole-spec review found everywhere. 20 of the 21 are latent: they sat in text that earlier full reviews read and passed. By layer:

- **std and runtime APIs, 4:** `zip`'s iteration, `Box.leak` taking a scoped value, a pin's drop ordering, and thread identities. Two of them, `zip` and `Box.leak`, broke rules the language already stated, so the APIs as written were wrong, not the rules.
- **The contract for `unsafe` code and C, 7:** what C may do with a value Rayo lends, a C entry's `mutable` parameter across a checkpoint, views C writes, a local's address across moves, `p.move()` under a view, `ptr(to:)` as a function value, and the promise for storage shared between two handles. Safe code's checking is unaffected; these tighten what `unsafe` code and C must promise.
- **Rules that safe code's checking applies, 10:** a suspended accessor that kept no hold on `self`, a field assignment through a binding that may name either of two places, a generic `owned T` that may be a mutable view, inline array indices that are value parameters, an optional chain treated as a place, a throwing conversion that changes which arguments are places, a `where yield` over an under-aligned argument, and three compile-time interactions (generated members, frozen `const` views, reflective projections).

Each fix in the third group was a missing case or an over-broad sentence, settled in one or two sentences, not a change to how ownership works. So the model holds, but its text still has gaps, and a review spread over every topic under-samples each one: focused rounds find what it misses.

**R64's fixes were mostly safe, and its own regressions were few.** 3 of 116 rows sat in text R63 wrote (6 counting duplicates), 3% against R63's 18%, one of them a hole at the C boundary. Three partitions found no soundness problem (05+examples, 07+08, hard-cases), and 14+README found only a duplicate. Design rows stayed high (15 distinct): most were reasonable patterns the ownership rules forbade, and the fixes added consuming loops, `discard self`, taking `owned` arguments when the call begins, awaited assignment to a task's own locals, path-rule borrows across checkpoints and `@entry` parameters that meet the path rule. The spec grew 3.7%, to 119,747 words, 1,871 of them probes. That new surface is where the next ownership round should start, and the same focused setup over C interop and `unsafe`, and over concurrency, would show whether those areas hide as much.

**Why the method changed after R64.** Reading for holes didn't converge. Distinct holes went 20 (R61), 13 (R62), 16 (R63) and 16 (R64), most of them latent in text that earlier rounds had read and passed, and a fix usually added a rule or an exception that the next round could probe. The probes, which recorded each scenario, grew from 5,463 words at R50 to 18,102 at R64 and still couldn't show when the space of programs was covered. From R65:

- soundness is reviewed by checking each step of `docs/15-soundness.md` once, a finite task in which a failed step names the rule to fix;
- `hard-cases.md` keeps only what the rules must let code express, its Must accept and Must hold criteria. Every Must reject and Must be sound criterion was a soundness scenario the argument covers, and C8 and C9, which held only those, were retired;
- the next evidence comes from running code rather than reading: an executable model of the static core, whose checker compiles the hard cases' Must accept patterns as tests and whose interpreter flags undefined behavior in random programs the checker accepts, and a model check of the grace-period protocol.
