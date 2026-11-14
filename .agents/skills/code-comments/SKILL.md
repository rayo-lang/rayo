---
name: code-comments
description: "Read before writing or changing any code in this repo, every time — including one-line edits. Carries the guidance for comments, doc comments, names and error messages."
---

# Code comments

A comment is written for the next person who reads the code, and an error message for the person whose program just failed. Each earns its place by being **readable** and **relevant**. Everything below is those two words applied; where a case isn't covered, judge it by them.

## Readable

A comment reads as plain English at first glance. Write it the way a careful engineer would explain the code to a colleague: everyday words, ordinary sentence order, one idea at a time, in complete sentences. If a sentence needs a second reading, rewrite it; two short sentences beat one dense one. Clear comes before short: one line is right where one line says it all, and where the reader needs more to know what the thing is, write more.

Use the language's and the compiler's own terms (*borrow*, *lower*, *witness*) where they are the precise word, and everyday words everywhere else.

- **Words about the things themselves.** Say what happens to the things the code works on: the struct, the field, the call, the argument. Name a parameter, or any exact thing, in inline code only where that helps the reader find it. The sentence makes sense without decoding it: one built mostly of code is decoded, not read.
- **Examples for what's hard.** Give an example only for an important or complex case, in a code block of its own. Something simple is said in words alone.

A function's doc in that spirit:

```swift
/// Checks an assignment, or a compound assignment such as `+=`. The value is checked even when the target
/// can't be assigned, so mistakes in it are still reported.
```

Names follow the same aim: spelled out in full, and named for what they hold or do. A function's name says what it does, and nothing it doesn't.

## Relevant

A comment tells the reader something they need and the code doesn't already show.

- **Above a type**, it says what the thing is and what it holds, so a reader new to the code knows both from the doc alone.
- **Above a function**, it says what the function does, as a caller sees it. When the name and the signature already say that, write none.
- **A block's opening comment**, where the `code-style` skill calls for one, says its step in the terms of the function's job, so a reader can skim the body by its comments.
- **Any other comment in a body** explains what the lines can't show: why it's done this way, an ordering that matters, a trap. It sits above the first line it explains, never between the lines it covers. A comment that only restates the line is noise.
- **Code that confuses** is made clearer before a comment is reached for: a better name, a smaller function, a tighter type, a condition that says what it tests. A comment is for what remains.
- **A comment stays true.** A comment in code you change is yours too: update it, or delete it if it no longer helps.

## Error messages

An error message says what is wrong, directly, in the fewest plain words, the way a person would say it out loud. It gives a reason only where the reader would otherwise not know how to fix the mistake.

## Code is its own source of truth

Comments and names describe the code as it is, in the present tense, and state any reason in place. They cite no issue, bug, pull request, spec section, ADR, plan, review finding or milestone, and say nothing of what the code used to do or will do: a reason worth citing is worth writing out where it has to hold. A test or file is named for what it covers.

## Before you open a pull request

Audit every comment, name and error message you added or changed, and every comment in code you touched. Each comment and name reads at first glance, is true of the code as it stands, and cites no record of a decision. Each name is spelled out and says what the thing holds or does, and nothing it doesn't. Each comment is in words about the things themselves, says all a reader needs, and tells the reader something the code doesn't (for a block's opening comment, its step; for a type's doc, what it is and holds). Each error message says what is wrong in the fewest plain words, with a reason only where the reader needs it to fix the mistake. A reviewer audits the same.
