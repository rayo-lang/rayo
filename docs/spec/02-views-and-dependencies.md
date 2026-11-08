# 02 · Views and dependencies

Programs often need to work with part of a value without taking ownership of it. A parser might keep the lines of a string as views of its characters; a renderer might work directly on part of a list. The string or list still owns the storage. If the owner moves or frees it while a view is in use, the view becomes invalid.

When a view reaches memory that can be freed, Rayo keeps it in the scope that lent it. Its type is marked [`Scoped`](02-views-and-dependencies/scoped-values.md#scoped-values), so that limit follows it into other values. The compiler also records which storage the view depends on. Staying in scope alone would not tell it which owner must remain available, especially after a view passes through a function or is stored in a collection.

## Dependencies

For example, a function can fill a list with views into a string:

```swift
func splitLines(_ text: StringView, into out: mutable List<StringView>) { ... }

var source = String("first\nsecond")
var lines = List<StringView>()
splitLines(source.view, into: &lines)
source.append("x")                               // error: source is borrowed by 'lines' (used below)
print(lines.count)
```

The list owns its `StringView` values, but the characters those views read still belong to `source`. Appending to `source` could move its buffer and free the old one. Because `lines` is used afterwards, the compiler rejects the append while those views still depend on the original buffer.

`StringView` is `Scoped` under that rule, and `List<StringView>` is scoped because it holds those views.

In this example, `lines` depends on `source` through a shared borrow. More generally, a scoped value's **dependency set** records every place or dynamic access it borrows, marked **shared** or **exclusive**; the value **carries** that set as it moves through a function. Until the last use of `lines`, changing, moving or destroying `source` must respect the borrow under the law of exclusivity ([01](01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)).

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
