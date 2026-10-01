---
name: code-design
description: Use before implementing a feature, fix, or refactor to place the change, reuse existing concepts, and keep seams and functions coherent.
---

# Code Design

Aim for the smallest change in the right system: reuse existing concepts, keep seams narrow, and keep each function at one zoom level.

Apply the first three gates before editing. Apply the fourth while coding. Apply the last two after the behavior works. `code-comments` governs documentation and naming.

## 1. Root problem

State the problem in one sentence without naming a solution. Describe the missing behavior or violated invariant, not the requested type, function, or patch.

If the sentence still assumes the proposed fix, restate it until another valid implementation could satisfy it.

**Done when:** the symptom follows from the problem, but the solution does not appear in the statement.

## 2. Owning system

Name the smallest system that owns the behavior and the level where it lives: target, directory, subsystem, or file.

Identify:

- **Interface objects:** the few entry points callers use to make the system do work.
- **Crossing values:** data that crosses the seam without performing the work.
- **Internals:** implementation details used only inside the system.

Verify only the map entries the change depends on: relevant build dependencies, exported surface, and sibling references to alleged internals. Treat code and build configuration as authoritative over prose.

Implement inside the owner. Reach sibling systems only through their interfaces and along existing dependency edges.

Stop and state the design decision before coding when the change needs either:

- a new interface object, including why no existing entry point fits; or
- changes to two systems' seams, including why the behavior does not belong wholly to one.

**Done when:** you can name the owner, its level, the seam used, and any seam deliberately changed.

## 3. Existing concept

Search by behavior, not by the name you plan to introduce. Inspect the owning system and its callers, then name the closest existing type, function, or extension point.

Use the reasons-to-change test:

- If both sites would change together for the same future requirement, they are one concept. Widen the existing implementation and migrate every affected caller in this change.
- If either site can change independently, keep them separate even when the code looks similar.

A flag or mode added only to make one abstraction serve two callers is evidence that the seam should remain. So is sharing across subsystems intentionally kept independent.

When the evidence is genuinely inconclusive and the choice changes a public seam, surface the two meanings, what each option couples, and one recommendation before editing.

**Done when:** you have named the closest existing concept and decided reuse or separation from its reasons to change.

## 4. One zoom level

A function either orchestrates named steps or performs one step. It does not switch between those altitudes.

Extract a function or value type when a body reveals a second level through:

- numbered or section-heading comments;
- setup followed by dispatch or detailed mechanics;
- parallel locals assigned through the same branches; or
- a tuple immediately unpacked and recombined by the caller.

Length is not the test. A long mechanical leaf may be coherent; a short function that both coordinates and performs work is not.

**Done when:** a reader can follow each changed function without changing altitude inside it.

## 5. Repetition created by the change

Inspect every touched site for repeated call sequences, guards, unwrapping, or logic that differs only by a value. At the third occurrence, extract only when the reasons-to-change test says the sites are one concept.

Name the extraction for its meaning and place it where its next caller will look. Leave coincidental similarity separate.

**Done when:** every repetition introduced or exposed by the change is either consolidated or deliberately independent.

## 6. Less code

Trace every changed line back to the root problem. Remove surface area the change does not need:

- parameters no caller varies;
- cases no input reaches;
- abstractions with one implementation;
- wrappers that only forward; and
- handling for states the types already exclude.

Remove only excess created by this change. Adjacent cleanup is separate work.

**Done when:** deleting any remaining changed line would break the required behavior, the chosen seam, or the clarity of one zoom level.
