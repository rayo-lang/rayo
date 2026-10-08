# Projection, transitivity and call results

[02 · Views and dependencies](../02-views-and-dependencies.md#dependencies)

## Rule 1: Projection

**A view taken from a place depends on that place**, since the view reaches only that place's storage and what the place owns. It depends shared for a read projection, such as `pool[h]` or `list[i]`, and exclusively for a `modify` projection ([Projections: `read` and `modify` accessors](projections-and-accessors.md#projections-read-and-modify-accessors)). A view that a `get` builds, such as `list.span` or `s[a..<b]`, depends on the place by rule 3, since a `get` returns a value instead of yielding a place ([below](#rule-3-call-results)).

**What a view taken from a place depends on follows from what it is taken through:** a shared view, a place that owns its value or an exclusive view, or an access-bound projection.

**Through a shared view, the place drops out where declared.** A `get` declared `where return outlives self`, or a projection declared `where yield outlives self`, gives a sub-view that is a narrower copy of the shared view ([Staying valid after a parameter moves on: `outlives`](dependency-lifetimes.md#staying-valid-after-a-parameter-moves-on-outlives)). So the sub-view depends only on what the view carries, not on the variable holding it. The compiler verifies the two facts that make this safe: nothing the view carries can be changed through it, or end with it ([Staying valid after a parameter moves on: `outlives`](dependency-lifetimes.md#staying-valid-after-a-parameter-moves-on-outlives)).

```swift
let b = rest.first                       // in a span iterator: 'b' depends on what 'rest' views
rest = rest[1...]                        // fine while 'b' is live: 'b' doesn't depend on 'rest'
let t = Token(text: src[start..<pos])    // in a lexer: depends on the text, not on the lexer's field
```

**Verification rejects an `outlives` clause for a view of data the type holds inline**, such as a `[4 of Int]` field, which depends on `self` itself.

**Through a place that owns its value, or an exclusive view, projections depend on the place itself.** An exclusive view can change what it carries, so it never meets the condition that lets the place drop out ([Staying valid after a parameter moves on: `outlives`](dependency-lifetimes.md#staying-valid-after-a-parameter-moves-on-outlives)).

**Through an access-bound projection, a view depends on the access.** An access-bound projection, one with no `yield` item in its `where` clause, may yield a temporary ([Access-bound projections](projections-and-accessors.md#access-bound-projections)). So a view of it depends on the **access**, which is held as rule 6 holds a dynamic access. The held access keeps the accessor suspended, so its frame stays as it was until the view's last use. The access is in the yielded value's own set, so it follows every value derived from it, even where the place drops out. It also keeps the places the accessor was given lent.

## Rule 2: Transitivity

**A value derived from a scoped value inherits that value's dependency set.** It reaches nothing its source can't, so the source's set covers it. A copy or a sub-view inherits the set whole. A stored field or tuple element inherits that field's set, where the caller keeps one ([Naming a field](dependency-lifetimes.md#naming-a-field)).

## Rule 3: Call results

**A scoped result depends on what the call was given.** Rule 3 tells the caller what a result borrows from the callee's signature, except for a local closure literal, whose body the caller sees ([below](#closure-calls)). A callee may return only what its caller lent it, by rule 5 ([Rule 5: The callee side](dependency-absorption-and-accesses.md#rule-5-the-callee-side)), so by default the result depends on all of that:

- on every borrowed or `mutable` argument, `self` included: both **the argument place and its dependency set**;
- on the sets of scoped `owned` arguments.

**An `owned` argument contributes only its set**, since its own storage belongs to the callee, which can't return a view of it (rule 5).

**A `mutable` argument's place is held exclusively, and a borrowed one's shared.** Each set keeps its own kinds, so a view taken through a borrowed `MutableSpan` still holds what the span holds exclusively.

**A thrown error is a result too**: what a `catch` binds depends on the arguments the same way.

### Closure calls

**Calling a closure is a call whose `self` is the closure**, so rule 3 applies to it as to a method. `self` is borrowed for a non-`mutating` closure, `mutable` for a `mutating` one and `owned` for a `consuming` one ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds)). A closure never lends out its owned captures (rule 5), so the result depends on the closure's dependency set: what it captures by reference, and what its owned captures carry.

```swift
let get = { src.view }
let v = get()                    // 'v' depends on 'src'
```

**Only a value whose type can hold a function value can depend on a closure's storage.** A function-typed argument depends on its closure's storage, as well as on what the closure carries ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)). No call of a closure returns anything depending on its own storage (rule 5), and nothing else sees into it. So only a value holding the function value can reach the storage.

**The storage a function-typed argument views is a dependency of the call's result, or of an absorbing argument (rule 4), unless that value's type is sealed.** A **sealed** type is a concrete type in which nothing is one of these, at any depth of fields, elements, payloads and type arguments:

- a function type, or a closure's concrete type;
- an interpolated literal's type ([04](../04-types/collections.md#strings));
- a `some P` or an `any P`, owned or a view;
- a type parameter or an associated type.

Every other type is **unsealed**. Each item above is a closure or a function value, may stand for one, or is a way to view a shallow value's own bytes ([below](#shallow-values)). So no value of a sealed type can reach a closure's storage, or a shallow argument's own bytes.

**What the closure carries always flows.** So this compiles:

```swift
func names(_ t: Span<Token>) -> List<StringView> {
    t.map { copy $0.text }       // the list depends on what 't' views, not on the literal
}
```

**A place captured exclusively ties the result to the closure**, since besides the result, only the closure reaches that place, and its next call may change or free it. Take a call that doesn't consume the closure, and returns a result depending on a place the closure captures exclusively: the place itself, not what it carries. The result then also depends, exclusively, on the function value and the storage it views, whatever the result's type, as a `mutating` method's result depends on `self`. So the next call conflicts while the result lives. The exemption for sealed types never removes this tie.

```swift
var grow = { () -> Span<Int> in buf.append(0); return buf.span }
let a = grow()
grow()                           // error: 'grow' is borrowed by 'a' (used below)
use(a)

var nextLine = { reader.readLine() }   // the same: each line it returns ties up 'nextLine'
```

**The tie also binds a call that is passed a `mutating` closure, or a new view of one, without consuming the closure itself.** Its result and absorbing arguments depend, exclusively, on that closure's storage whenever they may depend on a place the closure captures exclusively:

```swift
func once(_ f: consuming () -> Span<Int>) -> Span<Int>

let b = once(&grow)              // consumes a new view of 'grow', not 'grow' itself
grow()                           // error: 'grow' is borrowed by 'b' (used below)
use(b)
```

**The tie follows what the caller can see:**

- **A local closure literal.** A local with no type annotation, initialized with a closure literal, has the literal's own anonymous type ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closures-by-concrete-type-some-f)) and never holds another closure. So for a call on it, the compiler knows what the result depends on, and ties it only when that is an exclusively captured place. A tokenizer closure that advances a captured `pos` and returns views of a shared `src` hands out tokens that outlive the next call.
- **Everywhere else, the body is out of sight**, as in a local declared with a function type, a closure parameter, a stored or generic closure, a `some F`, or an element of a list of closures. There the tie applies to every call of a `mutating` function value, since it may carry an exclusive dependency.

So a function that takes a `mutating` closure can't hold one call's scoped result across a second call:

```swift
func twice(_ f: mutable (mutating () -> Span<Int>)) {
    let a = f()
    f()                          // error: 'f' is borrowed by 'a' (used below)
    use(a)
}
```

### Shallow values

**The shallow rule below spares a sealed result, or a sealed absorbing argument, from keeping a shallow argument's place borrowed**, since it can't reach the argument's own bytes. This lets a call take a temporary view, such as `source.view`, and leave a result or an absorbing argument that is used after the statement. Otherwise that value would depend on a temporary that dies with the statement ([below](#temporaries)).

A copyable type that holds no inline array, at any depth, is **shallow**, scoped or not. A shallow value owns no heap memory, since no copyable type does ([01](../01-values-and-ownership/moves-copies-destruction.md#copyable-types)), and holds no elements it could lend. Shallow types include plain values and shared views:

- `Int`, a `Range` and `Vec3`;
- a `Simd` vector, whose lanes are never viewed ([04](../04-types/numbers-and-math.md#simd-and-math));
- `Span`, `StringView` and [`Borrow<T>`](../04-types/collections.md#iteration);
- a shared `any P`, and a non-`mutating` function value;
- a `Token` of a `StringView` and an `Int`;
- tuples and `Optional`s of those.

**When a result or an absorbing argument has a sealed type, a shallow argument contributes only its dependency set**, not the argument place. Safe code can view a shallow value's own bytes only through one of these:

- an `any P` made from it;
- a closure capturing it by reference;
- an interpolated literal borrowing it.

**Only an unsealed type can hold any of these**, so a sealed result can't reach the argument's place.

**The rule holds whatever the argument's convention, and whether it is a variable, a parameter or a temporary.** To such a result, an unscoped shallow argument contributes nothing. For example:

```swift
splitLines(source.view, into: &lines)   // leaves only 'source' borrowed
let r = grid.row(y + 1)                 // depends on 'grid' alone
parts.append(data[0..<n])               // makes a List<Span<Float>> depend on 'data' alone

func nearest(_ es: Span<Enemy>, to p: Vec3) -> Borrow<Enemy>? {
    es.min(by: { … })                   // returns what 'es' views
}
```

**A value that holds an inline array, such as a matrix of four `Vec4` columns, can lend its elements.** So a result keeps depending on the argument place, as every result of an unsealed type does.

**A function value received `owned` absorbs, at the call, only what a call of it can store through its `keep` parameters** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#what-a-closure-may-keep-keep)). So its type counts as sealed there when every `keep` parameter's type is. The same holds for a closure of concrete type received `owned` through a `some F` parameter, or through a type parameter constrained to a function type. So this leaves only `src` borrowed:

```swift
forEachLine(src.view) { line in lines.append(copy line) }
```

**A function value or a closure passed `mutable` stays unsealed**, since the callee may replace it with another closure.

**In generic code, a type is shallow only if it is for every type argument its constraints allow**, since generic code is checked once for every type it may stand for. `Span<T>` is. `T`, `T?`, `(T, Int)`, an associated type, and a struct whose fields a `static if` or `static for` generates aren't.

**Two kinds of `unsafe` code make promises these rules rely on:**

- **Code that views a shallow value's bytes with `ptr(to:)`** promises never to return or store that view where a sealed type holds it.
- **Code that keeps a value through a raw pointer**, reading it after the call that gave it the value returns, promises that the holding type says what it holds, since rules 3 and 4 read only types. The type must be scoped if the value is, as a field `*T` makes it for a `T`. It must be unsealed if the value is, or may be, a closure, a function value or an `any P`, as a type parameter, an associated type or a `some P` may be.

**Code that keeps a value through a raw pointer also promises what it hands out of that storage.** What it later hands out borrows nothing that the handing-out call's dependencies don't give it, by the dependency rules and its `where` items. That covers a result, a yield, and a store through a `mutable` parameter. So storage that one value absorbs into and another hands out of, such as a channel's two ends, holds only unscoped values ([07](../07-concurrency/synchronization.md#queues-and-channels)).

### Mutable views

**Mutable views need an exclusive input.** Otherwise a function could turn a shared borrow into a `MutableSpan`, which would write what another shared borrow still reads. A **mutable view** is a value through which what it views can be changed:

- a `MutableSpan`, a `MutableRef` or a `mutable any P`;
- a lock guard;
- a `mutating` or `consuming` function value, or a closure with an exclusive capture;
- a value holding one of these.

**A scoped value that only holds shared views is no mutable view**, as `List<StringView>` isn't. Neither is a function value made from a named function, or from a literal that captures nothing, since it views no storage.

**A function that returns a mutable view must take a `mutable` argument or an `owned` mutable view.** A borrowed `MutableSpan` doesn't qualify, since a second view could then write what the first still reads. An `unsafe` function is exempt (next).

```swift
func rest<T>(_ s: owned MutableSpan<T>) -> MutableSpan<T>   // fine: takes an owned mutable view
func peek<T>(_ s: MutableSpan<T>) -> MutableSpan<T>         // error: 's' is only borrowed
```

**`unsafe` code that builds a mutable view answers for it**, since the signature's shape isn't enough: the code can take a dummy `mutable` argument. This covers a `MutableSpan`, a `MutableRef`, and a type of the code's own, declared `~Copyable`, that changes what it views through a raw pointer. The code promises that everything the view can change lies in a `mutable` argument's place, or in storage that place owns, or is reached through an exclusive dependency that an argument passed `mutable` or `owned` carries. It promises too that none of it is reached only through a borrowed argument or what one carries.

**In an `unsafe` function, that promise is its caller's**: that nothing else reaches what the view can change while it lives ([10](../10-errors-and-safety/unsafe-code.md#raw-accesses)). `S.trailing(at:count:)` is one such function ([08](../08-c-interop/imports-and-inline-c.md#what-imports-as-what)).

**Two kinds of mutable view may come from a shared input, since their exclusivity is enforced at run time:**

- **A value that depends on an exclusive dynamic access its call begins** (rule 6), as the span a `Slice`'s `lock()` returns does ([06](../06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers)).
- **A value of a guard type** ([Lock guards are released on the thread that took them](dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them)), whose exclusivity its `Synchronized` type enforces. A `Synchronized` method may return one from a shared `self`, as `Mutex.lock()` does, and any function may pass one on.

```swift
func lockRegistry(_ s: Services) -> MutexGuard<Registry> { s.registry.lock() }   // a guard from a shared 's'
```

### Temporaries

**An argument that isn't a place is a temporary**, like `makeArray()` in `first(makeArray())`. An `owned` parameter takes it over, so only its set flows.

**A temporary passed borrowed or `mutable`, `self` included, lives to the end of its full statement**, and a value depending on it can't outlive that:

```swift
let x = first(makeArray())      // an error if 'x' is used later
```

A **full statement** is a statement, except that each of these is a full statement of its own:

- a condition of an `if`, `guard`, `while` or `repeat … while`;
- a `when` subject;
- the condition of each arm of a `when` without a subject;
- a `where` guard of a `when` arm or a `catch`.

So the temporaries of each of these die before the body runs, unless a value subject is kept in a hidden local ([01](../01-values-and-ownership/bindings.md#conditions-and-patterns)). That makes this an error too:

```swift
if let x = first(makeArray()) { use(x) }   // error: the array dies before the body runs
```

**A scoped temporary gets no exemption**, since it may hold data inline that a borrowed callee lends out. Only its set flows in two cases:

- when it is shallow, and the result or absorbing argument is sealed ([above](#shallow-values));
- when the callee's `where` clause says the result, or what it yields, `outlives` the parameter it is passed for ([Precise dependencies (opt-in)](dependency-lifetimes.md#precise-dependencies-opt-in)), as a `where return outlives self` `get` or a `where yield outlives self` projection does.

So these leave only `arr` and `src` borrowed:

```swift
let m = arr.span.min(by: …)     // only 'arr' stays borrowed
let w = src.view[a..<b]         // only 'src' stays borrowed
```

**An unscoped shallow temporary contributes nothing.**

**Two kinds of temporary can be kept in hidden locals instead:**

- a `for` loop's sequence expression keeps its temporaries in hidden mutable locals until the loop ends;
- a closure literal can be kept in a hidden local of a local's scope ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)).
