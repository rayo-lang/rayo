# Writing the spec

The numbered chapters in `docs/spec/` are Rayo's specification: complete and exact, organized by construct, and read by looking things up rather than front to back. A long chapter keeps its numbered landing page and places related rules in subchapter files beneath a directory of the same name. Teaching belongs in the guide, which may simplify and links to the spec for the full rules.

The safety argument and hard cases in `docs/validation/` check the spec during design and implementation. They do not define language rules. If a check finds a missing rule, add it to the spec chapter that owns it.

The spec is **precise, plain and explained**: every rule stated exactly, with the reason it holds, in words a reader takes in once. Precision comes from defined terms and complete lists, never from packing more clauses into a sentence. Being a reference is a reason to be exact, not a reason to be terse: a reader who looks a rule up should understand it, not only find it.

## Sentences

- **One rule per sentence.** Aim for under 25 words. A sentence past 40 is a list, or two rules.
- **Active voice, short words.** "The compiler rejects `f(&x, x)`", not "`f(&x, x)` is rejected". *Use*, not *utilize*; *so*, not *consequently*.
- **The thing as the subject of a verb.** "`list[i]` hands out the list's element", not "the place an accessor yields from one".
- **Common words for common ideas.** Where programmers already have a word, use it: *reference counting*, not *counted owner*. Coin a term only for an idea with no common name, and define it.
- **Present tense, about what is.** Never "now", "no longer" or "previously".
- **Inline code is for names and short expressions**: a type, a keyword, an operator, or a few tokens such as `copy x`, `list[i]` or `T: Copyable`. A declaration, a signature or a statement goes in a code block, with what it shows in a trailing comment, never inside a sentence as in "as `struct S<T>(…): Scoped, ~Copyable` does".

## Paragraphs and sections

- **Lead with the rule**, in bold, in one sentence. Its cases, exceptions and consequences follow. A short example may come first.
- **Three or more items make a list**, one item per bullet.
- **Paragraphs stay under about 120 words.** A section that needs more splits into subsections, each with its own rule.
- **An exception sits next to its rule**, so a reader who finds the rule also finds what it doesn't cover.
- **Each rule is stated once**, in the section that owns it. Other sections link to it. A numbered landing page introduces and links its subchapters; the subchapter owns the detailed rules.
- **A rule whose consequence isn't obvious gets an example**: a short code block of what compiles and what doesn't, with the reason in a trailing comment, as in `// error: 'seen' is still used below`. Examples use the spec's running game code, such as `Enemy`, `world` and `Mesh`.

## Terms and links

- **Each term of art is defined once**, in bold, in the section that owns it. `GLOSSARY.md` names the term, says in one sentence what it is, and links to that definition. A pull request that adds, renames or moves a term updates its entry.
- **A chapter follows its construct, not a teaching order.** A rule may use a term defined later; on the term's first use in a section, it links to its definition.
- **One link per idea.** A sentence carrying more than two links is a list: give each item its own bullet and link.
- **Links** read `([06](06-memory-and-allocators.md#anchor))` across chapters, and `([above](#anchor))` or `([below](#anchor))` within one.
- **Anchors are part of the interface.** A pull request that moves or renames a heading updates every link to it. In a subchapter, links to a sibling subchapter use its file name; links to another numbered chapter go up one directory.

## Explaining

- **Say why a rule holds, where it isn't obvious.** The reason is what would go wrong without the rule, in this language's terms: "it declares no `deinit`, since each copy would run it". It follows the rule, in a clause or a sentence of its own. The case for the design against other languages belongs in `why-rayo.md`.
- **A reason is the spec's own.** It comes from this chapter or the section the rule links to. A rule whose reason the spec doesn't give is stated without one, never with a guess.
- **Explain a group before listing it.** A list opens with what its items share, and each item says how it fits, as "**Lock guards.** A `@guard` type holds a lock for as long as it lives, and a copy would release it a second time". A bare list of constructs leaves the reader to work out why they belong together.
- **Plain words before notation.** Name an idea in words before using its syntax as a noun: "always move-only", not "its kind makes it move-only".

## Lists and punctuation

- A list that completes a lead-in sentence ends each item with `;` and the last with `.`.
- A list of whole sentences ends each item with `.`.
- A bullet may open with a bold label that names its case: `- **Owning values.** These are …`.
- A colon, a comma or a second sentence does the work of a dash.

## Checks

`python3 scripts/check_docs.py`, which CI runs, checks every link and anchor, the layout and the dashes. It also counts each file's sentences over 40 words and paragraphs over 120, which may never rise above `scripts/readability-baseline.json`. A rewrite that lowers them commits the lower baseline, written by `--update-baseline`.

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

A second example, from 01's copy rules. Before:

> Copyable types conform to the derived marker protocol **`Copyable`**. Listing it, as `struct Handle<T>(…): Copyable` does, asks the compiler to confirm it.
>
> Every other type is **move-only**: one that declares a `deinit`, has a move-only field or payload, or lists **`~Copyable`**, as `struct MutableSpan<Element>(…): Scoped, ~Copyable` does. So is a type whose kind makes it move-only:
>
> - a `Synchronized` or `@guard` type (07, 02);
> - a `mutating` or `consuming` function value (05);

After:

> **A type is copyable only when a copy of its bytes is a second, independent value.** That needs the bytes to be all there is to the value: it owns nothing outside them, and nothing has to run when it is destroyed. A type is **copyable** when:
>
> - all its fields and payloads are copyable;
> - it declares no `deinit`, since each copy would run it, and two copies would release one resource twice;
>
> **Some types are move-only whatever their fields, since a second copy would break what the type promises:**
>
> - **`Synchronized` types.** A `Synchronized` type, such as `Mutex` or `Atomic<Int>`, exists once, so every thread that shares it synchronizes on the same memory (07).
> - **Lock guards.** A `@guard` type holds a lock for as long as it lives, and a copy would release the lock a second time (02).

The after version says what makes a type copyable before listing the conditions, gives each condition and each move-only type its reason, and moves the declarations into a code block.
