# 02 · Views and dependencies

## Scoped values

A **view** is a value that borrows memory something else owns:

```swift
let text: StringView = source.view            // borrows source's characters: no copy
let body: Span<Vertex> = mesh.vertices.span   // borrows the list's elements, read-only
var hot = &heat.span                          // a MutableSpan<Float>: borrows them mutably
```

**A view of memory that can be freed must stay within the scope that lent it.** A type whose values must do so conforms to the marker protocol **`Scoped`**, and any value of such a type is a **scoped value**. Among them are:

- the views `Span<T>`, `MutableSpan<T>`, `StringView`, `Borrow<T>` and `MutableRef<T>`;
- the iterators of collections, spans and strings;
- lock guards;
- the existential views `any P` and `mutable any P`;
- function-typed values, and closure literals that capture by reference or hold a scoped capture ([05](05-protocols-generics-and-closures.md#functions-and-closures)).

**An iterator that borrows nothing is unscoped**, such as a `Range`'s. So a task may `await` inside `for i in 0..<n`.

**A view needn't be scoped when nothing can free its memory while it reads it.** A `StaticSpan<T>` is unscoped, since it views immortal data ([09](09-compile-time.md#staticspan-views-of-immortal-data)). So is a `Slice<T>`, which reads its buffer only through a scoped span it hands out for each use ([06](06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers)). Any other view of memory that can be freed is scoped.

**Making a view from a raw pointer requires `unsafe`.** Safe code gets views only from what owns the memory.

**A type may be scoped without borrowing anything**, such as a profiling zone. It then can't be kept in a global or an unscoped type, or across an `await` ([below](#where-a-scoped-value-can-go)).

**A view that holds a mutable borrow is also `~Copyable`**, since two copies would be two mutable aliases:

```swift
struct Span<Element>(                                  // shared view: copyable
    public unsafe let baseAddress: *Element,
    public let count: Int,
): Scoped

struct MutableSpan<Element>(                           // exclusive view: move-only
    public unsafe let baseAddress: *Element,
    public let count: Int,
): Scoped, ~Copyable
```

### Where a scoped value can go

**A scoped value can live in locals, parameters, and the fields, elements, payloads and captures of other scoped values.** It can't be stored in an unscoped type, or anywhere else that requires `~Scoped` ([below](#generic-code-and-scoped)), such as a global. It can't live across an `await` either ([07](07-concurrency.md#semantics)).

### Which types are scoped

**A type with a scoped field or payload is scoped:**

- **Declared types.** A struct, enum or union with a field or payload whose type is scoped where the type is declared must be declared `Scoped`.
- **Generic types.** A generic type is scoped when a stored field or payload is, once its type arguments are substituted, its associated types resolved and its `static if` and `static for` members generated. This is checked as `Sendable` is ([07](07-concurrency.md#what-may-cross-threads-sendable)).
- **Raw pointers.** A field or payload of raw pointer type `*T` counts as scoped when `T` is.

So `List<StringView>`, `Map<StringView, Int>`, `Optional<Span<T>>` and `(StringView, Int)` are scoped, though the collections among them still own their heap memory. `Handle<Token>` and `Type<StringView>` aren't, since neither holds what its argument names. `struct Cursor<C: Collection>(var it: C.Iterator)` needn't be declared `Scoped`, but `Cursor<List<Int>>` is scoped, since a list's iterator is.

**The generic types that erase a type are the exceptions, and are unscoped.** These are `Box<any P>`, the object pointers, reference-counted pointers and weak links to `any P` ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)), and `Closure<F>` ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref)). Their argument names the kind of value they erased, which is always unscoped. Binding a type parameter to `any P` never makes an unscoped existential ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)).

### Generic code and `~Scoped`

**An unconstrained type parameter may be scoped**, and so may a type that depends on one, such as:

- an associated type, such as `C.Iterator`;
- a type whose members a `static if` or `static for` generates from a generic parameter, type or value.

