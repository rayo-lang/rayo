# Implicit conversions

[05 · Protocols, generics and closures](../05-protocols-generics-and-closures.md)

Most changes of type are written out, especially when they may lose information. A small set of conversions can instead follow from the type a context expects. The compiler performs those without a conversion expression, while preserving the ownership and borrowing rules of the value being converted.

```rayo
var target: Handle<Enemy>? = h                  // T to T?: a Handle is implicitly copyable, so 'h' is copied in
let top: &Enemy = enemies[0]                    // a place to a shared reference to it
let seen: &any Drawable = sprite                // 'sprite' is lent, and its '&Sprite' converts to a reference to an existential
let text: &Text = name                          // 'name' is lent, and its '&String' converts to a reference to its text
func sum<T: Numeric>(_ xs: &[T]) -> T           // takes a reference to any run of T
let total = sum(scores)                         // 'scores' is a List<Int>: it is lent, and the reference converts, binding T to Int
var w: Box<any Widget> = alloc Box(Slider(…))   // Box<Slider> to Box<any Widget>: no new allocation
let pickMax: (Int, Int) -> Int = max            // a named function to a function type
```

**An implicit conversion makes a value of the type its context expects, with no conversion written.** Numbers widen along their fixed order ([04](../04-types/numbers-and-math.md#conversions)). Otherwise there are nine kinds of implicit conversion, each decided by the expected type alone, so type checking stays local ([11](../11-compilation-model.md#type-checking-is-local)). All are free except two: moving a closure into a `Closure`, which may allocate, and an error's `@converts` initializer, which runs. The nine are:

- **A place to a shared reference to it.** A place given where a `&T`, or an optional, a result or a static type of one, is expected, and whose own type doesn't fit, is lent shared, as `&` written before it would lend it ([below](#places-lent-where-a-reference-is-expected)).
- **`T` → `T?` and `T` → `T!E`.** Where a `U?` or a `U!E` is expected, a value that converts to `U` (below) converts and is then wrapped, as `.some` or `.success`, in the same local step, as a named `@c func` passed for a nullable C callback is. It takes the value ([01](../01-values-and-ownership/bindings.md#conversions)). So `return v` in a function that can fail returns `.success(v)` ([10](../10-errors-and-safety/typed-errors.md#propagating-errors-with-try)). No conversion goes the other way: a `Result` value gives up its success value only to `try` or a `.success` pattern. A call or an `await` that can't fail has its success type to begin with ([10](../10-errors-and-safety/typed-errors.md#what-a-failure-type-names)).
- **References to existentials** ([`any P`: explicit dynamic dispatch](protocols-and-generics.md#any-p-explicit-dynamic-dispatch)):
    - A `&T`, for a `T` that meets every protocol of the composition, converts to a `&any P`, and a `mutable &T` to a `mutable &any P`. The new reference refers to the same place, and borrows it as the first one did ([01](../01-values-and-ownership/bindings.md#conversions)).
    - An existential of `P` converts to one of `Q` when `P` implies `Q`, as `any Widget` does to `any Drawable` when `Widget` inherits `Drawable`, or `any P & Sendable` to `any P`. So a `&any P` converts to a `&any Q`, a `mutable &any P` to a `mutable &any Q`, and an unscoped existential to one of `Q`, which keeps its allocation and takes the value.
- **References to runs** ([04](../04-types/collections.md#collections-and-strings)):
    - A `&List<T>` converts to a `&[T]` of its elements, a `mutable &List<T>` to a `mutable &[T]`, and a `&String` to a `&Text` of its text. The new reference refers to storage the first one reaches, and borrows the collection as the first one did, so it copies and allocates nothing ([01](../01-values-and-ownership/bindings.md#conversions)). So a function takes a `&[T]` or a `&Text`, and its callers lend what they own. A parameter of type `&[T]`, with `T` a type parameter, takes a `&List<U>` the same way, binding `T` to `U`, as `sum(scores)` above does.
- **Static values** ([02](../02-views-and-dependencies/scoped-values.md#converting-to-and-from-a-static-type)):
    - A static value converts to its plain type, as a `static &Text` does to a `&Text`, referring to the same data. So a literal goes wherever a `&Text` is expected.
    - A value converts to its static type where it depends only on static storage and immortal data, as a reference to a global `let` does. Where a `static U` is expected, a value that converts to `U` (above) converts and then becomes static, in the same local step, as `T` → `T?` wraps one. A value that depends on anything else never converts, since it may refer to memory that can be freed.
- **`Box<T>` → `Box<any P>`**, and likewise for each object pointer, reference-counted pointer and weak link, such as `WeakPointer<T>` → `WeakPointer<any P>` and `Shared<T>` → `Shared<any P>`. `T` must meet every protocol of the composition, as `T: Sendable` does for `any P & Sendable`, and `T: ~Scoped` must hold. The conversion takes the value, so a place given to it writes `consume` or `copy`, or is copied with nothing written where its type is implicitly copyable, as every position does ([01](../01-values-and-ownership/bindings.md#conversions)). `~Scoped` is what makes the conversion sound: the existential forgets `T` and any dependency `T` carries, so `T` must carry none ([02](../02-views-and-dependencies/scoped-values.md#generic-code-and-scoped)).
- **Closures to `Closure<F>`** ([Unscoped closures: `Closure<F>`](functions-and-closures.md#unscoped-closures-closuref)). A closure literal, an owned value of a closure's concrete type, or a named function or operator moves into a `Closure`, allocating when its captures exceed the inline size. A `Closure<F>` converts to a `Closure<G>` when a function value of type `F` converts to `G` (below), keeping its context.
- **Errors** ([10](../10-errors-and-safety/typed-errors.md#error-unions)). A value of an error union's member, or of a union whose members it all has, converts to that union, taking the value as `T` → `T?` does. A `T!F` converts to a `T!E` the same way when `F` is a member of `E`, or a union whose members `E` all has, so a `@converts` initializer never runs implicitly. Under `try` or `throw`, an error converts to the enclosing failure type through a `@converts` initializer ([10](../10-errors-and-safety/typed-errors.md#propagating-errors-with-try)).
- **Closures to function types**, in the ways listed next.

**These convert to function types** ([Function-typed values](functions-and-closures.md#function-typed-values)):

- A closure, named function or operator converts to a function type. A closure in a place is lent or taken as its kind needs ([below](#function-values-of-closures-in-places)).
- A `Closure<F>` in a place converts to the function type `F`, or to any function type a value of type `F` converts to (below), lent or taken as a closure is. Converting a `Closure<consuming …>` consumes it, but keeps its out-of-line context until the place is next assigned or its scope ends, whichever comes first. The context is then freed without destroying the captures, which the function value took.
- A literal that captures nothing, a named `@c func`, `@export`, imported or `extern c` function, or a `@c` value converts to a `@c` function pointer type ([C function pointers](functions-and-closures.md#c-function-pointers)). The pointer type must have the same types, or inside `unsafe` the same C representations, and must declare at least the converted function's stack need.
- A Rayo function value converts to each of these, with every parameter's type unchanged ([01](../01-values-and-ownership/parameters.md#parameters)), within the limits that C function pointers set for `unsafe` and C functions ([C function pointers](functions-and-closures.md#c-function-pointers)):
    - a stronger kind: non-`mutating` to `mutating` or `consuming`, and `mutating` to `consuming`;
    - the type without `@sendable` or `@noalloc`;
    - its `unsafe` form;
    - for a value that can't fail, the type whose result is a `T!Never` in place of its `T`, which is laid out the same, so a generic `R!E` binds `E` to `Never` ([10](../10-errors-and-safety/typed-errors.md#what-a-failure-type-names));
    - for a value whose result is a `T!Never`, the type whose result is a `T`, for the same reason.

**A function value that can't fail doesn't convert to a type that fails with anything but `Never`**, since it returns a `T`, laid out differently from a `T!E`, and a wrapper would need storage to hold it. A named function converts, through a wrapper the compiler makes ([Function-typed values](functions-and-closures.md#function-typed-values)). Other code writes a new closure literal that calls the function value.

**`x as T` expects a `T`, as an annotation does.** So `x` takes one of the implicit conversions above or a numeric widening ([04](../04-types/numbers-and-math.md#conversions)), or, for a literal, becomes a `T` ([04](../04-types/collections.md#literals)). It never tests a type at run time. Anything else is explicit, such as `box[as: T.self]` ([`any P`: explicit dynamic dispatch](protocols-and-generics.md#unscoped-existentials)).

## Places lent where a reference is expected

**Where a `&T` is expected, a place converts to a shared reference to itself, lent as `&p` would lend it.** A borrow costs the caller nothing, and a bare place never moves, since a move writes `consume` ([01](../01-values-and-ownership/references.md#places-given-to-a-position)). So a `&` there would tell a reader nothing the expected type doesn't, and a call that only reads its arguments reads as plainly as a receiver or an operator, which take their places with no mark ([01](../01-values-and-ownership/references.md#unmarked-places)). A `&p` written there lends the same way.

```rayo
func show(_ e: &Enemy) { … }
func total(_ xs: &[Int]) -> Int { … }

show(boss)                        // lends 'boss' shared
let top: &Enemy = enemies[0]      // holds a reference to enemies[0]
total(scores)                     // lends the List<Int> 'scores', and the reference converts to '&[Int]'
var lines = alloc List<&Text>()
lines.append(name)                // 'append' takes an Element, here a '&Text', so 'name' is lent
show(makeEnemy())                 // lends a temporary, which lives to the end of the statement
```

**A place is lent where a `&T` is expected, or an optional, a result or a static type of one**, such as `(&T)?`, `&T!E` or `static &[T]`. There the reference it makes is wrapped or made static in the same local step, as the conversions above do for any value. Such a type is expected in these positions:

- an argument whose parameter's type is one, given to a function, a method, a subscript, an initializer or an enum case, so a struct's field of such a type takes one too;
- the initializer of a `let` or `var` annotated with one;
- the right side of `=`, where the place it assigns is of such a type;
- an element of a tuple or array literal whose expected element type is one, as a `[&T]`'s is;
- the operand of `return`, or a single-expression body, of a function, closure or `get` whose result type is one.

**A type parameter stands for a `&T` there when the receiver's type or the call's written generic arguments bind it**, as `List<&Text>`'s `Element` does for `append(name)` above. A type parameter that only the call's arguments bind is bound by a bare place to the place's own type (below), so the place isn't lent:

```rayo
func push<T>(_ list: mutable &List<T>, _ x: T) { … }
var picks = alloc List<&Enemy>()

push(mutable picks, boss)         // error: 'picks' binds T to '&Enemy', and 'boss' binds it to Enemy
push(mutable picks, &boss)        // T is '&Enemy', and 'boss' is lent
picks.append(boss)                // the receiver binds Element to '&Enemy', so 'boss' is lent
```

**The conversion lends only a place whose own type doesn't fit.** A place whose type is the expected one, or converts to it implicitly, is given as it is. So a place that holds a `&Enemy`, given where a `&Enemy` is expected, passes a copy of its reference, since a shared reference is implicitly copyable ([01](../01-values-and-ownership/references.md#making-a-reference)).

**The reference it makes converts on as `&p`'s would, in the same local step**, so the conversions above follow it:

- a `Circle` place reaches a `&any Drawable` where `Circle` conforms to `Drawable`, as `seen` above does;
- a `List<Int>` place reaches a `&[Int]`, and a `String` place a `&Text`;
- a place that holds a `mutable &T` reborrows through it, as `&r` does, and a place that holds any reference is lent itself only where a reference to a reference is expected ([01](../01-values-and-ownership/references.md#reborrowing)).

**A value that isn't a place converts the same way, lending a temporary**, as `&makeEnemy()` does ([01](../01-values-and-ownership/references.md#making-a-reference)). So `show(makeEnemy())` above lends an enemy that its statement then destroys, and `let top: &Enemy = makeEnemy()` is the compile error for a binding given a reference to a temporary ([01](../01-values-and-ownership/bindings.md#bindings-that-refer-to-a-place)).

**The conversion has three limits, each where lending would hide what the code does:**

- **It never lends for change.** A `mutable &T` is expected only where code may change the place, and `mutable` is what shows a reader that it may. So a bare place given where a `mutable &T` is expected is the compile error that names `mutable p` ([01](../01-values-and-ownership/references.md#every-lend-for-change-is-marked)).
- **It applies only where a `&T`, or an optional, a result or a static type of one, is expected** ([above](#places-lent-where-a-reference-is-expected)). A `let` or `var` with no annotation, a `ref let`, and a loop's or a `when`'s subject expect no type, so each writes `&` to lend a place ([01](../01-values-and-ownership/bindings.md#bindings)). A function type is no reference either, so a closure in a place given where one is expected writes the mark its kind needs ([below](#function-values-of-closures-in-places)).
- **It never moves or copies the place.** It makes the borrow `&p` makes, which the law of exclusivity checks as it checks any other, so `f(mutable x, x)` is a compile error, as `f(mutable x, &x)` is ([01](../01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)).

**A bare place given for a parameter whose type is a type parameter binds the type parameter to the place's own type**, since nothing expects a `&T` until the type parameter is bound. A `some P` parameter counts, since it is an anonymous type parameter ([Protocols and generics](protocols-and-generics.md#protocols-and-generics)). Such a parameter owns its argument, so the place writes `consume` or `copy`, unless its type is implicitly copyable. Written with `&`, the place binds the type parameter to a reference.

**A parameter that is a reference to a type parameter, such as `&T` or `&some P`, expects a reference.** So a bare place given to it is lent, binding the type parameter to the place's type, unless its own type already fits, as a place that holds a `&Stats` does, binding `T` to `Stats` ([above](#places-lent-where-a-reference-is-expected)):

```rayo
func remember<T>(_ x: T) { … }                       // owns its argument
func print(_ value: &some Formattable)
func largest<T: Comparable>(_ xs: &[T]) -> &T { … }

remember(&name)                   // binds T to '&String': 'name' is lent
remember(name)                    // error: 'remember' owns its argument, a String; write '&name', 'consume name' or 'copy name'
remember(count)                   // binds T to Int, and copies 'count'
print(name)                       // the parameter is a reference, so 'name' is lent, binding the type to String
let best = largest(scores)        // the parameter is a reference, so 'scores' is lent, binding T to Int
```

[Functions and closures](functions-and-closures.md#functions-and-closures) says how overloads that differ in whether they take an argument by reference choose between them.

## Conversions through a mutable reference

**What a mutable reference refers to converts only to an unsized type.** A `mutable &List<T>` converts to a `mutable &[T]`, a `mutable &T` to a `mutable &any P`, and a `mutable &any P` to a `mutable &any Q` of an implied protocol (above). No other conversion changes what a mutable reference refers to: no widening, no `T` → `T?` and no stronger closure kind. Otherwise the callee could store a value of its own type in the caller's place, such as a `mutating` closure into a variable the caller still sees as a non-`mutating` one, which a job system may call on many threads.

**The conversions to unsized types are safe through a mutable reference, since a place of unsized type is never assigned as a whole** ([01](../01-values-and-ownership/references.md#unsized-types)). So the callee can't store a value of another type there:

- through a `mutable &[T]`, it changes elements, each a `T`, and can't add or remove one, since the run's storage belongs to what owns it, such as the list, which alone can resize it ([04](../04-types/collections.md#runs-of-elements));
- through a `mutable &any P`, it calls requirements, which change the value but never its type ([`any P`: explicit dynamic dispatch](protocols-and-generics.md#what-an-existential-may-call)).

```rayo
func clear(_ xs: mutable &[Int]) { for x in mutable xs { x = 0 } }
func widen(_ x: mutable &Int64) { x = .max }

clear(mutable scores)      // fine: a 'mutable &List<Int>' converts to a 'mutable &[Int]'
widen(mutable count)       // error: 'count' is an Int32, and 'widen' takes 'mutable &Int64'
```

**`&r` or `mutable r` of a place that holds a reference is a reborrow, not a conversion**, so `mutable r` of a place holding a `mutable &T` passes as a `mutable &T` argument however often the code lends it ([01](../01-values-and-ownership/references.md#reborrowing)).

## Function values of closures in places

**Where a function type is expected, a mark before a place holding a closure makes a function value of it, and the closure's kind says which mark** ([Function-typed values](functions-and-closures.md#function-typed-values)):

- `&f` of a non-`mutating` closure or `Closure`, which borrows `f` shared;
- `mutable f` of a `mutating` one, which borrows `f` exclusively, and needs `f` changeable;
- `consume f` of a `consuming` one, which takes it ([Closure kinds](functions-and-closures.md#closure-kinds)).

**A mark before a place holding a function value lends a new view of the same closure**, as a reborrow lends a new reference ([01](../01-values-and-ownership/references.md#reborrowing)). `&f` of a non-`mutating` function value carries what `f` carries, the same view a `copy f` would give. `mutable f` of a changeable place holding a `mutating` function value keeps `f` borrowed exclusively until the new view's last use. Only where the expected type is a reference to the function value's own type does the mark refer to the place `f` itself.

**So a function that takes a `mutating` callback can pass it on twice**, lending a new view of it each time:

```rayo
func eachMut(_ xs: mutable &[Enemy], _ body: mutating (mutable &Enemy) -> Void) {
    for x in mutable xs { body(mutable x) }
}

func both(_ a: mutable &[Enemy], _ b: mutable &[Enemy], _ body: mutating (mutable &Enemy) -> Void) {
    eachMut(mutable a, mutable body)     // a new view of the callback 'body', lent to this call
    eachMut(mutable b, mutable body)     // and another, after the first view's last use
}
```
