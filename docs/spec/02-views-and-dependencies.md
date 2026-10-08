# 02 · Views and dependencies

`splitLines` stores each line as a view into `source`. That saves a copy, but the views still read `source`'s characters. If `source` moves its buffer, they would point at freed memory.

## Dependencies

```swift
func splitLines(_ text: StringView, into out: mutable List<StringView>) { ... }

var lines = List<StringView>()
splitLines(source.view, into: &lines)
source.append("x")                               // error: source is borrowed by 'lines' (used below)
print(lines.count)
```

After `splitLines` returns, `lines` still holds views of `source`. The append could move the string's buffer, so the compiler rejects it while `lines` is still in use. The later `print` shows why the borrow has not ended yet.

Because the source's memory can be freed, a `StringView` is `Scoped`: it must stay within the scope that lent it, where the compiler can check its borrow. `List<StringView>` is scoped too, because it holds those views. [Scoped values](02-views-and-dependencies/scoped-values.md#scoped-values) sets out which other types have this restriction.

`Scoped` keeps the list inside the lending scope; it does not identify what the list borrows. For that, the compiler records a **dependency set**: every place or dynamic access the value borrows, marked **shared** or **exclusive**. The value **carries** this set as it moves through the function. Here, `lines` holds a shared borrow of `source`. Until the last use of `lines`, changing, moving or destroying `source` must respect that borrow under the law of exclusivity ([01](01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)).

A view can keep several places borrowed:

```swift
func visible(_ items: mutable List<Sprite>, in cells: Span<Cell>) -> MutableSpan<Sprite> { ... }

var vis = visible(&sprites, in: grid.cells.span)
grid.cells.append(c)                               // error: grid.cells is borrowed by 'vis' (used below)
cull(&vis)
```

`vis` is a mutable view of `sprites`, but `visible` also received a span of `grid.cells`. It therefore depends on `sprites` exclusively and `grid.cells` shared. Because `cull` uses `vis` after the attempted append, growing `grid.cells` conflicts with that shared borrow.

The compiler begins with the place a view comes from ([Projection](02-views-and-dependencies/dependency-projection-and-results.md#rule-1-projection)). If another value is made from that view, it inherits the dependencies ([Transitivity](02-views-and-dependencies/dependency-projection-and-results.md#rule-2-transitivity)). This lets the compiler follow a borrow through the body that created it.

A call needs one more step, because the caller sees the callee's signature rather than its body. A scoped result takes on dependencies from the arguments ([Call results](02-views-and-dependencies/dependency-projection-and-results.md#rule-3-call-results)). A scoped `mutable` argument can also take on what the other arguments borrow; this is absorption ([Absorption](02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)). In the string example, absorption tells the caller that `lines` now borrows `source`.

The callee's body is checked against the same promise: it can return, throw or store a scoped value only if the caller can track what it borrows ([The callee side](02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)). That is why the caller can reject the append without inspecting `splitLines`. When a view comes through an object, a `Slice` or a thread-local, the compiler also keeps its run-time access check active for as long as the view needs it ([Dynamic accesses](02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)).

## Subchapters

- [Scoped values and types](02-views-and-dependencies/scoped-values.md)
- [Projection, transitivity and call results](02-views-and-dependencies/dependency-projection-and-results.md)
- [Absorption, callee checks and dynamic accesses](02-views-and-dependencies/dependency-absorption-and-accesses.md)
- [Destruction, precise dependencies and `rebind`](02-views-and-dependencies/dependency-lifetimes.md)
- [Projections and accessors](02-views-and-dependencies/projections-and-accessors.md)