A value of such a type follows the dependency rules as if it were scoped, so rule 5 applies when it is returned or stored ([below](#rule-5-the-callee-side)).

**Code that must let a `T` outlive its scope requires `T: ~Scoped`**, which every unscoped type satisfies. So `Mutex.lock` is `func lock<R: ~Scoped>(_ body: consuming (mutable T) -> R) -> R`. The closure can compute any unscoped result from the protected data. It can't smuggle out a view of it as its result, which would be scoped, or through its captures, since its parameter isn't declared `keep` ([05](05-protocols-generics-and-closures.md#what-a-closure-may-keep-keep)).

**`~Scoped` is also required implicitly wherever a value can outlive the function that stores it, or be reached without its borrows:**

- globals, `@threadlocal var`s included;
- objects' values;
- a leaked `Box`'s value, which a `RawAllocation` holds with no borrows ([06](06-memory-and-allocators.md#owning-boxes));
- unscoped closures' captures;
- the contents of every `Synchronized` generic, such as `Mutex<T>` or a queue, whose methods take a shared `self`, so absorption (rule 4, [below](#rule-4-absorption)) can't track what goes in ([07](07-concurrency.md#the-synchronized-contract));
- the concrete type in every conversion to an unscoped existential (`Box<any P>`, and each object pointer, reference-counted pointer and weak link to `any P`), since erasure would hide what the value borrows;
- task parameters and a `task func` method's `self`, which a task keeps in its state ([07](07-concurrency.md#semantics));
- the elements of a `StaticSpan`, which outlive every scope ([09](09-compile-time.md#staticspan-views-of-immortal-data)).

**In a type, `~` means "not", and comes only before `Copyable`, `Sendable` and `Scoped`** ([01](01-values-and-ownership.md#copies)).

- In a conformance list, `~Copyable` and `~Sendable` opt a type out of a derived conformance ([07](07-concurrency.md#what-may-cross-threads-sendable)).
- In a constraint, `T: ~Scoped` requires that `T` isn't scoped.

An unconstrained type parameter may be move-only, scoped and not `Sendable`, so none of those needs a `~`.

### Dependencies

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

A scoped value's **dependency set** is the places and dynamic accesses it borrows from, each marked **shared** or **exclusive**. What a value **carries** is its dependency set.

**Until a value's last use, every place in its set counts as borrowed, with its kind.** The compiler works the set out inside one function body, from six rules:

1. **Projection:** a view taken from a place depends on that place ([below](#rule-1-projection)).
2. **Transitivity:** a value derived from a scoped value inherits that value's whole dependency set ([below](#rule-2-transitivity)).
3. **Call results:** a scoped result depends on what the call was given ([below](#rule-3-call-results)).
4. **Absorption:** after a call, every scoped `mutable` argument takes on what the other arguments borrow ([below](#rule-4-absorption)).
5. **The callee side:** a function can return, throw or store only what its caller lent it ([below](#rule-5-the-callee-side)).
6. **Dynamic accesses:** an access to an object, a `Slice` or a thread-local lasts until nothing uses it ([below](#rule-6-dynamic-accesses)).

Rule 4 tells the caller that `lines` now borrows `source`, and rule 5 checks inside `splitLines` that it stored nothing else, so neither needs an annotation.

#### Rule 1: Projection

**A view taken from a place depends on that place.** It depends shared for a read projection such as `pool[h]` or `list[i]`, and exclusively for a `modify` projection ([below](#projections-read-and-modify-accessors)). A view that a `get` builds, such as `list.span` or `s[a..<b]`, depends on the place by rule 3 ([below](#rule-3-call-results)).

- **Through a shared view, the place drops out where declared.** A `get` declared `where return outlives self`, or a projection declared `where yield outlives self`, gives a sub-view that is a narrower copy of the shared view ([below](#staying-valid-after-a-parameter-moves-on-outlives)). So the sub-view depends only on what the view carries, not on the variable holding it. `rest = rest[1...]` can then reassign an iterator's span while an element taken from it is live, and `Token(text: src[start..<pos])` depends on the text, not on the lexer's field. Verification rejects the claim for a view of data the type holds inline, such as a `[4 of Int]` field, which depends on `self` itself.
- **Through a place that owns its value, or an exclusive view, projections depend on the place itself.**
- **Through an access-bound projection, a view depends on the access.** An access-bound projection, one with no `yield` item in its `where` clause, may yield a temporary ([below](#projections-read-and-modify-accessors)). So a view of it depends on the **access**, which is held as rule 6 holds a dynamic access. The access is in the yielded value's own set, so it follows every value derived from it, even where the place drops out. It also keeps the places the accessor was given lent.

#### Rule 2: Transitivity

**A value derived from a scoped value inherits that value's dependency set.** A copy or a sub-view inherits it whole. A stored field or tuple element inherits that field's set, where the caller keeps one ([below](#naming-a-field)).

#### Rule 3: Call results

**A scoped result depends on what the call was given:**

- on every borrowed or `mutable` argument, `self` included: both **the argument place and its dependency set**;
- on the sets of scoped `owned` arguments.

**A `mutable` argument's place is held exclusively, and a borrowed one's shared.** Each set keeps its own kinds, so a view taken through a borrowed `MutableSpan` still holds what the span holds exclusively.

**A thrown error is a result too**: what a `catch` binds depends on the arguments the same way.

##### Closure calls

**Calling a closure is a call whose `self` is the closure.** `self` is borrowed for a non-`mutating` closure, `mutable` for a `mutating` one and `owned` for a `consuming` one ([05](05-protocols-generics-and-closures.md#closure-kinds)). A closure never lends out its owned captures (rule 5), so the result depends on the closure's dependency set: what it captures by reference, and what its owned captures carry. So `let get = { src.view }; let v = get()` makes `v` depend on `src`.

**Only a value whose type can hold a function value can depend on a closure's storage.** A function-typed argument depends on its closure's storage, as well as on what the closure carries ([05](05-protocols-generics-and-closures.md#function-typed-values)). No call of a closure returns anything depending on its own storage (rule 5), and nothing else sees into it. So only a value holding the function value can reach the storage.

**The storage a function-typed argument views is a dependency of the call's result, or of an absorbing argument (rule 4), unless that value's type is sealed.** A **sealed** type is a concrete type in which nothing is one of these, at any depth of fields, elements, payloads and type arguments:

- a function type, or a closure's concrete type;
- an interpolated literal's type ([04](04-types.md#strings));
- a `some P` or an `any P`, owned or a view;
- a type parameter or an associated type.

Every other type is **unsealed**. What the closure carries always flows. So `func names(_ t: Span<Token>) -> List<StringView> { t.map { copy $0.text } }` compiles: the list depends on what `t` views, not on the literal.

**A place captured exclusively ties the result to the closure.** Take a call that doesn't consume the closure, and returns a result depending on a place the closure captures exclusively: the place itself, not what it carries. The result then also depends, exclusively, on the function value and the storage it views, whatever the result's type, as a `mutating` method's result depends on `self`. The sealed-type exemption never removes this tie.

```swift
var grow = { () -> Span<Int> in buf.append(0); return buf.span }
let a = grow()
grow()                           // error: 'grow' is borrowed by 'a' (used below)
use(a)
```

`{ reader.readLine() }` stays lending the same way.

**The tie also binds a call that is passed a `mutating` closure, or a new view of one, without consuming the closure itself.** Its result and absorbing arguments depend, exclusively, on that closure's storage whenever they may depend on a place the closure captures exclusively. So with `func once(_ f: consuming () -> Span<Int>) -> Span<Int>`, `let a = once(&grow); grow()` conflicts too.

**The tie follows what the caller can see:**

- **A local closure literal.** A local with no type annotation, initialized with a closure literal, has the literal's own anonymous type ([05](05-protocols-generics-and-closures.md#closures-by-concrete-type-some-f)) and never holds another closure. So for a call on it, the compiler knows what the result depends on, and ties it only when that is an exclusively captured place. A tokenizer closure that advances a captured `pos` and returns views of a shared `src` hands out tokens that outlive the next call.
- **Everywhere else, the body is out of sight**, as in a local declared with a function type, a closure parameter, a stored or generic closure, a `some F`, or an element of a list of closures. There the tie applies to every call of a `mutating` function value, since it may carry an exclusive dependency. So `func twice(_ f: mutable (mutating () -> Span<Int>))` can't hold `f()`'s result across a second `f()`.

##### Shallow values

A copyable type that holds no inline array, at any depth, is **shallow**, scoped or not. Shallow types include:

- `Int`, a `Range` and `Vec3`;
- a `Simd` vector, whose lanes are never viewed ([04](04-types.md#simd-and-math));
- `Span`, `StringView` and [`Borrow<T>`](04-types.md#iteration);
- a shared `any P`, and a non-`mutating` function value;
- a `Token` of a `StringView` and an `Int`;
- tuples and `Optional`s of those.

**When a result or an absorbing argument has a sealed type, a shallow argument contributes only its dependency set**, not the argument place. Safe code can view a shallow value's own bytes only through an `any P` made from it, a closure capturing it by reference, or an interpolated literal borrowing it. Only an unsealed type can hold any of these.

The rule holds whatever the argument's convention, and whether it is a variable, a parameter or a temporary. To such a result, an unscoped shallow argument contributes nothing. For example:

- `splitLines(source.view, into: &lines)` leaves only `source` borrowed;
- `let r = grid.row(y + 1)` depends on `grid` alone;
- `parts.append(data[0..<n])` makes a `List<Span<Float>>` depend on `data` alone;
- `func nearest(_ es: Span<Enemy>, to p: Vec3) -> Borrow<Enemy>? { es.min(by: { … }) }` returns what `es` views.

**A value that holds an inline array, such as a matrix of four `Vec4` columns, can lend its elements.** So a result keeps depending on the argument place, as every result of an unsealed type does.

**A function value received `owned` absorbs, at the call, only what a call of it can store through its `keep` parameters** ([05](05-protocols-generics-and-closures.md#what-a-closure-may-keep-keep)). So its type counts as sealed there when every `keep` parameter's type is. The same holds for a closure of concrete type received `owned` through a `some F` parameter, or through a type parameter constrained to a function type. So `forEachLine(src.view) { line in lines.append(copy line) }` leaves only `src` borrowed. One passed `mutable`, which the callee may replace with another closure, stays unsealed.

**In generic code, a type is shallow only if it is for every type argument its constraints allow.** `Span<T>` is. `T`, `T?`, `(T, Int)`, an associated type, and a struct whose fields a `static if` or `static for` generates aren't.

**Two kinds of `unsafe` code make promises these rules rely on:**

- **Code that views a shallow value's bytes with `ptr(to:)`** promises never to return or store that view where a sealed type holds it.
- **Code that keeps a value through a raw pointer**, reading it after the call that gave it the value returns, promises that the holding type says what it holds, since rules 3 and 4 read only types. The type must be scoped if the value is, as a field `*T` makes it for a `T`. It must be unsealed if the value is, or may be, a closure, a function value or an `any P`, as a type parameter, an associated type or a `some P` may be.

**Code that keeps a value through a raw pointer also promises what it hands out of that storage.** What it later hands out borrows nothing that the handing-out call's dependencies don't give it, by the dependency rules and its `where` items. That covers a result, a yield, and a store through a `mutable` parameter. So storage that one value absorbs into and another hands out of, such as a channel's two ends, holds only `~Scoped` values ([07](07-concurrency.md#queues-and-channels)).

##### Mutable views

**Mutable views need an exclusive input.** A **mutable view** is a value through which what it views can be changed:

- a `MutableSpan`, a `MutableRef` or a `mutable any P`;
- a lock guard;
- a `mutating` or `consuming` function value, or a closure with an exclusive capture;
- a value holding one of these.

**A scoped value that only holds shared views is no mutable view**, as `List<StringView>` isn't. Neither is a function value made from a named function, or from a literal that captures nothing, since it views no storage.

**A function that returns a mutable view must take a `mutable` argument or an `owned` mutable view**, such as `func rest(_ s: owned MutableSpan<T>) -> MutableSpan<T>`. A borrowed `MutableSpan` doesn't qualify, since a second view could then write what the first still reads. An `unsafe` function is exempt (next).

**`unsafe` code that builds a mutable view answers for it**, since the signature's shape isn't enough: the code can take a dummy `mutable` argument. This covers a `MutableSpan`, a `MutableRef`, and a type of the code's own, declared `~Copyable`, that changes what it views through a raw pointer. The code promises that everything the view can change lies in a `mutable` argument's place, or in storage that place owns, or is reached through an exclusive dependency that an argument passed `mutable` or `owned` carries. It promises too that none of it is reached only through a borrowed argument or what one carries.

**In an `unsafe` function, that promise is its caller's**: that nothing else reaches what the view can change while it lives ([10](10-errors-and-safety.md#unsafe-code)). `S.trailing(at:count:)` is one such function ([08](08-c-interop.md#what-imports-as-what)).

**Two kinds of mutable view may come from a shared input, since their exclusivity is enforced at run time:**

- **A value that depends on an exclusive dynamic access its call begins** (rule 6), as the span a `Slice`'s `lock()` returns does ([06](06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers)).
- **A value of a guard type** ([below](#lock-guards-are-released-on-the-thread-that-took-them)), whose exclusivity its `Synchronized` type enforces. A `Synchronized` method may return one from a shared `self`, as `Mutex.lock()` does, and any function may pass one on: `func lockRegistry(_ s: Services) -> MutexGuard<Registry> { s.registry.lock() }`.

##### Temporaries

**An argument that isn't a place is a temporary**, like `makeArray()` in `first(makeArray())`. An `owned` parameter takes it over, so only its set flows.

**A temporary passed borrowed or `mutable`, `self` included, lives to the end of its full statement**, and a value depending on it can't outlive that. So `let x = first(makeArray())` is an error if `x` is used later.

A **full statement** is a statement, except that each of these is a full statement of its own:

- a condition of an `if`, `guard`, `while` or `repeat … while`;
- a `when` subject;
- the condition of each arm of a `when` without a subject;
- a `where` guard of a `when` arm or a `catch`.

So the temporaries of each of these die before the body runs, unless a value subject is kept in a hidden local ([01](01-values-and-ownership.md#conditions-and-patterns)). That makes `if let x = first(makeArray()) { use(x) }` an error too.

**A scoped temporary gets no exemption**, since it may hold data inline that a borrowed callee lends out. Only its set flows in two cases:

- when it is shallow, and the result or absorbing argument is sealed ([above](#shallow-values));
- when the callee's `where` clause says the result, or what it yields, `outlives` the parameter it is passed for ([below](#precise-dependencies-opt-in)), as a `where return outlives self` `get` or a `where yield outlives self` projection does.

So `arr.span.min(by: …)` and `src.view[a..<b]` leave only `arr` and `src` borrowed. An unscoped shallow temporary contributes nothing.

**Two kinds of temporary can be kept in hidden locals instead:**

- a `for` loop's sequence expression keeps its temporaries in hidden mutable locals until the loop ends;
- a closure literal can be kept in a hidden local of a local's scope ([05](05-protocols-generics-and-closures.md#function-typed-values)).

#### Rule 4: Absorption

**After a call, every scoped `mutable` argument, a `mutating` method's `self` included, takes on what the other arguments borrow**, and so do an `owned` argument that is a mutable view and a `modify`'s yield (below). It takes the places and sets of the borrowed ones, and the sets of the `mutable` and scoped `owned` ones, with the kinds of rule 3. So `tokens.append(Token(text: src.view))` makes `tokens` depend on `src`, and `lexer.lex(into: &tokens)` leaves `lexer` and `tokens` free of each other. Another `mutable` argument's place flows in only when a `where` item names it ([below](#precise-dependencies-opt-in)), as for a function that keeps views of one argument in another: `func chunks(_ data: mutable List<Float>, into work: mutable List<MutableSpan<Float>>) where work borrows data`. Assigning a whole new value replaces the set of a variable that owns its value, and assigning a stored field replaces that field's set ([below](#naming-a-field)), where the place assigned is known: through a binding that may name one of several places, as after `var r = if flip { &d1 } else { &d2 }` or a `rebind` on one path, the assignment adds to each place's set. Any other change to part of a value, such as to an element, adds to it.

- **Stores through an exclusive view reach what it views.** A dependency added to an exclusive view, or to a place reached through one, is also added to **every place the view depends on exclusively**, transitively: by assignment through the view (`v = tmp.span` in `for var v in &views`), by absorption into it (`fill(&left, tmp.span)` on a `split` half), or by storing a borrow into a list of exclusive views (`d = &crate`). Each time, the collection the view came from now depends on `tmp` or `crate`. Writing a whole new value through an exclusive view adds and never replaces.
    - If such a place belongs to the caller, the store is a store into the caller's place, and rule 5 applies, whatever convention brought the view in: a `mutable` parameter, an `owned` `MutableSpan`, a `mutable any P`, or an owned `mutating` closure with exclusive captures. Every exclusive dependency a parameter carries in is treated like a `mutable` parameter, by rule 5 and by its use at every exit (below).
    - On the caller's side, an argument passed `owned` that is itself a mutable view (rule 3), such as an `owned` `MutableSpan`, a `mutable any P` or a `mutating` closure, absorbs like a `mutable` one: `poison(consume left)` makes `views`, which `left` was split from, absorb the call's other arguments. A borrowed argument absorbs nothing, whatever it carries, since nothing is stored through a borrowed view.
    - In generic code, a value whose type may be a mutable view counts as one for these two rules: a type parameter, an associated type, a `some P`, or a type that depends on one, unless its constraints include `Copyable` or `~Scoped`. So an `owned T` absorbs like a `mutable` argument, and what a parameter of such a type carries in counts as exclusive, so a `put(local.view)` through an `owned T: Sink` is a store into the caller's place.
- **Creating a closure.** It counts, for these rules, as a call to a primary initializer whose arguments are its captures, which no code can name or call ([09](09-compile-time.md#what-reflection-can-read)): an exclusive by-reference capture is a `mutable` argument, a shared one borrowed, and an owned one `owned`. So `var add = { names.append(tmp.view) }` makes `names` depend on `tmp` at creation, whether or not `add` is called. A `consuming` closure's exclusive captures also take on each other's places, since its one call may store a view of one into another (rule 5).
- **Calling a closure.** Its `mutable` arguments absorb the closure's dependency set, as its `self` (rule 3): with `let put: (mutable List<StringView>) -> Void = { o in o.append(src.view) }`, `put(&out)` makes `out` depend on `src`. One that absorbs a place the closure captures exclusively also depends on the closure, exclusively, unless the call consumes it, decided by what the caller can see. The closure itself absorbs **only what its `keep` arguments carry**, never the argument places ([05](05-protocols-generics-and-closures.md#what-a-closure-may-keep-keep)), a `mutating` closure into itself and so into the places it depends on exclusively. Its other parameters are call-scoped, so nothing it was lent reaches its captures.
- **A projection access.** It is a call to its accessor, with the subscript's arguments and `self`, and a `modify`'s yield is one more `mutable` argument, since the code after the `yield` may store what the caller wrote there: a subscript's `mutable` parameter absorbs it ([Projections](#projections-read-and-modify-accessors)).

#### Rule 5: The callee side

**A function can return, throw or store only what its caller lent it.** A returned or thrown scoped value, and anything stored into a scoped `mutable` parameter, may depend only on:

- the borrowed or `mutable` parameters and their dependency sets, except that what is stored into a `mutable` parameter depends on another `mutable` parameter itself only when a `where` item names it (rule 4);
- the sets carried in by scoped `owned` parameters, which belong to the caller and flow back through rules 3 and 4;
- **static storage**: global `let`s and `const`s ([07](07-concurrency.md#global-state)), and the views that the `Synchronized` values in them lend, such as a lock guard or `Once.get()` ([07](07-concurrency.md#the-synchronized-contract)). Such a global is never moved or destroyed ([07](07-concurrency.md#shutdown)). What a C entry returns to C, or stores into what C lent it, may depend on less ([08](08-c-interop.md#c-representations)).

```swift
func name() -> StringView {
    let s: String = "temp"
    return s.view                      // error: returned view depends on local 's', which is destroyed on return
}
```

Rule 5 rejects:

- **a view of what the function itself owns or began**, which is a local, storage an `owned` parameter owns (not the borrows it carries), a thread-local, or a dynamic access or access-bound projection begun inside the function. The non-`mutable` parameters of an `@export` or `@c` function, or of a closure literal converted to a `@c` type, count as `owned` here, since C passes them by value ([08](08-c-interop.md#calling-rayo-from-c));
- **anything stored into a `mutable` parameter `p` that depends on a place overlapping `p`**, such as `d.first = d.text.view` in `func index(_ d: mutable Doc)`, since rule 4 tells the caller nothing new about its own argument. In the caller's own body, `doc.first = doc.text.view` is fine: `doc` then depends on `doc.text`, and it is an error only when destroying `doc` uses that dependency ([below](#when-destroying-a-value-counts-as-using-it));
- **anything stored through a parameter's exclusive dependencies that depends on the parameter's own storage**, which rule 4 never reports: in a `mutating` method of a struct holding `out: MutableSpan<StringView>` and `s: String`, `out[0] = s.view` is an error, while `out[0] = copy view` for a field `view: StringView` is fine.

**Scoped `mutable` parameters count as used at every exit**: each `return`, `throw` and propagating `try`, and the end of the body. So a callee can't store a view into `out` and then free what it points at, even on its way out with an error.

**In a closure body**, the closure is checked as a method whose `self` is the closure:

- **By-reference captures** are places `self` depends on, shared or exclusive, and a result or a store into a `mutable` parameter may depend on them.
- **Owned captures** are always an `owned` parameter's own storage, whatever the closure's kind, since a closure may be called through a view of its storage, and a call through a `consuming` type ends that view and destroys a `consuming` closure's captures ([05](05-protocols-generics-and-closures.md#closure-kinds), [05](05-protocols-generics-and-closures.md#function-typed-values)). So a result or a store may depend on what they carry, never on the captures themselves: `{ [move s] in s.view }` is an error.
- **A store into a capture** may depend on places captured by shared reference, on what any capture carries, on what parameters declared `keep` carry ([05](05-protocols-generics-and-closures.md#what-a-closure-may-keep-keep)), and on static storage. It may not depend on a place the closure captures **exclusively**, unless the closure is `consuming`, since the next call may change or free it: `{ buf.append(1); views.append(buf.span) }` is an error. So `entries.map { $0.name.view }` may return what depends on its parameter, but can't store it.

#### Rule 6: Dynamic accesses

**An access to an object, a `Slice` or a thread-local lasts until nothing uses it.** An access to an object's value, through its owner or a weak pointer, to a `Slice`'s buffer, through its `read()` or `lock()` ([06](06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers)), or to a thread-local `var`, is itself a dependency. A view derived from it (`r.value!.items.span`) or passed through a call (`first(r.value!)`) depends on it, and **the access is held until the last use of every value that depends on it**, so the run-time mark covers the view for its whole life. An access-bound projection's access is held the same way, its accessor suspended at the `yield`.

**A site in a loop holds one access at a time.** Each time a site in a loop's body or its `while` condition begins a dynamic access, or an access-bound projection's access, no value that depends on the access it began the last time may be used from then on. So `for w in nodes { names.append(w.value!.name.view) }` is an error, since every pass would keep its own access: the second pass's `append` uses `names`, which depends on the first pass's. A `rebind` step through objects may begin its access while its own target still depends on the previous one, since the step moves the target to the new access ([below](#pointing-a-name-at-another-place-rebind)).

### When destroying a value counts as using it

```swift
var m = Mutex(0)
var g = m.lock()
g.value += 1                                  // g's last use written out
owned var n = consume m                       // error: destroying g at scope end still uses m
```

A few values act when destroyed, as a lock guard unlocks its mutex, so **destroying a value is a use** when it is, or holds at any depth, one of these, a field `*T` holding a `T` as it does for [scopedness](#which-types-are-scoped):

- a value whose type declares a `deinit` that isn't `PlainDeinit` (below);
- a `consuming` function value, which may own handed-over captures in the storage it views ([05](05-protocols-generics-and-closures.md#function-typed-values));
- a value of a type parameter, an associated type or a `some P`, unless constrained `Copyable` or `TrivialFree` ([06](06-memory-and-allocators.md#releasing-a-value-without-destroying-it-trivialfree)), since generic code is checked once for every type it may stand for;
- in generic code, a value of a type whose members a `static if` or `static for` generates from its generic arguments, when those members may include a `deinit` or a stored field ([09](09-compile-time.md#generated-members-are-checked-per-instantiation)), unless a `where` clause states it `Copyable` or `TrivialFree`.

Such a value stays live until it is destroyed: at scope end, when overwritten or consumed, or, if it is maybe-initialized ([01](01-values-and-ownership.md#places-that-hold-no-value)), at the scope end or assignment that destroys it if it still holds a value. Its destruction uses its whole dependency set when it is itself one of the values above, or when it is an enum, an optional included, an inline array, a `Box` or a value of a type parameter that holds one, whose parts have no sets of their own ([below](#naming-a-field)). Otherwise, for a struct or tuple, it uses only the sets the caller keeps for the stored fields and tuple elements that are or hold one, each by the same rule. It holds the dynamic accesses in those sets until then (rule 6). Any other value is live only until its last use.

**What its destruction uses can't include a part of itself**, at any depth: that conflicts with destroying it, as moving it would, since a `deinit` takes an owned `self` and may change one part before reading another. With `struct Doc(var text: String, var first: StringView?): Scoped`, `doc.first = doc.text.view` is fine, and still is when `Doc` holds a lock guard in another field, whose destruction uses only the guard's own set. It is an error once `Doc` has a non-`PlainDeinit` `deinit`, or when the guard locks a mutex that `Doc` holds.

A type conforms to **`PlainDeinit`**, with `unsafe` ([10](10-errors-and-safety.md#safe-modules)), when its `deinit` only destroys what it owns alone and frees its own buffers: destroying one uses only what destroying its elements uses, and skipping its own `deinit` can only leak. Any `deinit` may be skipped, as a stale value's elements' are ([10](10-errors-and-safety.md#unsafe-code)). So a `List<StringView>`, whose std type conforms, keeps nothing borrowed when dropped at scope end, while a `List<MutexGuard<T>>` keeps its mutexes borrowed until then. An object's owner, a `Pin`, a `LocalPin` and `Shared` don't conform, since their `deinit`s change state they don't own alone.

### Lock guards are released on the thread that took them

```swift
var g = registry.lock()
Thread.start { [move g] in g.value.flush() }  // error: a guard isn't Sendable, so it stays on the thread that took it
```

A **guard type** is declared `@guard`: the type of a value that holds a lock for as long as it lives, which a `Synchronized` type's method returns from a shared `self` (rule 3), as `MutexGuard` is. `@guard` makes it `Scoped`, `~Copyable` and `~Sendable`, and nothing that isn't `Sendable` moves to or is lent to another thread, even inside a type parameter, an existential or a closure. So a guard is dropped, or consumed as a `Condvar` wait consumes one, only on the thread that took it, as many platform mutexes require ([07](07-concurrency.md#locks-mutex-and-rwlock)).

### Precise dependencies (opt-in)

By default a result depends on every argument rule 3 names, even one it only read. When that gets in the way, as with a lookup keyed by a view into a buffer you want to advance, the function says what its result borrows in its `where` clause:

```swift
extension SymbolTable {
    func find(_ key: StringView) -> Span<Symbol>?
        where return borrows self                // the result borrows only the table, not the key
}

func split(_ text: StringView, by separator: StringView, into out: mutable List<StringView>)
    where out borrows text                       // 'out' takes on only text, not 'separator'

func builtinName(_ key: StringView) -> StringView
    where return borrows static                  // only static data: the key doesn't stay borrowed

let tok = lexer.peek()                           // shared on lexer
let syms = symbols.find(tok.text)                // shared on symbols only
lexer.advance()                                  // OK: tok's last use is above
use(syms)
```

- **What depends** is `return` (the result and any thrown error), `yield` (what an accessor yields, [Projections](#projections-read-and-modify-accessors)), or a parameter that absorbs under rule 4, for what it takes on: a `mutable` one, `self` in a `mutating` method included, or an `owned` one that is a mutable view, such as an `owned` `MutableSpan`.
- **`borrows x`** makes it depend on the parameter `x` and what `x` borrows, and on no other parameter, though it may still view static storage, as rule 5 allows every function; rules 3 and 4 apply to `x` alone, so a shallow argument still contributes only its set to a sealed subject. **`borrows static`** means static storage only. **`outlives x`** means only what `x` borrows, so it stays valid after `x` changes or is gone ([below](#staying-valid-after-a-parameter-moves-on-outlives)).
- **Several items** may name one subject, which then depends on all of them: `where return borrows self, return borrows key`. A subject no item names follows the default rules.

The compiler **verifies the clause in the callee**, with rule 5 restricted to what the items name, so a wrong clause is a compile error. The clause names parameters, their stored fields ([below](#naming-a-field)) or `static`, nothing more. A view that `unsafe` code builds from a raw pointer carries no dependencies to verify, so its signature's dependencies, by the default rules or the clause, are part of what that code promises.

#### Staying valid after a parameter moves on: `outlives`

`where return outlives self` is how an iterator over shared elements hands out elements that outlive the iteration:

```swift
struct SpanIterator<T>(var rest: Span<T>): SharedIterator, Scoped {
    mutating func next() -> Borrow<T>? where return outlives self { ... }   // elements borrow the collection, not the iterator
}

var names = List<StringView>()
for s in table.entries { names.append(s.name.view) }   // names depends on 'table', shared
use(names)                                              // fine; mutating 'table' here would be the error
```

Without the clause, each element would depend exclusively on the iterator, and the next `next()` would conflict with `names`. Iterators that hand out **mutable** views ([`MutableRef`](04-types.md#iteration), or `MutableSpan` chunks) stay lending, since two live exclusive views from one iterator would alias.

- **`outlives x` requires that nothing `x` carries can be changed through `x` or end with it.** So `x`'s type can hold no mutable view (rule 3), and destroying one is no use ([above](#when-destroying-a-value-counts-as-using-it)); in generic code, for every type argument its constraints allow. `Span`, a span iterator and `List<StringView>` qualify, so `func copyAll(from src: List<StringView>, into dst: mutable List<StringView>) where dst outlives src` leaves `src` free once it returns, where by default `dst` would keep the borrowed `src` itself borrowed. An iterator over a `MutableSpan` could hand out a view and then replace the data under it. A read guard carries only a shared borrow, but dropping it releases the lock, so a guard's `.value` is declared `where yield borrows self`. Inside `next()`, verification uses rule 1's shared-view case: `let b = rest.first; rest = rest[1...]; return b` gives `b` the collection's set, not the field's.
- **Generic code sees the clause through the protocol.** `IteratorProtocol.next()` has no clause, because some iterators over shared elements lend, such as a line reader that reuses one buffer, so generic code over it treats elements as lent. The refinement **`SharedIterator`** declares `next()` `where return outlives self`, and `Collection` requires `Iterator: SharedIterator`. **A witness must satisfy its requirement's clause**, depending on no more than it declares, which the compiler checks at the conformance.
- **A value moved out of an owner carries only what the owner carried.** `where return outlives p` is also allowed, whatever `p` carries, on a function whose result is **moved out** of the own storage of `p`, where `p` is `self` or a `mutable` parameter: `popLast()`, `remove(at:)` and `Optional.take()` with `where return outlives self`, and `replace(&place, with:)` with `where return outlives place`. A value `p` owns can view `p`'s own storage only by making `p` depend on a part of itself, and then `&p` conflicts with that dependency, so the call can't be made: what it returns depends only on what `p` carried, with the same kinds. So a worklist over a `List<MutableSpan<Float>>` works: in `while var s = work.popLast() { let p = partition(&s); let (low, high) = (consume s).split(at: p); work.append(low); work.append(high) }`, `work` stays free while `s` holds its buffer. The consuming `split(at:)` hands the halves over with what `s` carried, where the lending `s.split(at: p)` would tie them to `s` ([04](04-types.md#shared-mutable-and-consuming-forms-of-one-method)).

#### Naming a field

A value may carry borrows of several places while a result comes from one of them. So an item may name a path of a parameter's stored fields and tuple elements, and a subject may be followed by one: `return.name`, `return.0`, or `q.table` for a `mutable` parameter `q`, which then takes on what the item names in that field only:

```swift
struct Query(
    var name: StringView,                        // borrows the request text
    var table: Span<Entry>,                      // borrows the symbol table
): Scoped

func lookup(_ q: Query) -> Borrow<Entry>?
    where return outlives q.table                // an entry of the table, never of the request

func makeQuery(_ text: StringView, _ t: Span<Entry>) -> Query
    where return.name borrows text, return.table borrows t

var request = readRequest()
let e = lookup(Query(name: request.view, table: symbols.span))
request = readRequest()                          // fine: 'e' borrows symbols, not the request
use(e)
```

- **The caller keeps a set per stored field** of a struct, and per element of a tuple, down through nested stored fields, and a value's own set is their union. A primary initializer gives each field its argument's set, and assigning a stored field replaces its set, where the place assigned is known (rule 4). A call result gets per-field sets only from `return.f` items; other fields get what a plain `return` item names, or what the default rules give the whole result. Elements, enum payloads, what a `Box` holds, and a value of a type parameter have a single set.
- **A `mutable` argument's fields may trade what they carry**, as in a `mutating` method that swaps two fields. So after the call, each stored field of the argument, at every depth, has the union of all its fields' sets from before, plus what the call gives it. A field a `p.f` item names keeps its own set, plus what the items name, and the callee proves it took nothing from `p`'s other fields. So after `mutating func flip() { let t = copy a; a = copy b; b = t }` on a `Pair` built from `s1.view` and `s2.view`, both fields depend on `s1` and `s2`.
- **A path goes through stored fields only**, since an accessor is an access to all of `self` ([Which places overlap](01-values-and-ownership.md#which-places-overlap)). `borrows q.table` means that field and what it borrows; `outlives q.table` only what it borrows, under the conditions above applied to the field's type. The callee proves it with the same per-field sets for its own locals.

### Pointing a name at another place: `rebind`

A binding of a place is a name for that place, so `=` on it writes the place: after `var cur = &tree.root`, `cur = Node()` replaces the node in `tree.root`. A cursor walking down a structure moves the name itself with `rebind … to …`:

```swift
struct Node(var value: Int = 0, var children: List<Box<Node>> = [])

var cur = &tree.root
for i in path {
    guard i < cur.children.count else { break }
    rebind cur to &cur.children[i].value         // 'cur' now names that child; nothing is written
}
cur.children.append(Box(Node(value: 0)))
tree.root.value = 1                              // error if placed before the last use of 'cur'
```

`rebind x to p` makes the local `x` name the place `p` from then on, as if declared with it there. `x` is a local declared in the same function or closure body, not a parameter or a capture. `p` has `x`'s type, and is lent as `x`'s declaration lent its place: a changeable place marked `&` for a `var`, unmarked for a `let`, which still changes nothing. **`=` never rebinds**: `cur = &child` is a compile error; `rebind` does that. `&p` is a value only where it makes a view of a type of its own: a `mutable any P`, a function value made from a `mutating` closure, a `Closure<mutating …>` or a `mutating` function value ([05](05-protocols-generics-and-closures.md#implicit-conversions)), or the mutable form of a `get`, such as `&list.span` ([04](04-types.md#shared-mutable-and-consuming-forms-of-one-method)). Then `x = &p` writes that view into the place `x` names, as `d = &crate` does in a `for var d` loop, and `x` still names the same place.

- **A place reached through `x` keeps `x`'s set.** It lies inside the one `x` named, so the original borrow of `tree.root` lasts until `x`'s last use.
- **Any other place starts a new borrow.** `x`'s set becomes `p`'s, and the old place is free once nothing else depends on it.
- **Through objects, the cursor holds one mark.** A step through an object's owner or weak pointer, such as `rebind cur to &cur.children[i].value` with children held by `UniquePointer`s, takes the new object's access (rule 6), which **replaces** the previous object's access in `x`'s set, so the cursor holds a mark only on the object it stands on, however deep the walk. The previous access ends once nothing else depends on it. That is safe because the new place lies in another object's value, guarded by the new mark: if an alias removes the child from the previous object, destroying the object the cursor stands on panics ([03](03-handles-and-objects.md#destroying-an-object)), and any other alias reaching it still conflicts.
- **No target through an access-bound projection.** Each step would nest another suspended access ([below](#projections-read-and-modify-accessors)), so such a target is an error.
- **A binding that owns its value can be rebound.** The first `rebind` of one, such as `var cur = buildTree()` or `var lives = &particles.life`, hands the value to a hidden local of the binding's scope, destroyed at its end, and the value stays where it is, so views already taken from it stay valid and depend on that local, and a lock guard handed over this way stays locked until the scope ends. `x` then names a place, so it can't be consumed. When a path or a loop pass may skip the `rebind`, `x` can't be consumed after it on any path, and the hidden local is maybe-initialized ([01](01-values-and-ownership.md#places-that-hold-no-value)).

## Projections: `read` and `modify` accessors

An accessor that **yields** a place instead of returning a value is a **projection**:

```swift
struct Pool<T>(…) {
    subscript(h: Handle<T>) -> T? where yield borrows self {   // yields the pool's own storage (below)
        read   { if valid(h) { yield dense[slots[h.index].denseIndex] } else { yield nil } }
        modify { if valid(h) { yield &dense[slots[h.index].denseIndex] } else { yield nil } }
    }
}

world.enemies[h]?.hp -= 10                   // modify projection plus optional chaining
if var e = &world.enemies[h] { e.hp = 0 }
let pos = world.enemies[h]!.pos              // borrows through the read projection; '!' panics on a stale handle
```

A `read` accessor lends a place for reading and a `modify` accessor for changing. An accessor whose declared type is written `T?` is an **optional projection**, yielding either a place of type `T` or `nil`. One written `Optional<T>`, or with a type alias of an optional, yields a whole place of that enum type, such as a stored optional field, so `node.next = nil` and `node.next.take()` work through it. Only the `?` written in the declaration makes an optional projection.

**An optional projection, an optional chain, or a tuple of places, is a place only in its parts.** An optional projection's place is the `T` that `?.`, `!`, `x? = v`, `??`, a `let` or `var` condition or a pattern unwraps, and so is the place of an optional chain through a place, since `a?.b` names the `b` inside `a`'s payload and no `B?` lies in memory. A tuple of places, from `yield (&a, &b)` or `value[fields:]` ([09](09-compile-time.md#tuples-field-lists-and-queries)), is used element by element, as a pattern binds them. No such `T?` or tuple exists in memory, so none can be assigned as a whole, or lent with `&` or bound as a place except by a condition or pattern that unwraps or destructures it, or used as a `mutating` or `consuming` receiver such as `take()`, or passed as an argument other than a copy. An optional projection or chain may still be compared with `nil`, and, when `T` is copyable, copied wherever a copy is accepted ([01](01-values-and-ownership.md#parameters)), as in `let hp = copy target?.hp` and as `a ?? b` with an optional `b` needs, since it hands on `a` whole ([04](04-types.md#optionals)).

**A `read` or `modify` accessor yields exactly once on every path that returns normally**, which the compiler checks. So `yield` stands only in a `read` or `modify` body itself, never in a closure literal, a nested function, a local type's or extension's members or a `defer` block inside it, nor where a loop could run it again, and an optional projection yields `nil` on the paths that have no place to yield.

**Access-bound projections.** An accessor may yield a temporary: a value computed on the spot, a bitfield's bits read out of its bytes ([08](08-c-interop.md#structs-unions-and-enums)), or an under-aligned field copied to an aligned place ([04](04-types.md#packed-structs-and-under-aligned-places)). So by default a projection is **access-bound**: the accessor stays suspended at its `yield` until the last use of every value that depends on the access, as for a dynamic access (rule 6), and then runs the code after it, such as a `modify`'s write-back. Meanwhile the accessor keeps `self` and its subscript arguments lent as the access began them, shared for a `read` and exclusively for a `modify` or a `get` and `set` change, so what depends on the access depends on those places too, whatever the shallow rule, `outlives` or `copy` drops from its set. A view of it works like any view within the function, but can't leave it (rule 5).

**Storage projections.** An accessor declared **`where yield borrows self`** yields part of `self`'s storage, so a view of it depends on `self`, as a view of a stored field does, and can outlive the access. Any `yield` item makes a storage projection of what the item names:

```swift
struct Flags(var bits: UInt32) {
    var low: UInt16 { read { yield UInt16(truncating: bits) } }    // access-bound: yields a temporary
}
struct Inventory(var items: List<Item>) {
    subscript(i: Int) -> Item where yield borrows self { read { yield items[i] } modify { yield &items[i] } }
}
func firstName(_ inv: Inventory) -> StringView { inv[0].name.view }       // OK: a storage projection
```

- **The claim is verified.** Every `yield` must name a place reached through stored fields and other storage projections from what the item names (`self`, another parameter, or static storage), never a local, a temporary, a bitfield or an under-aligned field. A place reached through a raw pointer, such as a `List`'s buffer or a lock guard's protected value, can only be yielded from `unsafe` code, which promises that it lies in storage the named parameter owns or views, and that the code after the `yield` treats it as the next rule says.
- **The yield stays lent until the accessor returns.** A storage projection's access ends, and the code after its `yield` runs, when the call it is an argument of returns ([01](01-values-and-ownership.md#evaluation-order-and-when-a-calls-borrows-begin)), and otherwise at the end of the full statement that begins it ([above](#temporaries)). The access can end while a view of the yield lives on, so what runs after the `yield`, a `defer` block or a local's destruction included, treats the yielded place as still borrowed: it never changes it, and after a `modify` never reads it either. `modify { yield &items; items = List() }` is an error, and so is `modify { yield &items; spy.append(items[0].view) }`.
- **Projections of views.** On an exclusive view type, such as `MutableSpan` or `MutableRef`, a view of the yield depends on the view variable itself (rule 1): `func label(_ s: mutable MutableSpan<Item>, _ i: Int) -> StringView { s[i].name.view }` depends on `s`, and through it on what `s` views. On a view type that `outlives` accepts ([above](#staying-valid-after-a-parameter-moves-on-outlives)), `where yield outlives self` says the yield is reached through what the view carries.
- **Standard projections.** Collection and pool subscripts, `Box.value`, `MutableRef.value` and every lock guard's `.value` are `where yield borrows self`; the projections of `Span`, `StringView` and `Borrow` are `where yield outlives self`, and a `MutableSpan`'s element projections `where yield borrows self`. Properties that build a view, such as `span`, sub-span ranges and an `SoA` column, whose view depends on its column alone ([04](04-types.md#struct-of-arrays-soat)), are `get`s returning a view, not projections (rule 3). `Span`'s and `StringView`'s range `get`s, `first` and `last` are `where return outlives self`. The `.value` of a `UniquePointer` or a `WeakPointer` depends on its access (rule 6).
- **Protocols carry the clause.** A requirement `var pos: Vec3 { read modify }` is access-bound unless declared `var pos: Vec3 where yield borrows self { read modify }`, and a witness must satisfy it. A stored field witnesses either kind, except an under-aligned field or an imported bitfield, which goes through a temporary and so witnesses only an access-bound requirement, and subject to [05](05-protocols-generics-and-closures.md#conformances)'s rules on `let`, hidden, static, `unsafe` and union-member fields. An optional projection meets one only when the requirement's own declared type is written as an optional, `U?`, so that generic code treats it as an optional projection too, never when an associated type or a type parameter turns out to be an optional, or when the requirement is written `Optional<U>`, which asks for a whole place. A projection that yields a tuple of places meets none. So generic code can return a view of a requirement's yield only from a storage projection.

### `get` and `set` accessors

```swift
struct Angle(var radians: Float) {
    var degrees: Float {
        get { radians * 180 / .pi }
        set { radians = newValue * .pi / 180 }
    }
}
var a = Angle(radians: 0)
a.degrees = 90                               // calls set
a.degrees += 45                              // calls get, then set with the sum
```

A computed property or subscript may return a value from a `get`, as a body with no accessor keyword does, and take one in a `set`, which receives the assigned value as an `owned` parameter named `newValue`. A declaration's accessors are a `get`, a `get` and a `set`, a `read`, or a `read` and a `modify`.

- **Assignment calls `set`.** So does a compound assignment, since `a ⊕= b` is `a = a ⊕ b` ([05](05-protocols-generics-and-closures.md#operators)). Any other change, such as binding `var d = &a.degrees`, passing it as a `mutable` argument or calling a `mutating` method on it, calls `get`, lends the result, and calls `set` with it once the access ends, so it is access-bound, as a `modify` that yields a temporary is. That `set` call is checked as if written there, so the change is an error when the `get`'s result may depend on `self` or on a `mutable` argument of the access, which `set` changes while its `newValue` still views it.
- **Both calls take the subscript's arguments.** They are worked out once, when a compound assignment or another change calls `get` and then `set`: a borrowed or `mutable` argument is lent to each in turn, and a copyable `owned` one is copied for the `get`. So such an access is a compile error when an `owned` parameter's type is move-only, since one value can't move into two calls.
- **Requirements.** A `get`, yielding its result as a temporary, meets an access-bound `{ read }` requirement, and a `get` and a `set` meet an access-bound `{ read modify }` one when the `get`'s result can't depend on `self` or on a `mutable` parameter and no `owned` parameter's type is move-only, so that the pair of calls is always valid. A `{ get }` requirement is met by a `get`, and `{ get set }` by a `get` and a `set`. When the value's type is copyable, a stored field that [05](05-protocols-generics-and-closures.md#conformances) allows, or a storage projection, also meets them, and so do an access-bound `read`, for `{ get }`, and an access-bound `read` and `modify`, for `{ get set }`, when the type is also unscoped, the `read`'s yield copied as the `get` and the `modify` serving as the `set`; a scoped yield's copy would carry an access that ends inside the witness, which rule 5 rejects. An optional projection, or one that yields a tuple of places, meets `{ get }` but never `{ get set }`, since it has no whole value that a `set` could write ([above](#projections-read-and-modify-accessors)).

