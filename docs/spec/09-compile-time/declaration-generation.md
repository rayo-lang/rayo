# Generating declarations

[09 · Compile time](../09-compile-time.md)

A generic type may need different fields or cases for different type arguments. Rayo lets compile-time conditions and loops generate those declarations, so each resulting type has ordinary named members. The same constructs can generate declarations at a file's top level.

```swift
struct Columns<Row>(                                      // a struct of arrays: one list per field of Row
    static for f in Row.fields {
        var \(f.name): List<f.type> = []
    }
)

enum AnyEvent {                                           // one case per event type in 'gameplay', which this module imports
    static for t in Module("gameplay").types where t.conforms(Event.self) {
        case \(t.baseName)(t)
    }
}
```

A library writes such a type once, and the compiler generates its members from the lists it walks: `Columns<Particle>` gets one list per field of `Particle`, and `AnyEvent` one case per event type.

**`static if` and `static for` work in three places where declarations go, and generate whatever may appear there:**

- **Struct headers.** In a struct's header, they generate stored fields ([04](../04-types/structs.md#structs)).
- **Type bodies.** In the body of a struct, enum, union or extension, never a protocol, they generate any member ([12](../12-grammar/declarations.md#files-and-declarations)). That covers computed properties, a union's stored members, constants, methods, initializers, subscripts, nested types and type aliases, an enum's cases, and a `deinit`, which is still the type's only one.
- **The top level.** At a file's top level, they generate any declaration ([12](../12-grammar/declarations.md#files-and-declarations)): structs, unions, enums, protocols and type aliases; functions and `task` functions; constants; global `let`s and `var`s, `@threadlocal var`s included; extensions; and `extern c` blocks and `extern c func` declarations. A top-level `static if` can also include or exclude `import` statements, `import c` ones included ([`static if` and conditional compilation](constants-and-conditions.md#static-if-and-conditional-compilation)).

## Computed names

```swift
struct Merged<A, B>(                                      // Merged<Enemy, Player> is an error if both have an 'hp'
    static for f in A.fields { var \(f.name): f.type },
    static for f in B.fields { var \(f.name): f.type },
)
```

A generated declaration needs a name that comes from the element it was made for. **A computed name, written `\(e)`, stands for the identifier that `e`, a `const` string, spells.**

- **Where it goes.** `\(e)` may appear only where the grammar allows ([12](../12-grammar/declarations.md#files-and-declarations)), such as where a declaration is named.
- **What it spells.** The string must be a valid identifier. So `Columns<(Transform, Velocity)>` is an error: a tuple element's `field.name` is its position, `0`.
- **Clashes.** Generated declarations that end up with the same name conflict exactly as written ones would. So two stored fields of one name are a compile error, as in `Merged` above, and functions may overload ([05](../05-protocols-generics-and-closures/functions-and-closures.md#functions-and-closures)).

## Generated declarations are ordinary declarations

**Every rule treats generated declarations as if they were written out**: layout, access control, conformances, exclusivity, moves and partial moves, per-field dependency sets, destruction order and reflection. So the generated stored fields of one value are disjoint places ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)), and `Columns<Particle>.fields` lists them:

```swift
struct Particle(var pos: Vec3, var vel: Vec3)

var columns = Columns<Particle>()                         // fields: pos: List<Vec3>, vel: List<Vec3>
step(&columns.pos, columns.vel.span, dt)                  // two fields of one value: disjoint, as if written out
```

## Generated members are checked per instantiation

**A type whose header or body generates declarations from its type parameters is checked per instantiation**, as a `static for` body is ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#checking-generic-code)), since such a type's members depend on its type arguments. Concrete code names the members directly: `delta.hp`, `columns.pos`. Generic code over `Delta<T>` reaches them through reflection or a computed name, as `diff` does, and an error there is reported at the instantiation. Generic code that uses none of this is still checked once, at its definition.

**Generic code sees such a type at its safe bound.** Generic code is checked once, for every type its parameters may stand for ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#checking-generic-code)). So whatever such a type's generated members could change, generic code assumes they do:

- **When they may include a `deinit` or a stored field**, it may have a `deinit` that isn't `PlainDeinit`, at any depth. So there:
    - it may be move-only;
    - destroying it counts as a use ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it));
    - nothing moves out of it ([01](../01-values-and-ownership/moving-values-out.md#what-can-be-moved-from));
    - it isn't `Pod` or `TrivialFree`.
- **When they may include a stored field**, that field may be of any type, so it may be scoped, as a type parameter may ([02](../02-views-and-dependencies/scoped-values.md#generic-code-and-scoped)), and it isn't sealed, shallow, `Frozen` or `Sendable` either.
- **When they may include an enum case**, a `when` over it ends in `else`.

A `where` clause that states a property, such as `where Delta<T>: Copyable`, lets the code rely on it, and each caller's type arguments must meet it.

## Generation runs in dependency order

```swift
struct A(
    static for f in Delta<A>.fields { … }                 // error: A's fields would depend on themselves
)

struct Node(
    @Replicated var pos: Vec3,
    var pending: Delta<Node>,                             // fine: pending isn't replicated, so Delta<Node> holds only pos
)
```

A generated type's members come from lists of other declarations, and **generation reads each list only once it is final**, so it runs in dependency order:

- **Module lists.** Only imported modules' lists, and a module's own `declaredTypes`, drive generation ([Enumerating a module's types](reflection.md#enumerating-a-modules-types)).
- **Fields and cases.** A list of fields or cases is complete once every member it depends on is.

**Generation is a cycle, and a compile error, when a generated declaration could change one of these:**

- a list that a `static for` iterates;
- a fact that a `static if` or `static for` reads: a conformance, whether a type is copyable, or its layout.

A generated declaration here is one that any `static if` or `static for` generates, directly or through other generated declarations or the `const`s they feed. It may be a member, a top-level declaration, an extension or a conformance. The test is on what it could change, whether or not its branch is taken. So each of these makes generation a cycle:

```swift
struct Echo {
    static if Echo.conforms(Copyable.self) { deinit { … } }   // error: a deinit would change whether Echo is copyable
}

static if !Foo.conforms(Printable.self) {
    extension Foo: Printable { … }                         // error: the conformance would change the condition
}
```

A type that only holds a type generated from it is fine: `Delta<Node>` iterates the fields `Node` declares.
