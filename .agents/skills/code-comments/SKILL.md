---
name: code-comments
description: "Read before writing or changing any code in this repo, every time — including one-line edits. Carries the guidance for comments, doc comments, and names."
---

# Code comments

A comment is written for the next person who reads the code. It earns its place by being **readable** and **relevant**. Everything below is those two words applied; where a case isn't covered, judge it by them.

## Readable

A comment reads as plain English at first glance. Write it the way a careful engineer would explain the code to a colleague: everyday words, ordinary sentence order, one idea at a time. If a sentence needs a second reading, rewrite it; two short sentences beat one dense one.

Use the language's and the compiler's own terms (*borrow*, *lower*, *witness*) where they are the precise word, and everyday words everywhere else.

Names follow the same aim: spelled out in full, and named for what they hold or do.

## Relevant

A comment tells the reader something they need and the code doesn't already show.

- **Above a declaration**, it says what the declaration is or does, as a caller sees it. When the name and the signature already say that, write none.
- **Inside a body**, it explains what the lines can't show: why it's done this way, an ordering that matters, a trap. A comment that only restates the line is noise.
- **Code that confuses** is made clearer first: a better name, a smaller function, a tighter type. A comment is for what remains.
- **A comment stays true.** A comment in code you change is yours too: update it, or delete it if it no longer helps.

## Code is its own source of truth

Comments and names describe the code as it is, in the present tense, and state any reason in place. They cite no issue, pull request, spec section, ADR or milestone, and say nothing of what the code used to do or will do: a reason worth citing is worth writing out where it has to hold. A test or file is named for what it covers.

## Before you open a pull request

Reread every comment and name you added or changed, and every comment in code you touched. Each one reads at first glance, tells the reader something the code doesn't, is true of the code as it stands, and cites no record of a decision. A reviewer checks the same.
