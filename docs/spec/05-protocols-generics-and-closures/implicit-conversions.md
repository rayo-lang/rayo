# Implicit conversions

[05 · Protocols, generics and closures](../05-protocols-generics-and-closures.md)

```swift
var target: Handle<Enemy>? = h                  // T to T?, taking h
let seen: any Drawable = sprite                 // a shared borrow of 'sprite' to an existential view
var w: Box<any Widget> = Box(Slider(…))         // Box<Slider> to Box<any Widget>: no new allocation
let pickMax: (Int, Int) -> Int = max            // a named function to a function type
```

**An implicit conversion makes a value of the type its context expects, with no conversion written.** Numbers widen along their fixed order ([04](../04-types/numbers-and-math.md#conversions)). Otherwise there are six kinds of implicit conversion, each decided by the expected type alone, so type checking stays local ([11](../11-compilation-model.md#type-checking-is-local)). All are free except two: moving a closure into a `Closure`, which may allocate, and an error's `@converts` initializer, which runs. The six are:

- **`T` → `T?`.** Where a `U?` is expected, a value that converts to `U` (below) converts and is then wrapped, in the same local step, as a named `@c func` passed for a nullable C callback is. It takes the value ([01](../01-values-and-ownership/bindings.md#conversions)).
- **Existentials** ([`any P`: explicit dynamic dispatch](protocols-and-generics.md#any-p-explicit-dynamic-dispatch)):
    - A shared borrow of a `T` that meets every protocol of the composition converts to `any P`, and an exclusive borrow `&x` to `mutable any P`. A place converts by a shared borrow wherever an `any P` is expected, as any view of it is made, with nothing written ([01](../01-values-and-ownership/bindings.md#conversions)).
    - `&v` of a changeable place holding a `mutable any P` makes a new view of the same value (below). A shared borrow of such a place gives a shared `any P` view of the same value, while the place stays borrowed shared.
    - An existential of `P` converts to one of `Q` when `P` implies `Q`, as `any Widget` does to `any Drawable` when `Widget` inherits `Drawable`, or `any P & Sendable` to `any P`. A view stays a view, and an unscoped existential keeps its allocation. From a place, a shared view makes a new view of the same value while the place stays borrowed shared, a `mutable any P` is taken or, with `&v`, lends a new view, and an unscoped existential is taken.
- **`Box<T>` → `Box<any P>`**, and likewise for each object pointer, reference-counted pointer and weak link, such as `WeakPointer<T>` → `WeakPointer<any P>` and `Shared<T>` → `Shared<any P>`. `T` must meet every protocol of the composition, as `T: Sendable` does for `any P & Sendable`, and `T: ~Scoped` must hold. The conversion takes the value, moving it out of a place as a declaration would ([01](../01-values-and-ownership/bindings.md#bindings)). `~Scoped` is what makes the conversion sound: the existential forgets `T` and any dependency `T` carries, so `T` must carry none ([02](../02-views-and-dependencies/scoped-values.md#generic-code-and-scoped)).
- **Closures to `Closure<F>`** ([Unscoped closures: `Closure<F>`](functions-and-closures.md#unscoped-closures-closuref)). A closure literal, an owned value of a closure's concrete type, or a named function or operator moves into a `Closure`, allocating when its captures exceed the inline size. A `Closure<F>` converts to a `Closure<G>` when a function value of type `F` converts to `G` (below), keeping its context.
- **Errors** ([10](../10-errors-and-safety/typed-errors.md#error-unions)). A value of an error union's member, or of a union whose members it all has, converts to that union, taking the value as `T` → `T?` does. Under `try` or `throw`, an error converts to the enclosing function's error type through a `@converts` initializer ([10](../10-errors-and-safety/typed-errors.md#propagating-errors-with-try)).
- **Closures to function types**, in the ways listed next.

**These convert to function types** ([Function-typed values](functions-and-closures.md#function-typed-values)):

- A closure, named function or operator converts to a function type.
- A `Closure<F>` place converts to the function type `F`, or to any function type a value of type `F` converts to (below). It is borrowed as `F`'s kind needs, as a closure is. Converting a `Closure<consuming …>` consumes it, but keeps its out-of-line context until the place is next assigned or its scope ends, whichever comes first. The context is then freed without destroying the captures, which the function value took.
- A literal that captures nothing and doesn't throw, a named `@c func`, `@export`, imported or `extern c` function, or a `@c` value converts to a `@c` function pointer type ([C function pointers](functions-and-closures.md#c-function-pointers)). The pointer type must have the same types, or inside `unsafe` the same C representations, and the same conventions, and must declare at least the converted function's stack need.
- A Rayo function value converts to each of these, with every parameter convention unchanged ([01](../01-values-and-ownership/parameters.md#parameters)), within the limits that C function pointers set for `unsafe` and C functions ([C function pointers](functions-and-closures.md#c-function-pointers)):
    - a stronger kind: non-`mutating` to `mutating` or `consuming`, and `mutating` to `consuming`;
    - for a non-throwing value, the same type throwing an error type that leaves the same borrowed arguments always the caller's place ([01](../01-values-and-ownership/parameters.md#borrowed-arguments)), as any unscoped one does;
    - a type whose parameters add `keep`;
    - the type without `@sendable` or `@noalloc`;
    - its `unsafe` form.

**`x as T` expects a `T`, as an annotation does.** So `x` takes one of the implicit conversions above or a numeric widening ([04](../04-types/numbers-and-math.md#conversions)), or, for a literal, becomes a `T` ([04](../04-types/collections.md#literals)). It never tests a type at run time. Anything else is explicit, such as `box.downcast(to: T.self)` ([`any P`: explicit dynamic dispatch](protocols-and-generics.md#any-p-explicit-dynamic-dispatch)).

**No conversion applies through `mutable`.** An `&` argument has exactly its parameter's type: no widening, no `T → T?`, no stronger closure kind and no added `keep`. Otherwise the callee could store, say, a `mutating` closure into a variable the caller still sees as a non-`mutating` one, which a job system may call on many threads.

**The exceptions make new views instead of converting a variable**, and each lends its place until the view's last use:

- `&x` → `mutable any P`;
- `&v`, for a changeable place `v` holding a `mutable any P` → a new view of the same value;
- `&f` → the function value of a `mutating` closure or `Closure<mutating …>` `f`;
- `&f`, for a changeable place `f` holding a `mutating` function value → a new view of the same closure.

**So a function that takes a `mutating` callback can pass it on twice**, lending a new view of it each time:

```swift
eachMut(a, &body)   // a new view of the callback 'body', lent to this call
eachMut(b, &body)   // and another, after the first view's last use
```
