# Writing the guide

The guide in `docs/guide/` teaches Rayo to a programmer who already knows C++, Rust, Swift or C#. It is read front to back. The spec states every rule exactly and is read by looking things up; the guide picks the rules a reader needs first, shows them working, and links to the spec for the rest. The sentence rules of `spec-style.md` apply to the guide too.

## Chapters

- **Start from a problem.** A chapter opens with something a systems programmer needs to do, in a few sentences and a short code sample, and builds the solution step by step.
- **Build on earlier chapters only.** A chapter uses what the chapters before it taught, and what it teaches itself. A later topic may be named in passing, with a link to its chapter.
- **End with the spec.** The last section, `## In the spec`, lists the spec sections behind the chapter, each with a few words on what it adds.
- **Stay short.** A chapter is a sitting's read: about 150 to 300 lines.

## Teaching

- **One idea at a time.** Say the idea in a sentence, show it in code, say what the compiler does with it, then move on.
- **Show the error, then the fix.** For a rule that rejects code, show the rejected line with the compiler's reason in a trailing comment, as in `// error: 'cmds' was moved`, then the code that works. The two may declare the same function one after the other. A borrow error reads as the spec's do: `// error: 'source' is borrowed by 'lines' (used below)`.
- **Simplify, never contradict.** The guide may leave out cases, but what it says is true as stated. Where it leaves out a case a reader is likely to hit, it says so and links to the spec.
- **Use the spec's terms.** Call things what `GLOSSARY.md` calls them. Bold a term where the guide first explains it, and link the spec section that defines it.
- **Write code the spec accepts.** Every example follows the spec's rules and the grammar in 12, unless its comment says it is an error. Two shortcuts are allowed, as the guide's README says: statements beside declarations, and a body left out as `{ ... }`. Examples use the spec's running game code: `Enemy`, `world`, `Mesh`, `Pool`, `Handle`.
- **Keep one `Enemy`.** Chapter 1 declares `Enemy(pos, vel, hp)`. A chapter that needs another field adds it to those three.
- **Compare where it helps.** A short comparison with C++, Rust, Swift or C# helps a reader map an idea, as in "like a Rust slice, but checked at run time". The case for the design belongs in `why-rayo.md`.
- **"You" is fine.** The guide talks to the reader, in the present tense.

## Links

Links to the spec read as in the spec: `([01](../spec/01-values-and-ownership.md#moves))`. A link to another guide chapter names it: `([Borrowing](03-borrowing.md))`.

## Checks

`python3 scripts/check_docs.py` checks the guide's links, layout, dashes and sentence and paragraph lengths, as it does the spec's.
