# 12 · Grammar

**The grammar decides whether source text is valid Rayo syntax; chapters 01 to 11 decide what that source means.** Look up a construct's production when punctuation or order is in doubt. Start with [where statements end](#where-statements-end) if a line break changes how a program parses. The [notes](12-grammar/notes.md#notes) settle choices the productions alone leave open.

**The productions use these EBNF symbols:**

- `?` marks an optional part;
- `*` repeats a part zero or more times, and `+` one or more times;
- `|` separates alternatives;
- `'x'` is a literal token;
- text between `(*` and `*)` is a comment.

**The chapters' examples are sometimes sketches, not source.** They show a declaration without its body, or with `…` in it, where the body doesn't matter.

## Where statements end

```swift
let total = base +              // a line that ends in a binary operator continues
    bonus * 2
let hps = enemies
    .filter({ $0.hp > 0 })      // a line that starts with '.' joins the one above
    .map({ copy $0.hp })
spawn(
    at: origin,                 // inside ( and [, newlines are whitespace
    count: 3
)
if ready { start() }
else { wait() }                 // a line that starts with 'else' joins the one above
x = 1; y = 2                    // ';' separates statements on one line
```

**Newlines end statements, and `;` separates statements on one line.** The productions don't show where one statement ends and the next begins, so the rules below decide where a newline doesn't end a statement, and where an arm of a `when` ends:

- **Inside brackets, newlines are whitespace.** Where the innermost unclosed bracket is `(` or `[`, a newline never ends anything, so an argument list or array literal can span lines and close on a line of its own. Where it is `{`, the other rules apply.
- **A line continues** when it ends in one of these:
    - a binary operator, though a `>` that closes generic arguments isn't one;
    - `=` or a compound assignment;
    - `->`, `,`, `(`, `[` or `{`;
    - an attribute, so `@reflect` on its own line applies to the declaration below it.
- **The next line joins the current one** when it starts with one of these:
    - `.`, for method chaining;
    - a binary operator, except `-`, `&`, `..<` and `...`, which can also be prefix operators;
    - `else`, `catch`, `where`, `throws` or `->`, so a signature can wrap before its result.

  So a line that starts with `-x` or `..<n` starts a new statement, unless the line above continues.
- **A `when` arm ends with the `}` of its block.** Whatever follows begins the next arm, on the same line or the next, so a line that starts with `.` or `else` there begins an arm rather than joining the one above. An arm's patterns and guard may span lines by the rules above, as `.chase(let t)` does below.

```swift
let label = when state {
    .idle { "idle" }
    .chase(let t)
        where t.isBoss { "fleeing" }    // a pattern, and its guard on the next line: one arm
    .chase { "chasing" }                // the '}' above ended an arm, so '.' begins this one
    else { "stuck" }
}
```

## Subchapters

- [Lexical grammar](12-grammar/lexical.md)
- [Files and declarations](12-grammar/declarations.md)
- [Types, statements, expressions and patterns](12-grammar/constructs.md)
- [Grammar notes](12-grammar/notes.md)
