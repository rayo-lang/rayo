---
name: code-comments
description: "Read before writing or changing any code in this repo, every time — including one-line edits. Carries the rules for comments, doc comments, and naming."
---

# Code Comments

Binding on every line you write or change, whether or not this skill was invoked explicitly. It governs what a line
*says* — names, doc comments, inline comments. How a change is shaped is `code-design`'s.

It binds comments you leave in place as much as ones you write. A comment standing in code you touched is a comment you
are keeping, so judge it the same way.

## The two rules

**Above a property, a type, or a function.** The comment is a description of that declaration — what it is, or what
it does. It earns its place only by saying something the signature does not already say. When the signature says it
all, write nothing.

**Inside a body.** The comment exists only where the code is not obvious, or where something happens the line does not
show: a side effect, an ordering that matters, a trap. Never a translation of the line back into English.

Everything below is these two rules applied.

## Above a declaration

Start from the signature. Read it as a stranger would, then ask what they still would not know. That gap is the whole
of what the comment may contain — and often there is no gap.

What fills the gap depends on what is being declared:

- **A type** — what it is for, and where it sits in the flow when that is not plain from the code around it.
- **A property** — what it carries, when the name and the type do not already say it.
- **A method** — what it does, and what it returns when that is not obvious from the doing.

Once the description earns its place, it may carry one more thing: a fact about **this** declaration that the code
cannot show — a constraint that decides its shape, an alternative that was rejected and why, a precondition the caller
must hold. One or two sentences. Never at length.

Five ways this goes wrong. All five produce comments that are true, and none of them belong:

**It describes something other than the declaration.** What the caller does with the answer. What a later pass does
with the value. What a sibling field means. The concept the file header already states.

```swift
// Before — every word is about the linker, two targets away.
/// Nil binds the function into the platform C runtime, which every hosted target links without being asked.
private func nativeLibrary(of funcDecl: FunctionDecl) -> String?
```

The function reads an attribute list and answers a name or nil. It binds nothing. Delete it, or say what it does.

**It repeats the signature.** The type, the name, and the parameter list are already read by everyone who reaches the
comment.

```swift
// Before — the question mark says this.
/// `buildBody` returns nil when there is no body to lower.
buildBody: ([RILBlockArgument], RILType) -> RILFunctionBodyBuilder.Result?
```

```swift
// Before — "one past the last" is the name.
/// The id one past the last instruction the body handed out.
let nextInstructionId: RILInstructionId?
```

**It names the value where the work belongs.** A noun phrase — "The RIL type `param` occupies", "Which borrow
`source` is held under" — is a property's shape, and a method named like one (`parameterType`, `resolvedProperty`)
does not earn it. The shape also hides work: it reads as a pure lookup over methods that mint witness tables,
allocate stack slots, and record internal errors.

**Nothing describes the declaration at all.** A doc worn down to preconditions and exception cases — what the caller
must hold, what answers nil, what the function does *not* do — never says what the thing is. Either the signature
says everything and the comment goes entirely, or the comment opens by describing.

**It is an essay.** A description is one or two sentences. Paragraphs, bullet lists of branches, and an argument for
why the design is right are not descriptions, whatever they contain. If a function seems to need paragraphs, the
function does too much, and the fix is in the function.

### What a good one looks like

A method leads with what it does. A type or a property leads with what it is or what it carries. Then stop.

```swift
/// Lowers `param` to the RIL type it occupies: for a parameter crossing a `@import(c)` boundary, the C primitive
/// behind its wrapper type; otherwise the ordinary lowering of the declared type.
private func parameterType(of param: SignatureParameter, isCABI: Bool) -> RILType
```

```swift
/// Classifies which borrow, if any, `source` is held under. A member projected out of a lent parameter carries the
/// same lent mode without being one, so the mode alone does not decide it.
func borrowSource(of source: RILValueId) -> BorrowSource
```

The second sentence there is the earned fact: it says why the body tests membership in a set rather than reading a
mode, which nothing in the three lines below could tell you.

## Inside a body

The test is whether a reader stumbles. Two comments on the same guard; only one is worth keeping.

**A second copy of the code — delete it.** `case .paid` already says "paid". The comment is the guard translated back
into English, and it drifts.

```swift
// Only paid accounts.
guard case .paid = account.plan else { return nil }
```

**An explanation — keep it.** The guard shows *which* accounts are skipped, not what becomes of them, and that is
where a reader stumbles.

```swift
// A trial account is skipped rather than billed: the job that expires trials
// charges the card itself on the last day, and billing here as well would
// take the money twice.
guard case .paid = account.plan else { return nil }
```

Put it on the line it explains. A comment describing the branch below the one it sits above is a comment in the wrong
place.

## Reach for the code before the comment

Where a reader would stop to work out what a line is for, reach in this order: a better name, a smaller function, a
type that makes the illegal state unrepresentable. The comment is the last resort.

Two shapes are always a refactor, never a comment:

- **Numbered steps.** A function needing `// 1.`, `// 2.`, `// 3.` to be readable is naming its steps in comments
  instead of in function names. Each step is a function, and the numbering leaves with them.
