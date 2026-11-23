# Scoped values

[02 · Views and dependencies](../02-views-and-dependencies.md)

A **view** is a value that borrows memory something else owns, so code can read or change data where it lies, without copying it. A reference is the plainest one ([01](../01-values-and-ownership/references.md#references)):

```swift
let text: &Text = source                      // refers to source's text: no copy
let body = &mesh.vertices.span                // a '&[Vertex]': refers to the list's elements, read-only
var hot = mutable &heat.span                  // a 'mutable &[Float]': refers to them for change
```

**A view of memory that can be freed must stay within the scope that lent it.** Inside that scope, the compiler sees every borrow, and rejects freeing the memory while the view lives ([Dependencies](../02-views-and-dependencies.md#dependencies)). A type whose values must stay there conforms to the marker protocol **`Scoped`**, and any value of such a type is a **scoped value**. Among them are these, each of which reaches memory it doesn't own:

- **References**, `&T` and `mutable &T`, among them the references to unsized types `&[T]`, `&Text` and `&any P` ([01](../01-values-and-ownership/references.md#references));
- **Iterators** of collections and strings, which borrow what they walk;
- **Lock guards**, which point into their lock ([Lock guards are released on the thread that took them](dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them));
- **Function values**, which view a closure's storage ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)), and **closure literals** that capture by reference or hold a scoped capture ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closures-by-concrete-type-some-f)).

**An iterator that borrows nothing is unscoped**, such as a `Range`'s. So a task may `await` inside `for i in 0..<n`: a scoped value can't live across an `await` ([below](#where-a-scoped-value-can-go)), but this loop's iterator isn't one.

**A view needn't be scoped when nothing can free its memory while it reads it.** A static value, such as a `static &Text`, is unscoped, since it views only data that lives as long as the program ([below](#static-values)). So is a `Slice<T>`, which reads its buffer only through a scoped reference it hands out for each use ([06](../06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers)). Any other view of memory that can be freed is scoped.

**Making a view from a raw pointer requires `unsafe`.** Safe code gets views only from what owns the memory, since a view built from a raw pointer carries no dependencies for the compiler to verify ([Precise dependencies (opt-in)](dependency-lifetimes.md#precise-dependencies-opt-in)).

**A type may be scoped without borrowing anything**, such as a profiling zone. It then can't be kept in a global or an unscoped type, or across an `await` ([below](#where-a-scoped-value-can-go)).

**A view that holds a mutable borrow is move-only**, since two copies would be two ways to change the same place at once. A mutable reference, a lock guard and a `mutating` function value are all move-only ([01](../01-values-and-ownership/moves-copies-destruction.md#types-that-are-always-move-only)).

## Writing through a view

**Writing through a view changes what it views, so it needs the view in a changeable place**, as any change does ([01](../01-values-and-ownership/bindings.md#changeable-places)). Through a reference, the write also needs a mutable one ([01](../01-values-and-ownership/references.md#forwarding-through-a-reference)). So a `let` can't write through a view it holds, and a loop name that owns a view can:

```swift
var hot = mutable &heat.span                            // a 'mutable &[Float]' that a var holds
hot[0] = 0                                              // fine: writes heat[0] through the reference
let cold = mutable &chill.span
cold[0] = 0                                             // error: writing through a view needs a changeable place; declare 'var cold'
for chunk in data.mutableChunks(64) { scale(mutable &chunk) }   // fine: the loop owns each chunk, and lends 'scale' a reborrow of it
for d in &targets { d.takeDamage(1) }                   // error: 'd' names each 'mutable &any Damageable' read-only; write 'mutable &targets'
```

`mutable &chunk` above is a reborrow, so `chunk` is usable again once `scale` returns ([01](../01-values-and-ownership/references.md#reborrowing)).

**A reference's members are those of what it refers to**, which it forwards ([01](../01-values-and-ownership/references.md#forwarding-through-a-reference)). So what a member does through it follows from how the member is declared, as with `[T]`'s members through a `mutable &[T]`:

```swift
var some = mutable &hits[0..<8]                 // a 'mutable &[Int]' that a var holds
print("\(some.count) hits")                     // a plain member: reads what 'some' refers to
some.sort()                                     // a 'mutating' member: writes through 'some'
some = mutable &some[1...]                      // points 'some' at part of what it refers to
let (low, high) = some.consumingSplit(at: 4)    // takes 'some', and hands over its halves
```

- **A plain member reads what the view refers to**, as `count` does.
- **A `mutating` member, a `mutate` accessor included, writes through the view**, and needs the view in a changeable place, as every `mutating` member's receiver does. A `mutate` hands out a place only in what the view refers to ([Place and value properties](place-and-value-properties.md#the-place-lies-in-its-sources)).
- **A view covers other elements only as a new value.** An assignment points a `var` at a part of what it referred to ([Assigning a reference to a `var`](dependency-lifetimes.md#assigning-a-reference-to-a-var)), and `consumingSplit(at:)` takes a `mutable &[T]` and hands over two references to its halves ([01](../01-values-and-ownership/references.md#forwarding-through-a-reference)). Either way, nothing still uses the view that covered the old elements.

## Where a scoped value can go

**A scoped value can live in locals, parameters, and the fields, elements, payloads and captures of other scoped values.** It can't be stored in an unscoped type, or anywhere else that requires `~Scoped` ([below](#generic-code-and-scoped)), such as a global. A value in any of those can outlive the function that stores it, or be reached without its borrows.

**A scoped value can't live across an `await` either** ([07](../07-concurrency/tasks.md#semantics)), since a task's owner may move or destroy the task's state between steps.

## Which types are scoped

**A type with a scoped field or payload is scoped**, since a scoped value can't be stored in an unscoped type ([above](#where-a-scoped-value-can-go)). So a struct or enum that holds a reference is scoped. The rule applies to each kind of type this way:

- **Declared types.** A struct, enum or union with a field or payload whose type is scoped where the type is declared must be declared `Scoped`.
- **Generic types.** A generic type is scoped when a stored field or payload is, once its type arguments are substituted, its associated types resolved and its `static if` and `static for` members generated. This is checked as `Sendable` is ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)).
- **Raw pointers.** A field or payload of raw pointer type `*T` counts as scoped when `T` is, so that the type says what it holds, since rules 3 and 4 read only types ([Shallow values](dependency-projection-and-results.md#shallow-values)).

So `List<&Text>`, `Map<&Text, Int>`, `(&[T])?` and `(&Text, Int)` are scoped, though the collections among them still own their heap memory. `Handle<Token>` and `Type<&Text>` aren't, since neither holds what its argument names. A generic type may be scoped in some instances without being declared `Scoped`:

```swift
struct Cursor<C: Collection>(var it: C.Iterator)   // needn't be declared Scoped
let c: Cursor<List<Int>>                           // scoped, since a list's iterator is
```

**The generic types that erase a type are the exceptions, and are unscoped.** Their argument names the kind of value they erased, not a view of it, and that value is always unscoped. These are:

- `Box<any P>`;
- the object pointers, reference-counted pointers and weak links to `any P` ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch));
- `Closure<F>` ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)).

## Generic code and `~Scoped`

**An unconstrained type parameter may be scoped**, and so may a type that depends on one, such as:

- an associated type, such as `C.Iterator`;
- a type whose members a `static if` or `static for` generates from a generic parameter, type or value.

**A value of such a type follows the dependency rules as if it were scoped**, since generic code is checked once for every type it may stand for. So rule 5 applies when it is returned or stored ([Rule 5: The callee side](dependency-absorption-and-accesses.md#rule-5-the-callee-side)).

**Code that must let a `T` outlive its scope requires `T: ~Scoped`**, which every unscoped type satisfies. `Mutex.lock` constrains its result this way:

```swift
extension Mutex {
    func lock<R: ~Scoped>(_ body: consuming (mutable &T) -> R) -> R   // R can't be a view of the data
}
```

The closure can compute any unscoped result from the protected data. It can't smuggle out a view of the data as its result, which would be scoped, or through its captures, since nothing a closure stores into its captures may depend on its parameters ([05](../05-protocols-generics-and-closures/functions-and-closures.md#what-a-closure-may-keep-from-its-parameters)).

**`~Scoped` is required implicitly in these places, where a value can outlive the function that stores it, or be reached without its borrows:**

- globals, `@threadlocal var`s included, so a global whose type would be scoped takes its static type ([below](#static-values));
- objects' values;
- a leaked `Box`'s value, which a `RawAllocation` holds with no borrows ([06](../06-memory-and-allocators/owning-values.md#owning-boxes));
- unscoped closures' captures;
- the contents of every `Synchronized` generic, such as `Mutex<T>` or a queue, whose methods take a shared `self`, so absorption ([Rule 4: Absorption](dependency-absorption-and-accesses.md#rule-4-absorption)) can't track what goes in ([07](../07-concurrency/synchronization.md#the-synchronized-contract));
- the concrete type in every conversion to an unscoped existential (`Box<any P>`, and each object pointer, reference-counted pointer and weak link to `any P`), since erasure would hide what the value borrows;
- task parameters and a `task func` method's `self`, which a task keeps in its state ([07](../07-concurrency/tasks.md#semantics)).

**A static type meets `~Scoped`**, so a static value can go in each of these places, as a `Mutex<static Token>` or a `Box<any P>` of a `static Token` can.

**In a type, `~` means "not", and comes only before `Copyable`, `Sendable` and `Scoped`** ([01](../01-values-and-ownership/moves-copies-destruction.md#copyable-types)).

- In a conformance list, `~Copyable` and `~Sendable` opt a type out of a derived conformance ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)).
- In a constraint, `T: ~Scoped` requires that `T` isn't scoped.

**An unconstrained type parameter may be move-only, scoped and not `Sendable`, so none of those needs a `~`.**

## Static values

```swift
protocol Logger: Sendable { func write(_ line: &Text) }
enum TokenKind { case kIf, kElse }
struct Token(let kind: TokenKind, let text: &Text): Scoped

let keywords: [2 of Token] = [Token(kind: .kIf, text: "if"), Token(kind: .kElse, text: "else")]   // a global: [2 of static Token]
struct Hint(let text: static &Text, let delay: Float)         // a plain struct can store a static view

let fileLog = FileLogger(path: "game.log")                    // a global let of a Logger, with a Mutex inside
struct AudioLog(let log: static &any Logger)                  // a reference to a logger that lives as long as the program
let audioLog = AudioLog(log: fileLog)

func show(_ hint: &Hint, _ token: &Token) {
    let shown: &Text = hint.text                              // fine: a static value converts to its plain type
    let kept: static &Text = token.text                       // error: 'token' is borrowed, so its text may be freed
}
```

**A static value views only data that lives as long as the program, so it is unscoped, where a value of its plain type is scoped.** That data is static storage, which no code moves or destroys ([Rule 5: The callee side](dependency-absorption-and-accesses.md#rule-5-the-callee-side)), or immortal data. **Immortal data** is memory that is never freed, and that nothing writes once a value names it, such as the program image or the runtime's tables. The qualifier `static` marks a static value in its type: `static T` is the **static type** of `T`, a `T` whose every view views such data. A static value of a view type, such as a `static &Text`, is a **static view**.

**`static` qualifies a scoped type whose scoped parts are all shared views:**

- a shared reference, such as `&T`, `&[T]`, `&Text` or `&any P`;
- a type whose scoped fields, payloads and elements all take `static`, a field of raw pointer type `*U` counting as one of type `U`, as `Token`, `[2 of Token]`, `(&Text, Int)` and `List<&Text>` do.

**No other type takes `static`**, since its point is to stay in its scope or to change what it views. That rules out these, and any type that holds one:

- an exclusive view, such as `mutable &T`, `mutable &[T]` or `mutable &any P` ([Mutable views](dependency-projection-and-results.md#mutable-views));
- a lock guard ([Lock guards are released on the thread that took them](dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them));
- a function value or closure literal;
- a type declared `Scoped` with no scoped field, such as a profiling zone.

**`static` on a concrete unscoped type is a compile error**, as `static Int` is, since it would change nothing.

**A type parameter takes no `static`**, since generic code is checked once, at its definition, and the parameter may stand for a type that can't take it ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#checking-generic-code)). Generic code that keeps a value requires `T: ~Scoped` instead, which a static type meets, so the caller writes `static` in the argument, as `Mutex<static Token>` does. An associated type, or a type that depends on a parameter, takes none either.

### What a static type is

**A static type is a type of its own, with its plain type's layout.** It differs from its plain type in what its views may view:

- **Parts.** A static value's fields, elements and payloads are static too, and so is a reference to any place reached through it, since each views the same data. So `keywords[0]` is a `static Token`, `keywords[0].text` a `static &Text`, and `&keywords[1].text[0..<2]` a static view. A `var` field of a static value takes only a static value.
- **What it refers to and its type arguments.** On a reference or a generic type, `static` applies to the scoped type it refers to or takes as an argument too, and leaves an unscoped one as it is. So `static List<&Text>` is the same type as `List<static &Text>`, a `static &[Token]` refers to `static Token`s, and a `static &[Preset]` to plain `Preset`s. A type argument that may be scoped or not, such as a type parameter or an associated type not constrained `~Scoped`, is a compile error there.
- **Members.** A static value has its plain type's members, which it is lent to as its plain type, shared, so `keywords[0].text.count` works. A `mutating` member can be called on it only when every scoped field and payload of its type has a type argument's type, a raw pointer to one counting as one, as `List`'s, `Optional`'s and an inline array's do. Then the member is the static instance's own, and takes static values, as `List<static &Text>.append` does. Any other `mutating` member could store a view of shorter-lived data in it, so calling one is a compile error.
- **Conformances.** It conforms to its plain type's protocols through that type's witnesses, so a `Set<static Token>` hashes as `Token` does. It is copyable, implicitly copyable, `Sendable` and `TrivialFree` exactly when its plain type is, and `Frozen` when what it views is (below).
- **Reflection.** It reads as its plain type, with the same fields, cases and layout, except that each scoped field's and payload's type is its static type. So `field.type` and `value[field]` give a `static &Text` for a `static Token`'s `text`, and `T.construct` takes static values. Its `T.name` puts `static` before its plain type's name, and its `T.id` is its own ([09](../09-compile-time/reflection.md#what-reflection-can-read)).

### Converting to and from a static type

**A static value converts to its plain type wherever that is expected** ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)). A copyable one is read and a move-only one taken, as `consume` takes it ([01](../01-values-and-ownership/bindings.md#conversions)), and a place of one is lent as its plain type, shared. No conversion applies through `mutable &`, so a static value is never lent to a `mutable &` parameter of its plain type, which could store a view of shorter-lived data in it. A static value depends on nothing, so it meets `where return borrows static` ([Precise dependencies (opt-in)](dependency-lifetimes.md#precise-dependencies-opt-in)).

**A value converts to its static type where it depends only on static storage and immortal data**, read or taken as above ([Dependencies](../02-views-and-dependencies.md#dependencies)). What a lock guard lends depends on the place that holds the guard, which no global can be, since a guard takes no `static`, so it never converts ([Lock guards are released on the thread that took them](dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them)). So these convert wherever a static type is expected:

- a literal, which views the program image, such as a string literal's `static &Text` ([04](../04-types/collections.md#literals));
- a value built only from static and unscoped values, such as `keywords[0]` above;
- a reference to a global `let` or a `const`, such as `&fileLog` above, a `&FileLogger` that converts to a `&any Logger` and then to its static type ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions));
- a view that a `Synchronized` value in a global lends for the rest of the program, such as `Once.get()`'s ([07](../07-concurrency/synchronization.md#snapshots-one-time-values-and-waits));
- the result of a function declared `where return borrows static`.

**A value that depends on anything else never converts**, since what it views may be freed or locked: a borrowed parameter, a local, a global `var`, a thread-local, or a view lent through a lock guard.

**Besides these conversions, only the runtime makes static values**, such as a `Name`'s text and the names and lists that reflection and `typeInfo` give ([09](../09-compile-time/reflection.md#what-reflection-can-read)). `unsafe` code that makes one, and C that passes one to Rayo, promise that its data lives as long as the program ([08](../08-c-interop/c-contract-and-embedding.md#what-c-must-uphold)).

### Static globals and `Frozen`

**A global whose type would be scoped has its static type, with nothing written.** That covers a global `let`, `var` or `@threadlocal var`, a `const`, and a type's static stored property ([07](../07-concurrency/global-state.md#global-state)). So `keywords` above is a `[2 of static Token]`, and its initializer converts to it. A global whose type can't take `static`, such as a `mutable &[T]`, is a compile error.

**A static type is `Frozen` when what it views is.** The language declares the conformance ([06](../06-memory-and-allocators/owning-values.md#frozen-types-with-no-interior-mutability)):

- a `static &Text` is always `Frozen`, since the text it views is never written: a literal's bytes, interned text, or a `String` in a global `let` or a `const`;
- a `static &U` or `static &[U]` is `Frozen` when `U` is;
- a `static &any P` is `Frozen` when `P` refines `Frozen`;
- any other static type is `Frozen` when each of its fields, taken as static, is.

So `static &any Logger` above isn't `Frozen`, since `Logger` doesn't refine `Frozen`. It can be a global `let`'s or a field's type, but a `const` can't hold one ([09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)).
