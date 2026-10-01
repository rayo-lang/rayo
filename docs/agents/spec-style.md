# Writing the spec

The numbered chapters in `docs/` are Rayo's specification: complete and exact, organized by construct, and read by looking things up rather than front to back. Teaching belongs in the guide, which may simplify and links to the spec for the full rules.

The spec is **precise and plain**: every rule stated exactly, in words a reader takes in once. Precision comes from defined terms and complete lists, never from packing more clauses into a sentence.

## Sentences

- **One rule per sentence.** Aim for under 25 words. A sentence past 40 is a list, or two rules.
- **Active voice, short words.** "The compiler rejects `f(&x, x)`", not "`f(&x, x)` is rejected". *Use*, not *utilize*; *so*, not *consequently*.
- **The thing as the subject of a verb.** "`list[i]` hands out the list's element", not "the place an accessor yields from one".
- **Common words for common ideas.** Where programmers already have a word, use it: *reference counting*, not *counted owner*. Coin a term only for an idea with no common name, and define it.
- **Present tense, about what is.** Never "now", "no longer" or "previously".

## Paragraphs and sections

- **Lead with the rule**, in bold, in one sentence. Its cases, exceptions and consequences follow. A short example may come first.
- **Three or more items make a list**, one item per bullet.
- **Paragraphs stay under about 120 words.** A section that needs more splits into subsections, each with its own rule.
- **An exception sits next to its rule**, so a reader who finds the rule also finds what it doesn't cover.
- **Each rule is stated once**, in the section that owns it. Other sections link to it.
- **A rule whose consequence isn't obvious gets an example**: a short code block of what compiles and what doesn't, with the reason in a trailing comment, as in `// error: 'seen' is still used below`. Examples use the spec's running game code, such as `Enemy`, `world` and `Mesh`.

## Terms and links

- **Each term of art is defined once**, in bold, in the section that owns it. `GLOSSARY.md` names the term, says in one sentence what it is, and links to that definition. A pull request that adds, renames or moves a term updates its entry.
- **A chapter follows its construct, not a teaching order.** A rule may use a term defined later; on the term's first use in a section, it links to its definition.
- **One link per idea.** A sentence carrying more than two links is a list: give each item its own bullet and link.
- **Links** read `([06](06-memory-and-allocators.md#anchor))` across chapters, and `([above](#anchor))` or `([below](#anchor))` within one.
- **Anchors are part of the interface.** A pull request that renames a heading updates every link to it.

## Reasons

A rule says what holds. A short reason may follow when it helps a reader apply the rule, as in "since a copyable type owns no heap memory". The case for the design, and comparisons with other languages, belong in `why-rayo.md`.

## Lists and punctuation

- A list that completes a lead-in sentence ends each item with `;` and the last with `.`.
- A list of whole sentences ends each item with `.`.
- A bullet may open with a bold label that names its case: `- **Owning values.** These are …`.
- A colon, a comma or a second sentence does the work of a dash.

## Example

Before, the opening of chapter 01, with its links shown as plain text:

> A **place** is storage that holds a value: a local, a parameter, a global, a temporary, or a field, element or projection of one of those. A value has one owner at a time, except the value behind a counted owner such as `Shared<T>`, which each owner shares (06), and no second value is made unless the code says `copy` or `clone()`, takes a copyable `const` (below), or uses an operation defined to copy its copyable operands in: a range operator (05), a `Simd` initializer or lane read (04), …

After:

> A **place** is storage that holds a value: a local, a global, a parameter or a temporary, or a part of one, such as `enemy.hp` or `list[i]`.
>
> **Every value has one owner**, which decides when the value is destroyed. The exception is reference counting: `Shared<T>` lets several owners share one value, and the last owner to let go destroys it (06). Code that uses a value without owning it **borrows** it.
>
> **A second value exists only where the code asks for one**: with `copy` or `clone()`, by taking a copyable `const`, or through an operation that copies its operands (below).

The after version defines a place by example, names reference counting by its common name, and moves the full list of copying operations to a section of its own.
