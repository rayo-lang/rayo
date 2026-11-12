# Scoped values

[02 · Views and dependencies](../02-views-and-dependencies.md)

A **view** is a value that borrows memory something else owns, so code can read or change data where it lies, without copying it:

```swift
let text: StringView = source.view            // borrows source's characters: no copy
let body: Span<Vertex> = mesh.vertices.span   // borrows the list's elements, read-only
var hot = &heat.span                          // a MutableSpan<Float>: borrows them mutably
```

**A view of memory that can be freed must stay within the scope that lent it.** Inside that scope, the compiler sees every borrow, and rejects freeing the memory while the view lives ([Dependencies](../02-views-and-dependencies.md#dependencies)). A type whose values must stay there conforms to the marker protocol **`Scoped`**, and any value of such a type is a **scoped value**. Among them are these, each of which reaches memory it doesn't own:

- **Views of elements and values:** `Span<T>`, `MutableSpan<T>`, `StringView`, `Borrow<T>` and `MutableRef<T>`;
- **Iterators** of collections, spans and strings, which borrow what they walk;
- **Lock guards**, which point into their lock ([Lock guards are released on the thread that took them](dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them));
- **Existential views**, `any P` and `mutable any P`, which view a value of some type that conforms to `P` ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch));
- **Function values**, which view a closure's storage ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)), and **closure literals** that capture by reference or hold a scoped capture ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closures-by-concrete-type-some-f)).

**An iterator that borrows nothing is unscoped**, such as a `Range`'s. So a task may `await` inside `for i in 0..<n`: a scoped value can't live across an `await` ([below](#where-a-scoped-value-can-go)), but this loop's iterator isn't one.

**A view needn't be scoped when nothing can free its memory while it reads it.** A static value, such as a `static StringView`, is unscoped, since it views only data that lives as long as the program ([below](#static-values)). So is a `Slice<T>`, which reads its buffer only through a scoped span it hands out for each use ([06](../06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers)). Any other view of memory that can be freed is scoped.

**Making a view from a raw pointer requires `unsafe`.** Safe code gets views only from what owns the memory, since a view built from a raw pointer carries no dependencies for the compiler to verify ([Precise dependencies (opt-in)](dependency-lifetimes.md#precise-dependencies-opt-in)).

**A type may be scoped without borrowing anything**, such as a profiling zone. It then can't be kept in a global or an unscoped type, or across an `await` ([below](#where-a-scoped-value-can-go)).

**A view that holds a mutable borrow is also move-only, `~Copyable`**, since two copies would be two mutable aliases:

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

## Where a scoped value can go

**A scoped value can live in locals, parameters, and the fields, elements, payloads and captures of other scoped values.** It can't be stored in an unscoped type, or anywhere else that requires `~Scoped` ([below](#generic-code-and-scoped)), such as a global. A value in any of those can outlive the function that stores it, or be reached without its borrows.

**A scoped value can't live across an `await` either** ([07](../07-concurrency/tasks.md#semantics)), since a task's owner may move or destroy the task's state between steps.

## Which types are scoped

**A type with a scoped field or payload is scoped**, since a scoped value can't be stored in an unscoped type ([above](#where-a-scoped-value-can-go)). The rule applies to each kind of type this way:

- **Declared types.** A struct, enum or union with a field or payload whose type is scoped where the type is declared must be declared `Scoped`.
- **Generic types.** A generic type is scoped when a stored field or payload is, once its type arguments are substituted, its associated types resolved and its `static if` and `static for` members generated. This is checked as `Sendable` is ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)).
- **Raw pointers.** A field or payload of raw pointer type `*T` counts as scoped when `T` is, so that the type says what it holds, since rules 3 and 4 read only types ([Shallow values](dependency-projection-and-results.md#shallow-values)).

So `List<StringView>`, `Map<StringView, Int>`, `Optional<Span<T>>` and `(StringView, Int)` are scoped, though the collections among them still own their heap memory. `Handle<Token>` and `Type<StringView>` aren't, since neither holds what its argument names. A generic type may be scoped in some instances without being declared `Scoped`:

```swift
struct Cursor<C: Collection>(var it: C.Iterator)   // needn't be declared Scoped
let c: Cursor<List<Int>>                           // scoped, since a list's iterator is
```

**The generic types that erase a type are the exceptions, and are unscoped.** Their argument names the kind of value they erased, not a view of it, and that value is always unscoped. These are:

- `Box<any P>`;
- the object pointers, reference-counted pointers and weak links to `any P` ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch));
- `Closure<F>` ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)).

**Binding a type parameter to `any P` never makes an unscoped existential** ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)).

## Generic code and `~Scoped`

**An unconstrained type parameter may be scoped**, and so may a type that depends on one, such as:

