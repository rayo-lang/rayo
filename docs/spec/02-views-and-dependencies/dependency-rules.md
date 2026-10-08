# Dependencies

[02 · Views and dependencies](../02-views-and-dependencies.md)

The compiler tracks **what each scoped value borrows**:

```swift
func visible(_ items: mutable List<Sprite>, in cells: Span<Cell>) -> MutableSpan<Sprite> { ... }

var vis = visible(&sprites, in: grid.cells.span)   // vis borrows sprites (mutably) and grid.cells (shared)
grid.cells.append(c)                               // error: grid.cells is borrowed by 'vis' (used below)
cull(&vis)

func splitLines(_ text: StringView, into out: mutable List<StringView>) { ... }

var lines = List<StringView>()                   // scoped: its elements are views
splitLines(source.view, into: &lines)            // lines now borrows source (shared)
source.append("x")                               // error: source is borrowed by 'lines' (used below)
print(lines.count)
```

**The compiler sees names, not memory, so it learns which places a view reaches only from what the view borrows.** Above, `source.append("x")` may move the text to a larger buffer and free the old one, which `lines` still views. The compiler rejects the call because `lines` borrows `source`.

A scoped value's **dependency set** is the places and dynamic accesses it borrows from, each marked **shared** or **exclusive**. What a value **carries** is its dependency set.

**Until a value's last use, every place in its set counts as borrowed, with its kind.** So changing, moving or destroying such a place before then conflicts with the value, by the law of exclusivity ([01](../01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)).

**The compiler works the set out inside one function body, from six rules:**

1. **Projection:** a view taken from a place depends on that place ([Rule 1: Projection](dependency-rules/projection-and-results.md#rule-1-projection)).
2. **Transitivity:** a value derived from a scoped value inherits that value's whole dependency set ([Rule 2: Transitivity](dependency-rules/projection-and-results.md#rule-2-transitivity)).
3. **Call results:** a scoped result depends on what the call was given ([Rule 3: Call results](dependency-rules/projection-and-results.md#rule-3-call-results)).
4. **Absorption:** after a call, every scoped `mutable` argument takes on what the other arguments borrow ([Rule 4: Absorption](dependency-rules/absorption-and-accesses.md#rule-4-absorption)).
5. **The callee side:** a function can return, throw or store only what its caller lent it ([Rule 5: The callee side](dependency-rules/absorption-and-accesses.md#rule-5-the-callee-side)).
6. **Dynamic accesses:** an access to an object, a `Slice` or a thread-local lasts until nothing uses it ([Rule 6: Dynamic accesses](dependency-rules/absorption-and-accesses.md#rule-6-dynamic-accesses)).

**Each body is checked alone, from the signatures of the functions it calls**, and borrows leave a function only as its signature states ([01](../01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)). So the rules divide the work:

- **Rules 1 and 2 follow a view inside one body**, from the place it was taken from to every value derived from it.
- **Rules 3 and 4 carry it across a call.** From the callee's signature, they tell the caller what the result and the arguments borrow after the call.
- **Rule 5 checks the callee's body against that signature**, so what rules 3 and 4 tell the caller holds without the caller seeing the body.
- **Rule 6 holds a dynamic access's run-time check** until the last use of every value that depends on the access.

**So the example needs no annotation.** Rule 4 tells the caller that `lines` now borrows `source`, and rule 5 checks inside `splitLines` that it stored nothing else.

## Subchapters

- [Projection, transitivity and call results](dependency-rules/projection-and-results.md)
- [Absorption, callee checks and dynamic accesses](dependency-rules/absorption-and-accesses.md)
