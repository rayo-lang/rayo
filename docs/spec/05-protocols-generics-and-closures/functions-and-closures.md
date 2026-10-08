# Functions and closures

[05 · Protocols, generics and closures](../05-protocols-generics-and-closures.md)

A **closure** is a value of a closure literal's concrete type ([below](#closures-by-concrete-type-some-f)). Passed for a function-type parameter, it becomes a view of itself, which may borrow locals and never allocates. The function type says whether the closure only reads what it captures, writes it, or consumes it:

```swift
func each(_ xs: Span<Enemy>, _ body: (Enemy) -> Void) { for x in xs { body(x) } }
func eachMut(_ xs: Span<Enemy>, _ body: mutating (Enemy) -> Void) { for x in xs { body(x) } }

var dead = 0
each(enemies.span) { e in log("hp \(e.hp)") }                // reads only: a plain function type
eachMut(enemies.span) { e in if e.hp <= 0 { dead += 1 } }    // writes 'dead': a mutating function type
each(enemies.span) { e in if e.hp <= 0 { dead += 1 } }       // error: a mutating closure where a non-mutating one is expected
```

**Functions may share a name when their argument labels or parameter types differ.** A type's methods and properties may also share one when only their `self` convention differs ([04](../04-types/collections.md#shared-mutable-and-consuming-forms-of-one-method)). A call picks among such overloads in these steps:

1. It keeps the candidates whose parameters its arguments match by label, in order. A parameter that has a default may be left out ([01](../01-values-and-ownership/parameters.md#default-arguments)).
2. It keeps those that its arguments typed without context fit. Each such argument is of its parameter's type, or converts to it implicitly ([Implicit conversions](implicit-conversions.md#implicit-conversions)).
3. Each argument that needs context, such as a literal, a closure literal or a `.member`, takes each remaining candidate's parameter type. A candidate it doesn't fit drops out.
4. If exactly one candidate needs no conversion, it wins. Among several candidates that need no conversion, the one that alone declares no type parameters of its own wins, as below. Otherwise exactly one candidate must remain, or the call is ambiguous.

```swift
func f(_ x: Int) { … }      // wins for an Int argument: it alone declares no type parameters
func f<T>(_ x: T) { … }     // needs no conversion either, but declares T
```

**These steps resolve each call on its own, without backtracking**, so type checking stays local ([11](../11-compilation-model.md#type-checking-is-local)).

**A call `T(x)` with one unlabeled literal argument makes the literal a `T`**, as `x as T` does, so `Float(0)` is the `Float` zero.

**The language makes calls the code doesn't write, and the rules for calls apply to each.** Each one's callee is known statically. So the checks on calls cover them, such as the `@noalloc` check ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)) and the check that a global's initializer reads no global before it is initialized ([07](../07-concurrency/global-state.md#initialization-at-startup)). They are:

- a `deinit` that a scope's end, an overwrite or a `consume` runs;
- an accessor or an operator;
- a `@converts` or literal initializer;
- an expression pattern's `==`, or a range pattern's `contains`;
- a parameter's or field's default;
- the calls that build an interpolated string;
- a `for` loop's calls to `makeIterator` or `makeMutableIterator`, and to the iterator's `next`;
- an `await`'s calls to its operand's `poll` ([07](../07-concurrency/tasks.md#awaitables)).

**A function declared without `->` returns `Void`.** The exception is a non-public function whose body is a single expression: it returns that expression's type, unless it is `main`, `@c`, `@export`, a `task func` or a protocol witness. A public function is never an exception, since other modules are checked against its declaration, never its body ([11](../11-compilation-model.md#type-checking-is-local)).

**Every path returns.** A body that is a single expression returns its value, unless the result type is `Void`, where the value is discarded. Otherwise, in a function, closure, `get` or `task` body whose result type isn't `Void`, every path ends in a `return` with a value, a `throw` or a call that never returns ([04](../04-types/enums.md#enums)). A function whose result type is `Never` has no `return`, and no path reaches its end. A `while true` loop that no `break` leaves never completes, so no path continues past it.

**A closure literal's body is a function body of its own.** `return` and `throw` leave the closure, `break` and `continue` target only loops inside it, and `await` can't appear in it, even in a `task func`, since a closure is called, not stepped ([07](../07-concurrency/tasks.md#semantics)).

**A closure's parameter types come from a written parameter clause or the expected type**, never from the body, since inference is local ([11](../11-compilation-model.md#type-checking-is-local)). The grammar gives the syntax of trailing closures, `$0` and `{ x in … }` ([12](../12-grammar/constructs.md#expressions)).

**Only closure literals capture.** These declarations inside a body name none of the body's locals, parameters or `self`:

- a nested function;
- a member, accessor, initializer, `deinit` or field default of a local type;
- a member of a local extension.

## Capturing places

**A closure captures places, not variables.** It captures as precisely as its body names them: a body that reads `world.players` borrows that field, not `world`. So a closure reading one field can be passed alongside an exclusive borrow of another, and two closures in one call may each write a different field.

**The captured place is the longest path the body names through parts kept apart from their siblings** ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)). Those parts are:

- stored fields;
- reflection projections of a field known where the borrows are checked;
- inline array elements at an index known where the borrows are checked.

**The path stops before the steps the body evaluates on each call:**

- any other accessor, subscript or index;
- an optional chain, a force unwrap or a payload;
- an object's access.

**The path also stops before an under-aligned place**, so the closure captures the aligned place that holds it, since no view of an under-aligned place may exist ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)). A bitfield is captured through its C memory location, since the bitfields of one memory location are one place for exclusivity ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)).