- an associated type, such as `C.Iterator`;
- a type whose members a `static if` or `static for` generates from a generic parameter, type or value.

**A value of such a type follows the dependency rules as if it were scoped**, since generic code is checked once for every type it may stand for. So rule 5 applies when it is returned or stored ([Rule 5: The callee side](dependency-absorption-and-accesses.md#rule-5-the-callee-side)).

**Code that must let a `T` outlive its scope requires `T: ~Scoped`**, which every unscoped type satisfies. `Mutex.lock` constrains its result this way:

```swift
extension Mutex {
    func lock<R: ~Scoped>(_ body: consuming (mutable T) -> R) -> R   // R can't be a view of the data
}
```

The closure can compute any unscoped result from the protected data. It can't smuggle out a view of the data as its result, which would be scoped, or through its captures, since its parameter isn't declared `keep` ([05](../05-protocols-generics-and-closures/functions-and-closures.md#what-a-closure-may-keep-keep)).

**`~Scoped` is required implicitly in these places, where a value can outlive the function that stores it, or be reached without its borrows:**

- globals, `@threadlocal var`s included, so a global whose type would be scoped takes its static type ([below](#static-values));
- objects' values;
- a leaked `Box`'s value, which a `RawAllocation` holds with no borrows ([06](../06-memory-and-allocators/owning-values.md#owning-boxes));
- unscoped closures' captures;
- the contents of every `Synchronized` generic, such as `Mutex<T>` or a queue, whose methods take a shared `self`, so absorption (rule 4, [Rule 4: Absorption](dependency-absorption-and-accesses.md#rule-4-absorption)) can't track what goes in ([07](../07-concurrency/synchronization.md#the-synchronized-contract));
- the concrete type in every conversion to an unscoped existential (`Box<any P>`, and each object pointer, reference-counted pointer and weak link to `any P`), since erasure would hide what the value borrows;
- task parameters and a `task func` method's `self`, which a task keeps in its state ([07](../07-concurrency/tasks.md#semantics)).

**A static type meets `~Scoped`**, so a static value can go in each of these places, as a `Mutex<static Token>` or a `Box<any P>` of a `static Token` can.

**In a type, `~` means "not", and comes only before `Copyable`, `Sendable` and `Scoped`** ([01](../01-values-and-ownership/moves-copies-destruction.md#copyable-types)).

- In a conformance list, `~Copyable` and `~Sendable` opt a type out of a derived conformance ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)).
- In a constraint, `T: ~Scoped` requires that `T` isn't scoped.

**An unconstrained type parameter may be move-only, scoped and not `Sendable`, so none of those needs a `~`.**

## Static values

```swift
protocol Logger: Sendable { func write(_ line: StringView) }
enum TokenKind { case kIf, kElse }
struct Token(let kind: TokenKind, let text: StringView): Scoped

let keywords: [2 of Token] = [Token(kind: .kIf, text: "if"), Token(kind: .kElse, text: "else")]   // a global: [2 of static Token]
struct Hint(let text: static StringView, let delay: Float)    // a plain struct can store a static view

let fileLog = FileLogger(path: "game.log")                    // a global let of a Logger, with a Mutex inside
struct Telemetry(let log: static any Logger)                  // a view of a logger that lives as long as the program
let telemetry = Telemetry(log: fileLog)

func show(_ hint: Hint, _ token: Token) {
    let shown: StringView = hint.text                         // fine: a static value converts to its plain type
    let kept: static StringView = token.text                  // error: 'token' is borrowed, so its text may be freed
}
```

**A static value views only data that lives as long as the program, so unlike a value of its plain type it is unscoped.** That data is static storage, which no code moves or destroys ([Rule 5: The callee side](dependency-absorption-and-accesses.md#rule-5-the-callee-side)), or immortal data. **Immortal data** is memory that is never freed, and that nothing writes once a value names it, such as the program image or the runtime's tables. The qualifier `static` marks a static value in its type: `static T` is the **static type** of `T`, a `T` whose every view views such data. A static value of a view type, such as a `static StringView`, is a **static view**.

**`static` qualifies a scoped type whose scoped parts are all shared views:**

- the shared views `StringView`, `Span<T>`, `Borrow<T>` and `any P`;
- a type whose scoped fields, payloads and elements all take `static`, a field of raw pointer type `*U` counting as one of type `U`, as `Token`, `[2 of Token]`, `(StringView, Int)` and `List<StringView>` do.

**No other type takes `static`**, since its point is to stay in its scope or to change what it views. That rules out these, and any type that holds one:

- an exclusive view, such as `MutableSpan<T>`, `MutableRef<T>` or `mutable any P`;
- a lock guard ([Lock guards are released on the thread that took them](dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them));
- a function value or closure literal;
- a type declared `Scoped` with no scoped field, such as a profiling zone.

**`static` on a concrete unscoped type is a compile error**, as `static Int` is, since it would change nothing.

**A type parameter takes no `static`**, since generic code is checked once, at its definition, and the parameter may stand for a type that can't take it ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#checking-generic-code)). Generic code that keeps a value requires `T: ~Scoped` instead, which a static type meets, so the caller writes `static` in the argument, as `Mutex<static Token>` does. An associated type, or a type that depends on a parameter, takes none either.

### What a static type is

**A static type is a type of its own, with its plain type's layout.** It differs from its plain type in what its views may view:

- **Parts.** A static value's fields, elements, payloads and ranges are static too, since they view the same data. So `keywords[0]` is a `static Token`, `keywords[0].text` a `static StringView`, and `keywords[1].text[0..<2]` a static view. A `var` field of a static value takes only a static value.
- **Type arguments.** On a generic type, `static` applies to the type arguments too. So `static List<StringView>` is the same type as `List<static StringView>`, whose own methods, such as `append`, take and give static values, and a `static Span<Token>` views `static Token`s.
- **Members.** A static value has its plain type's members, which it is lent to as its plain type, shared, so `keywords[0].text.count` works. A `mutating` member of a type that isn't generic can't be called on it, since that member could store a view of shorter-lived data in it.
- **Conformances.** It conforms to its plain type's protocols through that type's witnesses, so a `Set<static Token>` hashes as `Token` does. It is copyable, `Sendable` and `TrivialFree` exactly when its plain type is, and `Frozen` when what it views is (below).
- **Reflection.** It reads as its plain type, with the same fields, cases and layout. Its `T.name` puts `static` before its plain type's name, and its `T.id` is its own ([09](../09-compile-time/reflection.md#what-reflection-can-read)).

### Converting to and from a static type

**A static value converts to its plain type wherever that is expected** ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)). A copyable one is read and a move-only one taken, as a declaration takes a value ([01](../01-values-and-ownership/bindings.md#conversions)), and a place of one is lent as its plain type, shared. No conversion applies through `mutable`, so a static value is never lent to a `mutable` parameter of its plain type. A static value depends on nothing, so it meets `where return borrows static` ([Precise dependencies (opt-in)](dependency-lifetimes.md#precise-dependencies-opt-in)).

**A value converts to its static type where it depends only on static storage and immortal data**, and on no lock guard or view lent under a lock, read or taken as above ([Dependencies](../02-views-and-dependencies.md#dependencies)). So these convert wherever a static type is expected:

- a literal, which views the program image ([04](../04-types/collections.md#literals));
- a value built only from static and unscoped values, such as `keywords[0]` above;
- a view of a global `let` or a `const`, such as the `any Logger` view of `fileLog` above, made as any `any P` view is and then converted ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions));
- a view that a `Synchronized` value in a global lends for the rest of the program, such as `Once.get()`'s ([07](../07-concurrency/synchronization.md#snapshots-one-time-values-and-waits));
- the result of a function declared `where return borrows static`.

**A value that depends on anything else never converts**, since what it views may be freed or locked: a borrowed parameter, a local, a global `var`, a thread-local, or a view lent through a lock guard.

**Besides these conversions, only the runtime makes static values**, such as a `Name`'s text and the names and lists that reflection and `typeInfo` give ([09](../09-compile-time/reflection.md#what-reflection-can-read)). `unsafe` code that makes one, and C that passes one to Rayo, promise that its data lives as long as the program ([08](../08-c-interop/c-contract-and-embedding.md#what-c-must-uphold)).

### Static globals and `Frozen`

**A global whose type would be scoped has its static type, with nothing written.** That covers a global `let`, `var` or `@threadlocal var`, a `const`, and a type's static stored property ([07](../07-concurrency/global-state.md#global-state)). So `keywords` above is a `[2 of static Token]`, and its initializer converts to it. A global whose type can't take `static`, such as a `MutableSpan`, is a compile error.

**A static type is `Frozen` when what it views is.** The language declares the conformance ([06](../06-memory-and-allocators/owning-values.md#frozen-types-with-no-interior-mutability)):

- a `static StringView` is always `Frozen`, since the text it views is never written: a literal's bytes, interned text, or a `String` in a global `let` or a `const`;
- a static `Span<U>` or `Borrow<U>` is `Frozen` when `U` is;
- a static `any P` is `Frozen` when `P` refines `Frozen`;
- any other static type is `Frozen` when each of its fields, taken as static, is.

So `static any Logger` above isn't `Frozen`, since `Logger` doesn't refine `Frozen`. It can be a global `let`'s or a field's type, but a `const` can't hold one ([09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)).
