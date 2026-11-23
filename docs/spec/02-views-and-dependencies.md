# 02 · Views and dependencies

Programs often need to work with part of a value without taking ownership of it. A parser might keep the lines of a string as references to its text; a renderer might work directly on part of a list. The string or list still owns the storage. If the owner moves or frees it while a reference to it is in use, the reference becomes invalid.

A reference is the plainest [view](02-views-and-dependencies/scoped-values.md#scoped-values), a value that borrows memory something else owns ([01](01-values-and-ownership/references.md#references)). When a view reaches memory that can be freed, Rayo keeps it in the scope that lent it. Its type is marked [`Scoped`](02-views-and-dependencies/scoped-values.md#scoped-values), so that limit follows it into other values. The compiler also records which storage the view depends on. Staying in scope alone would not tell it which owner must remain available, especially after a view passes through a function or is stored in a collection.

## Dependencies

For example, a function can fill a list with references to a string's text:

```rayo
func splitLines(_ text: &Text, into out: mutable &List<&Text>) { ... }

var source = alloc "first\nsecond"
var lines = alloc List<&Text>()
splitLines(source, into: mutable lines)
source.append("x")                               // error: source is borrowed by 'lines' (used below)
print("\(lines.count) lines")
```

The list owns its `&Text` references, but the text they refer to still belongs to `source`. Appending to `source` could move its buffer and free the old one. Because `lines` is used afterwards, the compiler rejects the append while those references still depend on the original buffer.

`&Text` is `Scoped`, as every reference is, and `List<&Text>` is scoped because it holds references.

In this example, `lines` depends on `source` through a shared borrow. More generally, a scoped value's **dependency set** records every place or dynamic access it borrows, marked **shared** or **exclusive**; the value **carries** that set as it moves through a function. Until the last use of `lines`, changing, moving or destroying `source` must respect the borrow under the law of exclusivity ([01](01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)).

A view can keep several places borrowed:

```rayo
func visible(_ items: mutable &List<Sprite>, in cells: &[Cell]) -> mutable &[Sprite] { ... }

var vis = visible(mutable sprites, in: grid.cells)
grid.cells.append(Cell())                          // error: grid.cells is borrowed by 'vis' (used below)
cull(mutable vis)
```

`vis` is a mutable reference to elements of `sprites`, but `visible` also received a reference to the elements of `grid.cells`. It therefore depends on `sprites` exclusively and `grid.cells` shared. Because `cull` uses `vis` after the attempted append, growing `grid.cells` conflicts with that shared borrow.

The compiler begins with the place a view comes from ([Projection](02-views-and-dependencies/dependency-projection-and-results.md#rule-1-projection)). If another value is made from that view, it inherits the dependencies ([Transitivity](02-views-and-dependencies/dependency-projection-and-results.md#rule-2-transitivity)). This lets the compiler follow a borrow through the body that created it.

A call needs one more step, because the caller sees the callee's signature rather than its body. A scoped result takes on dependencies from the arguments ([Call results](02-views-and-dependencies/dependency-projection-and-results.md#rule-3-call-results)). A scoped argument given to a `mutable &T` parameter can also take on what the other arguments borrow; this is absorption ([Absorption](02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)). In the string example, absorption tells the caller that `lines` borrows `source` after the call.

The callee's body is checked against the same promise: it can return or store a scoped value, an error included, only if the caller can track what it borrows ([The callee side](02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)). That is why the caller can reject the append without inspecting `splitLines`. When a view comes through an object, a `Slice` or a thread-local, the compiler also keeps its run-time access check active for as long as the view needs it ([Dynamic accesses](02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)).

## Subchapters

- [Scoped values and types](02-views-and-dependencies/scoped-values.md)
- [Projection, transitivity and call results](02-views-and-dependencies/dependency-projection-and-results.md)
- [Absorption, callee checks and dynamic accesses](02-views-and-dependencies/dependency-absorption-and-accesses.md)
- [Destruction, precise dependencies and assigning references](02-views-and-dependencies/dependency-lifetimes.md)
- [Place and value properties](02-views-and-dependencies/place-and-value-properties.md)