**A body that names a borrowing binding captures the place the binding names**, as worked out when it was bound. The capture brings the binding's dependency set and the dynamic accesses the binding holds, which stay held while the closure lives.

## Closure kinds

A closure's type says what it does with its captures, and the compiler infers this kind from the literal's body:

| Kind | Function type | The closure's body |
| --- | --- | --- |
| Non-`mutating` | `(Int) -> Void` | Only reads its captures |
| `mutating` | `mutating (Int) -> Void` | Writes a capture |
| `consuming` | `consuming () -> Mesh` | Moves out of a capture |

- **Non-`mutating`.** Its function types accept only closures that only read their captures, shared-borrowed or owned. So a job system may run one on many threads at once ([07](../07-concurrency/thread-work.md#lending-work-to-other-threads)), and a `sort(by:)` comparator can't write the pool it reads.
- **`mutating`.** A literal captures a place **exclusively** when its body makes any mutable access to it:
    - assigning it;
    - lending it with `&`, wherever `&` may appear ([01](../01-values-and-ownership/bindings.md#lending-a-place-for-change));
    - calling a `mutating` method on it;
    - capturing it exclusively in a nested literal.

  A `mutating` function value is move-only, and calling it mutates the closure itself. So it is passed `mutable` or owned, and runs on one thread at a time.
- **`consuming`.** A literal whose body moves out of a capture owns that capture. The body moves out with `consume input`, or by taking the capture anywhere a value is taken ([01](../01-values-and-ownership/moves-copies-destruction.md#moves)). The capture moves in when the closure is created, as `[move input]` would. Calling the closure consumes it, so the compiler checks it is called at most once. Copying a capture with `copy` doesn't make it `consuming`.

  A literal checked against a `consuming` function type, or a `some F` whose `F` is one, is `consuming` whatever its body does. Its concrete type satisfies only `consuming` function types, and it is called at most once.

**A closure that writes a capture is `mutating`, so a parallel loop rejects it:**

```swift
var n = 0
particles.forEachInParallel { _ in n += 1 }   // error: writes 'n', so it is mutating, but the loop runs it on many threads
```

**A parameter of `mutating` or `consuming` function type, or of `some F` where `F` is one, is received owned** unless declared `mutable`, since a borrowed one could never be called ([01](../01-values-and-ownership/parameters.md#parameters)). How a closure gets there depends on the parameter's type:

- **A closure passed for a function-type parameter is converted first** ([below](#function-typed-values)). So a local holding a `mutating` closure is passed with `&`, and stays usable after the call. A local holding a `consuming` closure is passed without `&`, and the conversion consumes it.
- **A local passed for a `some F` parameter whose `F` is `mutating` or `consuming` moves in**, unless the parameter is `mutable`.

**So `Mutex`'s `lock` needs no `owned`**, and a function value passed there moves in:

```swift
func lock<R: ~Scoped>(_ body: consuming (mutable T) -> R) -> R { … }   // Mutex<T>'s: 'body' is received owned
```

**The kinds nest.** A non-`mutating` value is accepted where a `mutating` or `consuming` one is expected, and a `mutating` one where a `consuming` one is. That holds for values only, never through `mutable` ([Implicit conversions](implicit-conversions.md#implicit-conversions)), and it never adds ownership ([below](#function-typed-values)).

## What a closure may keep: `keep`

A closure can't keep what it is lent for one call, such as the data behind a lock, unless the parameter is declared `keep`:

```swift
m.lock { d in kept = d.items.span }               // error: 'd' is lent only for the call
forEachLine(src.view) { lines.append(copy $0) }   // fine: forEachLine's closure takes a 'keep' parameter
let names = entries.map { $0.name.view }          // fine: the closure returns a view of its parameter, and keeps none
```

**Closure parameters are call-scoped.** Nothing that depends on one may be stored into the closure's captures, by rule 5 ([02](../02-views-and-dependencies/dependency-rules/absorption-and-accesses.md#rule-5-the-callee-side)) for a closure body. A call absorbs nothing into the captures, by rule 4 ([02](../02-views-and-dependencies/dependency-rules/absorption-and-accesses.md#rule-4-absorption)). A closure may still return what depends on a parameter, as the `map` above does. The call's result and `mutable` arguments still depend on what the closure captures, since the closure is the call's `self`.

**`keep` on a parameter of a function type lets the closure store what it derives from that parameter into its captures**, as `forEachLine`'s closure may:

```swift
func forEachLine(_ text: StringView, _ body: mutating (keep StringView) -> Void) { … }   // 'body' may keep the lines
```

**`keep` marks a borrowed or `owned` parameter.** A `mutable` parameter is the caller's place, and `keep` on it is a compile error.

**A call absorbs the `keep` argument's dependency set, with the kinds of rule 3, into every place the closure depends on exclusively** ([02](../02-views-and-dependencies/dependency-rules/projection-and-results.md#rule-3-call-results)). So `lines` above ends up depending on `src`, and the calling function must be allowed that store by its own rule 5.

- **A borrowed `keep` parameter lends only what it carries.** Its own storage belongs to the call, as a local's does. So the closure never keeps a view of the parameter itself, its bytes or what it owns. A call absorbs only the argument's dependency set, never the argument place, which lets the caller pass a local or a temporary. So a closure that keeps views of a list's elements takes `keep Span<T>`. One that keeps an `any P` view of the parameter, by appending it to a captured list, is rejected.
- **A `keep owned` parameter gives the closure its value too**, which it may move into its captures with what that value carries. So a closure may append its `keep owned MutableSpan<Float>` parameter to a captured list: a move-only view that no borrowed parameter could give up.
- **`keep` never changes what a callee receives.** It receives what the same parameter without `keep` would ([01](../01-values-and-ownership/parameters.md#parameters)), also when a conversion adds it.
- **`keep` is part of the type.** A closure type without it is accepted where one with it is expected, not the reverse, since a plain closure's receiver relies on nothing flowing into its captures.

## Unscoped closures: `Closure<F>`

A callback stored in a struct, or a thread's body, outlives the call that made it, so it owns its captures instead of borrowing:

```swift
struct Hotkey(var action: Closure<() -> Void>)

let id = 7
var ping = Hotkey(action: { [copy id] in log("pressed \(id)") })   // 'id' is copied in, and stays usable here
var level = Box(Level())
var load = Hotkey(action: { [move level] in start(level.value) })  // 'level' is moved in: it can't be used after this
var oops = Hotkey(action: { log("pressed \(id)") })                // error: 'id' isn't listed
```

**`Closure<F>`**, such as `Closure<mutating (Int) -> Int>`, is an unscoped, move-only value that owns every capture. It is `Sendable` only when its function type is `@sendable`, such as `Closure<mutating @sendable (Int) -> Int>` ([below](#function-typed-values)).

- **Captures are listed.** Each is `[move x]`, or `[copy x]` for a copyable value, which leaves `x` usable. `self` is listed too, and only a `consuming` method can move it. An unlisted capture is a compile error. A capture the body moves out of is already owned ([above](#closure-kinds)) and needs no entry. A global is never a capture of any closure: the body reaches it as any function does ([07](../07-concurrency/global-state.md#global-state)).
- **Size.** A `Closure` is 32 bytes, and holds up to 24 bytes of captures inline. The captures are laid out as a struct, as a literal's are ([below](#closures-by-concrete-type-some-f)). They are inline when all of these hold:
    - the captures' struct is at most 24 bytes;
    - its alignment is at most 8;
    - no capture has a layout the language or a library leaves open, such as a task's state, a `Pin<T>` or a value that holds one ([11](../11-compilation-model.md#what-the-language-leaves-open)).

  Otherwise the captures go in an out-of-line context that the closure owns, from the current allocator ([06](../06-memory-and-allocators/allocator-basics.md#the-current-allocator)). The capture list shows at the literal what moves in, and so whether it fits. In `@noalloc` code, a conversion into a `Closure` that allocates is an error.
- **It counts as holding a `Synchronized` value.** Its inline captures may hold one, unseen in its type. So a borrowed `Closure` is always the caller's place ([01](../01-values-and-ownership/parameters.md#borrowed-arguments)), and a `@packed` struct can't hold one.
- **An out-of-line context is checked like any owning storage** ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)). Calling a `Closure` whose context outlived its allocator's memory, as when an arena was reset since the closure was made, panics. Destroying such a `Closure` skips its captures' `deinit`s and the free, as for a stale `Box`.
- **Calling.** A stored `Closure<mutating …>` needs `mutable` access to be called, and calling a `Closure<consuming …>` consumes it.

## Closures by concrete type: `some F`

A closure can also be held by its own concrete type, which never allocates:

```swift
func times(_ n: Int, _ body: some mutating () -> Void) { … }   // monomorphized for each literal: never boxed

var hits = 0
var misses = 0
var onHit = { hits += 1 }                           // no annotation: the literal's own concrete type
var onMiss: mutating () -> Void = { misses += 1 }   // annotated: the function type, a view of the literal
```

**Every closure literal has its own anonymous concrete type.** A local initialized with a literal and no type annotation has that type, so it only ever holds that literal; with an annotation it has the function type. The type is laid out as a struct whose fields are its captures ([04](../04-types/structs.md#structs)), declared in this order: the listed captures, in list order, then the others, by reference or moved, in order of first use. A capture by reference is a pointer.

- **A `some F` parameter**, for a function type `F` of any kind, is an anonymous type parameter `B: F`, and takes the literal by its concrete type. The callee is monomorphized for it, and the closure is stored by value, **never boxed or allocated, whatever its size**, like a struct whose fields are its captures. `until` takes its condition this way, so an awaiting task never allocates ([07](../07-concurrency/tasks.md#awaitables)).
- **Function-type constraints.** A type satisfies `B: F`, for a function type `F`, when it is a closure's concrete type, a function type or a `Closure<G>`, and its values convert to `F` ([Implicit conversions](implicit-conversions.md#implicit-conversions)), which the kinds decide ([above](#closure-kinds)). Generic code calls a `B` as an `F`, converts it to `F`, and, when `B: ~Scoped`, moves it into a `Closure<F>`.
- **The captures decide whether it is scoped.** A literal's type is scoped when any capture is by reference or of a scoped type, such as a `[copy s]` of a `Span`. It then depends on the places it captures by reference and on what its captures carry. It is unscoped only when every capture is owned and unscoped ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)).
- **The captures and the kind decide whether it is copyable.** It is copyable when every capture is by shared reference, or owned and copyable, and the literal isn't `consuming`, which is called at most once.
- **Where the type must be unscoped**, as for a parameter constrained `F: ~Scoped`, a literal owns and lists its captures, as for a `Closure`. Elsewhere it captures by reference, except what its capture list names or its body moves out of.

## C function pointers

```swift
@c func half(_ x: Int32) -> Int32 { x / 2 }
let f: @c (Int32) -> Int32 = half               // a named @c func converts
let g: @c (Int32) -> Int32 = { x in x + 1 }     // so does a literal that captures nothing and doesn't throw
unsafe { print(f(4)) }                          // calling one is unsafe
```

**`@c (Int32) -> Int32` is a C function pointer.** It has no room for captures, and it never throws, since C can't receive an error. Calling one is `unsafe`, since the type can't tell a Rayo function from a C one. These convert to it:

- a literal that captures nothing and doesn't throw;
- a named `@c func`, `@export`, imported or `extern c` function, or a `@c` value, when its parameters and result have the same types and conventions as the pointer type's, and it needs no more stack than the pointer type declares ([08](../08-c-interop/imports-and-inline-c.md#the-stack-a-c-call-needs)).

**Inside `unsafe`, a function also converts to a `@c` type whose types differ but have the same C representations** ([08](../08-c-interop/calling-rayo-from-c.md#c-representations)). So a `WeakPointer<Body>` parameter meets a `UInt64` one. A `mutable T` parameter also meets a `*T` or `*T?` one there, since both cross as `T*`:

```swift
enum PadButton: Int32 { case start, back }   // crosses as its raw type, Int32
@c func onButton(_ b: PadButton) { … }       // converts to @c (Int32) -> Void
@c func onUpdate(_ s: mutable State) { … }   // converts to @c (*State) -> Void: both cross as State*
```

**The `unsafe` code that makes such a conversion promises both of these:**

- every call through the pointer passes values valid for the function's own types, and a pointer for a `mutable` parameter meets what 08 asks of one ([08](../08-c-interop/c-contract-and-embedding.md#what-c-must-uphold));
- every value the function returns, or writes through a `mutable` parameter or a pointer, is valid for the pointer type's types, as 08 asks of C.

**`@c noalloc (Int32) -> Int32` is a C function pointer whose calls allocate nothing**, so `@noalloc` code may call one ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)). Only what allocates nothing converts to it:

- a named `@noalloc` function;
- an imported or `extern c` function declared `noalloc` ([08](../08-c-interop/imports-and-inline-c.md#c-calls-in-noalloc-code-noalloc));
- a literal whose body passes the `@noalloc` check;
- another `@c noalloc` value.

**Inside `unsafe`, a `@c` value without the mark converts too**, as a pointer C handed over does, and that code promises what `noalloc` asserts. The mark converts away, never back outside `unsafe`.

**`unsafe (UInt32) -> Void` is an unsafe function type**, whose calls need `unsafe`. Any Rayo function value converts to the `unsafe` form of its type, never back.

**An `unsafe func` declared in Rayo converts only to `unsafe` function types** and `Closure`s of them, and, when it is also `@c`, to `@c` types. So no function value hides its call from the caller. It satisfies a `some F` or a function-type constraint only when `F` is `unsafe`.

**C code stays behind `@c` types.** An imported or `extern c` function is an `unsafe func` too ([08](../08-c-interop/imports-and-inline-c.md#what-imports-as-what)), but converts only to `@c` types, which carry its stack need ([08](../08-c-interop/imports-and-inline-c.md#the-stack-a-c-call-needs)). A `@c` value converts only to another `@c` type, or its optional, as above. Neither converts to a Rayo function type, a `Closure` or an `unsafe` form, whose calls wouldn't check that need. A literal that calls C inside an `unsafe` block is an ordinary Rayo function:

```swift
let now: () -> Double = { unsafe { platform_time_seconds() } }   // a Rayo function type, though its body calls C
```

## Function-typed values

A function-typed value views its closure's storage, so it can't outlive that storage:

```swift
let put: (mutable List<StringView>) -> Void = { o in o.append(src.view) }    // the literal lives as long as 'put'
func pick() -> (Int, Int) -> Int { max }                                   // fine: a named function views no storage
func inc() -> (Int) -> Int { return { x in x + 1 } }                       // fine: nor does a literal that captures nothing
func sorted(by less: (Int, Int) -> Bool = { a, b in a < b }) { … }        // fine, as a default, for the same reason
func mk() -> () -> Int { let x = 5; return { [copy x] in copy x } }        // error: the result would view mk's temporary
```

**A value of function type is a view of a closure's storage**, where all its captures, owned ones included, live. Converting a closure to a function type makes such a view. A closure here is any value of a closure's concrete type, such as a literal, a local, parameter or field of a literal's anonymous type, or a `some F` parameter. The view depends on the storage and on what the closure carries ([02](../02-views-and-dependencies/dependency-rules/projection-and-results.md#closure-calls)). A non-`mutating` function value is a copyable shared view; a `mutating` or `consuming` one is move-only.

- **A non-`consuming` closure is borrowed as its kind needs.** A non-`mutating` one is borrowed shared, whatever the function type. A `mutating` one is borrowed exclusively, so the place holding it is lent with `&` ([01](../01-values-and-ownership/bindings.md#lending-a-place-for-change)), as in `run(&grow)`, and is usable again after the view's last use.
- **A `consuming` closure is handed over.** The conversion consumes the source place ([01](../01-values-and-ownership/moving-values-out.md#moving-values-out)), and the value takes over the captures but not their memory, so it still can't outlive that memory. Calling it moves out of the captures and destroys the rest; dropping it uncalled destroys them all.
- **Converting a function value never adds ownership.** A value accepted where a stronger kind is expected views the same storage the same way: called through a `consuming` type, a borrowed closure runs with the access it was lent, and dropping the value destroys nothing.
- **Named functions and operators are function values too.** A named function other than `ptr(to:)` ([10](../10-errors-and-safety/unsafe-code.md#taking-an-address)), a static method or an operator, such as `max` or the `+` in `combine: +`, converts to each of these, with parameter conventions lining up as a witness's do ([01](../01-values-and-ownership/parameters.md#parameters)):
    - `Closure<F>`, for a function type `F` its signature matches;
    - any function type its signature matches, of any kind;
    - if it doesn't throw, such a type throwing an error type that leaves the same arguments places ([Implicit conversions](implicit-conversions.md#implicit-conversions)).

  A named function views no storage and depends on nothing, which is why `pick` compiles. An overloaded name is resolved by the expected type. A closure literal that captures nothing converts the same way, since its storage holds nothing. So `inc` and the default of `sorted(by:)` above compile.
- **`@sendable` function types**, such as `@sendable (mutable Particle) -> Void`, hold only closures whose captures, by reference or owned, all have `Sendable` types, and their values are `Sendable` ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)). A named function always converts to one. A `@sendable` value converts to the same type without the mark, never the reverse, and `Closure<F>` and `some F` carry the mark the same way.
- **`@noalloc` function types**, such as `@noalloc (mutable MutableSpan<Float>) -> Void`, hold only functions whose calls can't allocate: a `@noalloc` named function, or a literal whose body passes the `@noalloc` check ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)). Where a call may destroy the literal's captures, the check covers that destruction too. A call may destroy them for a `consuming` literal, and for any literal moved into a `Closure` or passed owned for a `some F`, since a call through a `consuming` type destroys what it doesn't move out. A call through a `@noalloc` function type counts as a `@noalloc` call. The mark converts away as `@sendable` does, never the reverse, and `Closure<F>` and `some F` carry it the same way.

**A literal is kept in a hidden local when it is in one of these places, and the local there depends on its storage after the statement**, by rules 3 and 4 ([02](../02-views-and-dependencies/dependency-rules.md#dependencies)):

- a local's initializer;
- the right side of an assignment to a local, or to a path of stored fields from one.

Within either, the literal may be anywhere outside nested closure bodies:

- directly;
- as a call argument at any depth, such as to a primary initializer;
- as an element of a tuple or array literal;
- as an `if` or `when` arm's value.

**The hidden local belongs to the local's scope** ([01](../01-values-and-ownership/moves-copies-destruction.md#destruction)). So `put` above stays usable for its whole scope, and so does `h` here:

```swift
let h = Handler(onClick: { … })   // the literal is an argument in a local's initializer: kept in a hidden local
```

- **Each such literal gets its own hidden local**, which holds a value only if the literal was made.
- **Each hidden local is destroyed right after the local it was made for.** So the value holding the view is gone first, and what the literal captured, such as a guard on an earlier local's mutex, is released before that local is destroyed.
- **A literal assigned on every pass of a loop reuses its hidden local**, so a still-live copy of the previous value conflicts with the assignment.

**Any other literal is an owning temporary that lives to the end of its full statement** ([02](../02-views-and-dependencies/dependency-rules/projection-and-results.md#temporaries)). Examples are a `return` operand and an argument in another kind of statement. So `mk` fails, and so does appending a literal to a `List<() -> Int>` used after the statement.
