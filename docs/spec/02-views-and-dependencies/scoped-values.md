# Scoped values

[02 · Views and dependencies](../02-views-and-dependencies.md)

A **view** is a value that borrows memory something else owns, so code can read or change data where it lies, without copying it:

```swift
let text: StringView = source.view            // borrows source's characters: no copy
let body: Span<Vertex> = mesh.vertices.span   // borrows the list's elements, read-only
var hot = &heat.span                          // a MutableSpan<Float>: borrows them mutably
```

**A view of memory that can be freed must stay within the scope that lent it.** Inside that scope, the compiler sees every borrow, and rejects freeing the memory while the view lives ([Dependencies](dependency-rules.md#dependencies)). A type whose values must stay there conforms to the marker protocol **`Scoped`**, and any value of such a type is a **scoped value**. Among them are these, each of which reaches memory it doesn't own:

- **Views of elements and values:** `Span<T>`, `MutableSpan<T>`, `StringView`, `Borrow<T>` and `MutableRef<T>`;
- **Iterators** of collections, spans and strings, which borrow what they walk;
- **Lock guards**, which point into their lock ([Lock guards are released on the thread that took them](dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them));
- **Existential views**, `any P` and `mutable any P`, which view a value of some type that conforms to `P` ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch));
- **Function values**, which view a closure's storage ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)), and **closure literals** that capture by reference or hold a scoped capture ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closures-by-concrete-type-some-f)).

**An iterator that borrows nothing is unscoped**, such as a `Range`'s. So a task may `await` inside `for i in 0..<n`: a scoped value can't live across an `await` ([below](#where-a-scoped-value-can-go)), but this loop's iterator isn't one.

**A view needn't be scoped when nothing can free its memory while it reads it.** A `StaticSpan<T>` is unscoped, since it views immortal data ([09](../09-compile-time/attributes-and-runtime-data.md#staticspan-views-of-immortal-data)). So is a `Slice<T>`, which reads its buffer only through a scoped span it hands out for each use ([06](../06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers)). Any other view of memory that can be freed is scoped.

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
- **Raw pointers.** A field or payload of raw pointer type `*T` counts as scoped when `T` is, so that the type says what it holds, since rules 3 and 4 read only types ([Shallow values](dependency-rules/projection-and-results.md#shallow-values)).

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

**A value of such a type follows the dependency rules as if it were scoped**, since generic code is checked once for every type it may stand for. So rule 5 applies when it is returned or stored ([Rule 5: The callee side](dependency-rules/absorption-and-accesses.md#rule-5-the-callee-side)).

**Code that must let a `T` outlive its scope requires `T: ~Scoped`**, which every unscoped type satisfies. `Mutex.lock` constrains its result this way:

```swift
extension Mutex {
    func lock<R: ~Scoped>(_ body: consuming (mutable T) -> R) -> R   // R can't be a view of the data
}
```

The closure can compute any unscoped result from the protected data. It can't smuggle out a view of the data as its result, which would be scoped, or through its captures, since its parameter isn't declared `keep` ([05](../05-protocols-generics-and-closures/functions-and-closures.md#what-a-closure-may-keep-keep)).

**`~Scoped` is required implicitly in these places, where a value can outlive the function that stores it, or be reached without its borrows:**

- globals, `@threadlocal var`s included;
- objects' values;
- a leaked `Box`'s value, which a `RawAllocation` holds with no borrows ([06](../06-memory-and-allocators/owning-values.md#owning-boxes));
- unscoped closures' captures;
- the contents of every `Synchronized` generic, such as `Mutex<T>` or a queue, whose methods take a shared `self`, so absorption (rule 4, [Rule 4: Absorption](dependency-rules/absorption-and-accesses.md#rule-4-absorption)) can't track what goes in ([07](../07-concurrency/synchronization.md#the-synchronized-contract));
- the concrete type in every conversion to an unscoped existential (`Box<any P>`, and each object pointer, reference-counted pointer and weak link to `any P`), since erasure would hide what the value borrows;
- task parameters and a `task func` method's `self`, which a task keeps in its state ([07](../07-concurrency/tasks.md#semantics));
- the elements of a `StaticSpan`, which outlive every scope ([09](../09-compile-time/attributes-and-runtime-data.md#staticspan-views-of-immortal-data)).

**In a type, `~` means "not", and comes only before `Copyable`, `Sendable` and `Scoped`** ([01](../01-values-and-ownership/moves-copies-destruction.md#copyable-types)).

- In a conformance list, `~Copyable` and `~Sendable` opt a type out of a derived conformance ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)).
- In a constraint, `T: ~Scoped` requires that `T` isn't scoped.

**An unconstrained type parameter may be move-only, scoped and not `Sendable`, so none of those needs a `~`.**
