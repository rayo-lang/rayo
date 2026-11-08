# 09 · Compile time

Rayo can do work before a program runs when the answer depends only on information available to the compiler. It can evaluate values, inspect types, and generate declarations or code. Generated members become ordinary parts of a type and are checked for each type that uses them.

A network replication layer sends only the fields of an object that changed since the last update. For every type it needs a record with one optional per replicated field, under that field's name, and a function that fills the record in. In Rayo each is written once, for every type:

```swift
struct Player(
    @Replicated var pos: Vec3,                         // the replication layer sends this field
    @Replicated var hp: Float = 100,
    var input: InputState,                             // local only
)

struct Delta<T>(                                       // what a replicated update changed, field by field
    static for f in T.fields where f.has(Replicated.self) {
        var \(f.name): f.type? = nil                   // a field named after f, of f's type, made optional
    }
)

func diff<T>(_ old: T, _ new: T) -> Delta<T> {
    var d = Delta<T>()
    static for f in T.fields where f.has(Replicated.self) {
        static if f.type.conforms(Equatable.self) {
            if old[f] != new[f] { d.\(f.name) = copy new[f] }          // a computed name, checked per instantiation
        } else {
            if (old[f] != new[f]).any { d.\(f.name) = copy new[f] }    // a vector compares lane by lane
        }
    }
    return d
}

let d = diff(lastSent, player)                         // d: Delta<Player>
if d.hp != nil { send(d.hp) }                          // a generated field, named like a written one
```

`Delta<Player>` is an ordinary struct with two fields, `pos: Vec3?` and `hp: Float?`. `T.fields` is a list the compiler builds from `T`'s declaration. `static for` walks it inside the compiler, and `\(f.name)` names a declaration with the text of `f.name`. The loop in `diff` unrolls into two comparisons, each type-checked with its own field's type.

**Three pieces make this work, all at compile time:**

1. **`const`**: evaluation at compile time, which runs ordinary functions under a few conditions ([Running code at compile time: `const`](09-compile-time/constants-and-conditions.md#running-code-at-compile-time-const)).
2. **`static if` and `static for`**: compile-time control flow, unrolled or discarded before code generation. They work in code and where declarations go, so they can generate fields, cases, methods and whole types ([Generating declarations](09-compile-time/declaration-generation.md#generating-declarations)).
3. **Static reflection**: over every type, plus **user-defined attributes** such as `@Replicated` ([Static reflection](09-compile-time/reflection.md#static-reflection), [Attributes](09-compile-time/attributes-and-runtime-data.md#attributes)).

## Subchapters

- [Constants and conditional compilation](09-compile-time/constants-and-conditions.md)
- [Static reflection](09-compile-time/reflection.md)
- [Generating declarations](09-compile-time/declaration-generation.md)
- [Attributes, runtime data and build inputs](09-compile-time/attributes-and-runtime-data.md)