- **A section heading.** A `// --- parse ---` inside a body marks a function waiting to be extracted.

And a comment explaining what a name means is a rename. Rename the thing.

## Writing the sentence

Orwell's rules, which are the whole of good English prose:

**No stock metaphors.** A value is not *threaded*, *surfaced*, *woven through*, or *carried along*. It is passed, held,
returned.

**Short words.** *Use*, not *utilize*. *So*, not *consequently*. *Hand back*, not *materialize*. Brevity is not
abbreviation, though: `ctx2`, `tmpB`, and `procFn` are words with letters missing, and the reader expands them. Spell
the name out.

**Cut every word you can.** Words, not facts — a comment carrying three facts keeps all three, in fewer words.

Apply the subtraction test to each sentence: **strike it — does a reader now get something wrong, or do something
wrong?** If not, delete it, and write no shorter version in its place. What the test catches is commentary, which is
cut rather than softened:

- **Arguing the design.** "which is what makes this correct", "this beats the obvious alternative".
- **Narrating the architecture.** Who resolved the value earlier, what a later pass will do with it, which other code
  agrees.
- **Admiring the code.** "cleanly", "neatly", "properly".
- **Restating** what the signature, the type, or a comment three lines up already said.

A fact lives in exactly one comment. Where the type returned, the parameter taken, or the function called already
documents it, leave it there. A comment noting that one function is built like another ("built the same way as `foo`")
reports duplication rather than documenting it — remove the duplication.

**Active voice.** "Signature collection fills it", not "it is filled during signature collection".

A second habit hides under this one, and it is where most unreadable comments come from: the noun phrase that swallows
a clause. "The name its declaration was written with." "The protocols `scope` bounds `index` to." Each drops the
relative pronoun, and the sense arrives only at the trailing preposition. Make the thing the subject of an active verb
instead.

```swift
// Before — ten words before the verb, and the sense arrives on "for".
/// The type-variable index each of an extension's generic parameters stands for.
```

```swift
// After — subject, verb, object.
/// Maps an extension's generic parameters, by name, to their type-variable indices.
```

At close range the construction is ordinary English — "the protocol it conforms to" reads at a glance. It turns bad
with distance, and worst when two of them meet in one sentence.

**No invented vocabulary.** "Capability", "chokepoint", "high-water mark" name real things badly. Name the mechanism
instead. Write so someone who has never opened the file can follow it, and never justify a design by pointing at
another language ("matching Swift's X").

**Break any of these sooner than write something barbarous.** A word the language or the compiler already uses —
*borrow*, *witness*, *lower*, *conform*, *invocation* — is the plain word here, and reaching for a homelier one makes
the sentence worse. Swapping *invocation* for *compilation* costs the reader the answer to "one module, or the whole
build?". Better than either: name the thing itself.

## Judging comments already written

Weigh the block whole — every line of it, at once. Taken sentence by sentence, each one survives on the strength of the
one beside it, and a block no reader needed lives on, a little shorter after every sweep.

Three outcomes, in this order:

1. **Delete it.** The first question to ask, and the usual answer.
2. **Rewrite it whole.** Where the block holds something worth keeping but carries it badly, write the replacement from
   the facts alone. Editing the old sentences forward keeps the shape that was wrong with them — compressing a sentence
   about the wrong subject gives a shorter sentence about the wrong subject, with the connective tissue stripped out.
3. **Correct a fact.** Only where the block is already as short as its facts allow, and one of them is wrong.

Never patch a block you would not have written.

## Lists, references, and tense

**One item per bullet line.** Cases, conditions, reasons, steps. In prose the reader does the splitting, and the tail
of a long sentence hides the last item.

```swift
// Before — three cases buried in one sentence.
// Returns nil for a closed account, for an account outside the billing
// region unless it carries a migration record, and for anything already
// invoiced this cycle.
```

```swift
// After — the reader counts them without parsing.
// Returns nil for:
// - a closed account
// - an account outside the billing region, unless it carries a migration
//   record
// - anything already invoiced this cycle
```

This is for a genuine list. A bullet per branch of the function below is the essay failure wearing a list's shape.

**Name the thing, never the record of the decision.** No spec chapter or section numbers, no ADR or D-entry numbers, no
issue, PR, or bug numbers, no iteration or milestone labels. A reason worth citing is worth stating here.

```swift
// Before — the constraint is somewhere else, behind a number.
// See ADR 0007 and 06 §4.2. Fixed in #812.
```

```swift
// After — the constraint is written where it has to hold.
// A retry carries the id of the request it repeats, so the server settles a
// repeat as the original charge rather than as a second one.
```

Names follow the same rule. A file, type, test, or fixture is named for what it covers, never for the artifact that
asked for it — `RetryReusesRequestId`, not `Issue812Tests`.

**Present tense, about what is.** Never about what was or will be: no "now", "no longer", "previously", "older",
"legacy", "until X ships". A comment that dates itself is wrong the moment it comes true. Names carry the same rule.
