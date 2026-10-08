# 02 · Views and dependencies

Splitting a string into lines need not copy its characters. Each line can view part of the original string, but then the lines need that string's memory to remain available. Rayo tracks that connection, even when a function stores the views in a collection.

## Dependencies

```swift
func splitLines(_ text: StringView, into out: mutable List<StringView>) { ... }

var lines = List<StringView>()
splitLines(source.view, into: &lines)            // lines now borrows source
source.append("x")                               // error: source is borrowed by 'lines' (used below)
print(lines.count)
```

`source.view` lends access to the characters owned by `source`; it does not make a copy. The `StringView`s stored in `lines` are views of those characters. Appending to `source` could move its buffer and free the memory the lines still use, so the compiler rejects the append. The later use of `lines` keeps that borrow live.

Because the source's memory can be freed, a `StringView` is `Scoped`: it must stay within the scope that lent it, where the compiler can check its borrow. `List<StringView>` is scoped too, because it holds those views. [Scoped values](02-views-and-dependencies/scoped-values.md#scoped-values) sets out which other types have this restriction.

Knowing that `lines` is scoped is only part of the check. The compiler also needs to know *which* memory its views use. A scoped value's **dependency set** records the places and dynamic accesses it borrows, marking each borrow **shared** or **exclusive**. A value **carries** this set as it moves through the function. Until the value's last use, changing, moving or destroying a place it depends on must respect the law of exclusivity ([01](01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)).

One value can depend on several places at once. Here, `vis` borrows `sprites` exclusively and `grid.cells` shared, so growing `grid.cells` conflicts with the view even though `vis` is used to change sprites:

```swift
func visible(_ items: mutable List<Sprite>, in cells: Span<Cell>) -> MutableSpan<Sprite> { ... }

var vis = visible(&sprites, in: grid.cells.span)
grid.cells.append(c)                               // error: grid.cells is borrowed by 'vis' (used below)
cull(&vis)
```

The compiler begins with the place a view comes from ([Projection](02-views-and-dependencies/dependency-projection-and-results.md#rule-1-projection)). If another value is made from that view, it inherits the dependencies ([Transitivity](02-views-and-dependencies/dependency-projection-and-results.md#rule-2-transitivity)). This lets the compiler follow a borrow through the body that created it.

A call needs one more step, because the caller sees the callee's signature rather than its body. A scoped result takes on dependencies from the arguments ([Call results](02-views-and-dependencies/dependency-projection-and-results.md#rule-3-call-results)). A scoped `mutable` argument can also take on what the other arguments borrow; this is absorption ([Absorption](02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)). In the string example, absorption tells the caller that `lines` now borrows `source`.

The callee's body is checked against the same promise: it can return, throw or store a scoped value only if the caller can track what it borrows ([The callee side](02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)). That is why the caller can reject the append without inspecting `splitLines`. When a view comes through an object, a `Slice` or a thread-local, the compiler also keeps its run-time access check active for as long as the view needs it ([Dynamic accesses](02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)).

## Subchapters

- [Scoped values and types](02-views-and-dependencies/scoped-values.md)
- [Projection, transitivity and call results](02-views-and-dependencies/dependency-projection-and-results.md)
- [Absorption, callee checks and dynamic accesses](02-views-and-dependencies/dependency-absorption-and-accesses.md)
- [Destruction, precise dependencies and `rebind`](02-views-and-dependencies/dependency-lifetimes.md)
- [Projections and accessors](02-views-and-dependencies/projections-and-accessors.md)
