# Writing the guide

The guide in `docs/guide/` teaches Rayo to a programmer who already knows C++, Rust, Swift or C#. It is read front to back. The spec states every rule exactly and lets readers find the full account of a construct; the guide picks the rules a reader needs first, shows them working, and links to the spec for the rest.

The guide follows `spec-style.md` for inline code, lists and punctuation. Both documents explain in connected prose. The guide builds ideas in learning order; the spec gives each construct's complete rules where a reader can find them.

## Writing

The guide is good prose, as Orwell describes it in *Politics and the English Language* and as *The Rust Programming Language* practises it:

- **Plain.** Short, common words, and the thing itself as the subject of an active verb. Say what happens, in literal terms. A term the guide teaches is explained in everyday words where it first appears.
- **Connected.** Each sentence follows from the one before, and the words that join them, such as *because*, *so*, *but* and *which*, carry the reasoning. A sentence ends where its thought does, so some are short and some are long.
- **Economical.** Every sentence gives the reader something new, and every word in it is needed. An explanation the reader needs is never wordiness: a claim without its reason is shorter, but harder to understand and to trust.
- **About what is,** in the present tense.
- **Comparisons in full.** A comparison names its example, as in "such as a number", or takes a sentence of its own. Never a clipped tail such as "as a number's are" or "as a plain parameter does".
- **Break any of these sooner than write something barbarous.**

## Chapters

- **Start from a problem.** A chapter opens with something a systems programmer needs to do, in a few sentences and a short code sample, and builds the solution step by step.
- **Build on earlier chapters only.** A chapter uses what the chapters before it taught, and what it teaches itself. A later topic may be named in passing, with a link to its chapter.
- **End with the spec.** The last section, `## In the spec`, lists the spec sections behind the chapter, each with a few words on what it adds.
- **What the reader needs at that point, and no more.** A chapter teaches each idea as far as the reader uses it there. A detail that matters only later goes in the chapter that needs it, or stays in the spec.
- **As long as its ideas need.** A chapter that grows past a sitting's read splits in two.

## Teaching

- **Teach the language, not its syntax.** The reader already programs, so the code shows the syntax. The prose explains what reading the code can't tell you: what a construct means, what it costs, what the compiler checks, and where Rayo behaves differently from what the reader expects.
- **Explain as a good textbook does.** Set up each feature with the problem it solves, show it, then walk the reader through what happens and why. Where the reader would guess wrong, say what they'd expect, and why Rayo works otherwise.
- **Walk the reader through, don't enumerate.** A chapter builds its ideas one step at a time, in the order a newcomer meets them, rather than listing rules. Teach each idea through its common case, and leave exceptions, edge cases and exact conditions to the spec: each detail a reader doesn't need yet makes them lose the thread.
- **One idea per paragraph.** A paragraph explains one idea: what it is, how you use it, and why it works that way. Bold marks a term where the guide first explains it.
- **Show, then explain.** Code comes in short listings, each followed by the prose that explains it, and a section may hold several, one per step of its idea. A comment in a listing marks what the line itself can't show, such as an error or a result the reader wouldn't predict.
- **Explain before using.** Every term, symbol and pronoun is clear where it first appears.
- **Show the error, then the fix.** For a rule that rejects code, show the rejected line with the compiler's reason in a trailing comment, as in `// error: 'cmds' was moved`, then the code that works. A borrow error reads as the spec's do: `// error: 'source' is borrowed by 'lines' (used below)`.
- **Simplify, never contradict.** The guide may leave out cases, but what it says is true as stated. Where it leaves out a case a reader is likely to hit, it says so and links to the spec.
- **Use the spec's terms.** Call things what `GLOSSARY.md` calls them, and link the spec section that defines each where the guide first explains it.
- **Write code the spec accepts.** Every example follows the spec's rules and the grammar in 12, unless its comment says it is an error. Two shortcuts are allowed, as the guide's README says: statements beside declarations, and a body left out as `{ ... }`. Examples use the spec's running game code: `Enemy`, `world`, `Mesh`, `Pool`, `Handle`.
- **Keep one `Enemy`.** Chapter 1 declares `Enemy(pos, vel, hp)`. A chapter that needs another field adds it to those three.
- **Rayo stands on its own.** Teach each idea in Rayo's terms, and let its merits be its own. Name another language only where the comparison makes a point the reader needs:
    - a difference that would mislead a reader who expects that language's behavior, as a `Vec3` that moves where C++ and Swift would copy it;
    - a definition Rayo takes from it, as the C++20 memory orderings;
    - a bug the chapter's problem shows, as a C++ reference that dangles.

  The case for the design against other languages belongs in `why-rayo.md`.
- **A teacher's voice.** Talk to the reader, and introduce each concept by what it does for them, tied to the example at hand. The examples come from a game, which the reader isn't building.
- **Write about Rayo.** The subject is always the language, never the guide itself. A pointer to the chapter that teaches a topic, such as "chapter 3 shows why", is the one exception.

## Links

Links to the spec read as in the spec: `([01](../spec/01-values-and-ownership.md#moves))`. A link to another guide chapter names it: `([Borrowing](03-borrowing.md))`.

## Checks

`python3 scripts/check_docs.py` checks the guide's links, layout, dashes and sentence and paragraph lengths, as it does the spec's.
