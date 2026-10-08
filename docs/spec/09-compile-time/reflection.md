# Static reflection

[09 · Compile time](../09-compile-time.md)

The compiler knows a type's fields, cases and other declarations while it builds the program. Static reflection lets generic code inspect that information and produce operations checked for the actual type. The example below turns a struct's fields into separate logging calls:

```swift
struct Stats(var hp: Float, var armor: Float)

func dump<T>(_ value: T) {
    static for field in T.fields {                      // unrolled in the compiler: one copy of the body per field
        log("\(field.name) = \(value[field])")          // each copy is checked with its own field's type
    }
}

dump(Stats(hp: 100, armor: 5))                          // compiles to two log calls, for hp and armor
```

**Every type has compile-time metadata**, which reflection reads ([below](#what-reflection-can-read)).

**`static for` iterates over compile-time lists** ([below](#compile-time-lists)). The body is instantiated once per element, and each instance is type-checked with that element's concrete types, since the elements may differ in type. The rest of the body's checks run on the unrolled code, since an unrolled copy changes what the code after it may use ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#checking-generic-code)). So a move in the body moves once per element.

A complete serializer dispatches on the kind of type it gets, walking a struct's fields and an enum's cases with `static for`. Each branch is checked only for the types that reach it ([`static if` and conditional compilation](constants-and-conditions.md#static-if-and-conditional-compilation)):

```swift
func serialize<T>(_ value: T, into w: mutable Writer) {
    static if T.conforms(Pod.self) && T.isPaddingFree {
        w.bytes(of: value)                                    // Vec3, Color, …: raw bytes
    } else static if T.conforms(Serializable.self) {          // List, String, Map, Handle… conform in std
        value.serialize(into: &w)
    } else static if T.isEnum {
        serializeEnum(value, into: &w)
    } else static if T.isConstructible {                      // every field visible here, so none is skipped silently
        w.beginObject(T.name)
        static for field in T.fields where !field.has(Transient.self) {
            w.key(field.name)
            serialize(value[field], into: &w)
        }
        w.endObject()
    } else {
        static error("\(T.name) can't be reached field by field here: conform it to Serializable")
    }
}

func serializeEnum<T>(_ value: T, into w: mutable Writer) {
    static for c in T.cases {
        if let payload = value[case: c] {                     // nil unless value holds case c
            w.name(c.name)
            static for field in c.payload { serialize(payload[field], into: &w) }
        }
    }
}
```

`Transient` is an attribute that a type's author puts on the fields a serializer should skip ([Attributes](attributes-and-runtime-data.md#attributes)). `@reflect(private)` lets `serialize` see a type's private fields ([below](#reflection-and-access-control)).

## What reflection can read

Reflection reads three kinds of fact, one table each: a type's fields, cases and attributes, the type as a whole, and the places inside a value.

**Fields and cases:**

| Expression | Meaning |
| --- | --- |
| `T.fields` | Compile-time list of stored fields, in declaration order |
| `field.name` | `StaticString`: the field's name, or, for an unlabeled tuple element or an imported struct's anonymous union or struct member, its position among the fields, `0`, `1`, … |
| `field.type` | The field's type, usable as a type |
| `field.hasDefault` | A `const`: whether the declaration has an initializer, or is an optional `var` that isn't `unsafe`, which defaults to `nil` ([04](../04-types/structs.md#initializers)) |
| `field.defaultValue()` | A call that evaluates that default |
| `T.field(ofType: U.self)`, `T.hasField(ofType: U.self)` | The one stored field of type `U` (a compile error if there are none or several), and whether there is exactly one |
| `T.cases`, `c.name`, `c.payload` | Enum cases, their names as `StaticString`s, and their payload types (a list of fields, like `T.fields`) |
| `field.attribute(Bounds.self)`, `T.attribute(A.self)`, `c.attribute(A.self)` | That attribute's value on the field, the type or the enum case, the first one where it is written more than once, or `nil` |
| `field.attributes(Requires.self)`, `T.attributes(A.self)`, `c.attributes(A.self)` | A compile-time list of every value of that attribute there, in order |
| `field.has(Transient.self)`, `T.has(A.self)`, `c.has(A.self)` | Whether the attribute is present |

**The type as a whole:**

| Expression | Meaning |
| --- | --- |
| `T.name` | `StaticString`: the type's declared name, after its enclosing types' names and joined to them by `.`, with its generic arguments resolved, such as `Tag<Player>`, `Outer.Inner` or `(Int, Float)` |
| `T.baseName` | `StaticString`: the name `T`'s declaration gives it alone, such as `Tag` or `Inner`, and an empty string for a type with no declaration |
| `T.module` | `StaticString`: `T`'s module's name, empty for a structural type |
| `T.id` | A stable 64-bit type id that no other type of the program has (below) |
| `T.layoutId` | A 64-bit hash of every representation `T` depends on (below) |
| `field.offset`, `field.bitRange`, `T.size`, `T.alignment` | Layout facts |
| `T.isPaddingFree` | Whether `T`'s layout has no padding bytes ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)) |
| `T.isEnum`, `T.isStruct`, `T.isTuple`, `T.isUnion` | Kind queries for dispatching in `static if` |
| `T.isConstructible` | Whether `T.construct` applies here ([below](#constructing-values-reflectively)) |
| `T.conforms(P.self)`, `T == U`, `T != U` | Protocol conformance and type equality, for use in `static if` |

**Reaching into a value:**

| Expression | Meaning |
| --- | --- |
| `value[field]` | Projection of that field (read, `modify` on a changeable place, or `consume` on one the code may move from) |
| `value[fields: (f1, f2)]` | Several distinct fields projected at once as a tuple of disjoint places ([below](#tuples-field-lists-and-queries)) |
| `value[case: c]` | A projection of case `c`'s payload, as a tuple whose fields are `c.payload`, a one-element tuple for a one-field payload ([04](../04-types/collections.md#tuples-ranges-and-arrays)), or `nil` when `value` holds another case (read, `modify` on a changeable place, or `consume`, which moves the payload out only when `value` holds `c`, as an `owned` pattern does) |

**`value[field]` lends the field in place**, as an accessor that yields does ([02](../02-views-and-dependencies/projections-and-accessors.md#projections-read-and-modify-accessors)). It is a storage projection, which a view can outlive, except on an imported bitfield or an under-aligned field. Those go through a temporary, so it is access-bound there. Every `value[field]` is checked per instantiation, for one field ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#checking-generic-code)). So generic code sees a storage projection or an access-bound one exactly as the instantiation does. Each element of `value[fields: …]` follows the same terms.

**Two kinds of imported C member reflect in their own way:**

- **Imported bitfields.** `T.fields` lists them with the types they import as. `field.offset` is the storage unit's offset, `field.bitRange` locates the field within it, and the field is read and written through its accessors ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)).
- **Anonymous members.** An imported struct's anonymous union or struct member is listed in `T.fields` as **one field of its type**, never as separate fields, so a union's members, which overlap, stay one place ([below](#tuples-field-lists-and-queries)).

**Some types have no fields or cases for reflection to see:**

- a type the compiler builds, whose fields nothing names: a closure literal's or a task's state, or an interpolated literal's value;
- a language type whose layout is left open ([11](../11-compilation-model.md#what-the-language-leaves-open)), such as `any P` or a function type;
- every other language type but a tuple, such as a number, `Bool`, a raw or object pointer, an inline array, a `Simd` vector, `StaticString` or `Name`.

For such a type, `T.fields` and `T.cases` are empty, the kind queries and `T.isConstructible` are false, and `value[field]` and `T.construct` don't apply. Only `T.size`, `T.alignment`, `T.isPaddingFree` and `T.layoutId` observe its layout.

**`T.id` names one type.** It hashes `T`'s identity, which two types share exactly when they are the same type. The identity holds what tells the type apart from every other, built as follows:

- **A declared type** has one part for each declaration from its module inward to itself: a module, type, extension, function, property, subscript, accessor, block, closure literal, `static if` branch or `static for` element. A part holds everything that tells its declaration apart from the others its scope may hold, so two declarations that may coexist never share a part:
    - its kind and its name;
    - an extension's extended type and constraints;
    - a function's, property's or subscript's whole signature, with `static`, its `self` convention, parameter labels, types and conventions, result, `throws` and `where` clause;
    - an accessor's kind (`get`, `set`, `read`, `modify`);
    - for a block, closure or branch, which has no name, its position in the scope around it;
    - every compile-time argument the declaration's body is instantiated with (below).

  So two sibling blocks' local `struct Scratch`s differ, and so do local types of a `get` and a `set`, or of a method's shared and mutable forms ([04](../04-types/collections.md#shared-mutable-and-consuming-forms-of-one-method)). An imported C type has, in place of these parts, the identity 08 gives it ([08](../08-c-interop/imports-and-inline-c.md#the-identity-of-an-imported-type)).
- **The type's own generic arguments** are part of it, a value argument by its value, and so is whether the type is an unscoped existential. So `Tag<Player>` and `Tag<Enemy>` differ, and so do `Box<any P>` and `Box<(any P)>` ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)).
- **A type with no name**, a closure literal's or a task's state or an interpolated literal's value, has its parts as a declared type does, so a generic `task func`'s state differs for each of the function's generic arguments. In place of a name, it has its position among the unnamed types of its innermost scope, counted after `static if` and `static for` are expanded, so each element of a `static for` has its own.
- **A structural type**, a tuple, inline array, raw pointer, existential, function type or error union, is one part. The part holds the type's kind, the identities of the types inside the type, with aliases and parentheses resolved, and every other fact of the type's form:
    - a tuple's labels;
    - an inline array's count;
    - an existential's `any` or `mutable any`, and its protocols, as a set;
    - a function type's `unsafe`, closure kind, `@sendable`, `@noalloc`, or `@c` with its stack need in bytes, `target.cStackReserve` when none is written; its thrown type, `Never` when none is written; and each parameter's `keep` and convention;
    - an error union's members, as a set.

  So `Closure<unsafe () -> Void>` and `Closure<() -> Void>` differ.

**Each instance of a body has its own compile-time arguments**, so a type declared in the body is a different type in each instance. The compile-time arguments a declaration's body is instantiated with are these:

- the declaration's generic arguments, written or implied, such as `Self` and each `some P` parameter's type;
- a `static for` element's index;
- the field a static closure's body is instantiated for ([below](#constructing-values-reflectively));
- the element a compile-time list's `filter` or `map` closure is instantiated for ([below](#compile-time-lists)).

**The id stays the same from build to build while the type's identity does.**

**No two types of one program share an id**: a build in which two identities would hash to one id fails. So within one program an id match is exact, and a type-erased container can trust it. Across builds, two different identities share an id only by a 64-bit hash collision, which no build checks.

**`T.layoutId` hashes `T`'s representation, and recursively those of the types it holds.** A representation covers these:

- the type's layout;
- the scalar type each part holds, so that `Int8` and `Bool` differ;
- an enum's cases, tags and raw values.

The types it holds are those of its stored fields, elements and payloads. The recursion goes through `StaticSpan`, `Slice`, `Shared` and each owning container's element types, but not through raw pointers, object owners or weak pointers. Unlike `T.id`, `T.layoutId` changes whenever any representation it covers changes, barring a 64-bit hash collision. So a binary cache or a type-erased container can tell when data laid out for `T` is stale, or holds bit patterns that are no longer values of it.

## Reflection and access control

A serializer in one module often reflects over types from another, and must not read what those types keep private:

```swift
// in module 'gameplay'
public struct Enemy(
    public var hp: Float,
    private var aiState: Int,                           // not public: other modules can't name it
)

@reflect(private) public struct Checkpoint(           // lets reflection in other modules see 'seed' as well
    public var level: Int,
    private var seed: UInt64,
)

// in a module that imports 'gameplay':
//   Enemy.fields lists hp only, so serialize(enemy) reaches its static error
//   Checkpoint.fields lists level and seed
```

**Reflection sees only what the use site could name, or what `@reflect(private)` shows**, and obeys the rules for writing the field by name there. So, past what `@reflect(private)` shows, reflection grants nothing that naming the field wouldn't:

- **Which fields are listed.** `T.fields` lists every field inside `T`'s own module, and elsewhere only the `public` ones, or all of them when `T` is `@reflect(private)`.
- **`@reflect(private)`** lets reflective code in other modules, such as a serializer, list the type's private fields and read them. Where the use site can call the type's primary initializer ([below](#constructing-values-reflectively)), it also lets that code write them and pass them to `T.construct`. It grants nothing else, so a `private init` keeps guarding the type's invariants.
- **Writing.** `value[field]` projects for `modify` only a `var` of a changeable place ([01](../01-values-and-ownership/bindings.md#changeable-places)) that code there could assign by name, or that `@reflect(private)` lets it write.
- **Moving out.** `consume value[field]` moves the field out where consuming it by name could ([01](../01-values-and-ownership/moving-values-out.md#what-can-be-moved-from)): from a place the code may move from, with no `deinit` along the path. `consume value[case: c]` moves a payload out under the same conditions. A private field of another module's type is moved out only where `@reflect(private)` lets the use site write it.
- **`unsafe` fields and unions.** A field declared `unsafe`, such as `Span`'s `baseAddress`, is read or written through reflection only inside `unsafe`, as by name. Reading a union member follows the union read rule ([04](../04-types/enums.md#untagged-unions)).

## Constructing values reflectively

Loaders (save files, network replication, asset import) need the reverse of `serialize`: building a `T` field by field, including fields with no default. **Static closures** do it: closures whose body is instantiated once per field, like a `static for` body:

```swift
func deserialize<T>(_ r: mutable Reader) throws(LoadError) -> T {
    static if T.conforms(Pod.self) && T.isPaddingFree {      // mirrors serialize: raw bytes
        return try r.read(T.self)
    } else static if T.conforms(Serializable.self) {         // one protocol for both directions
        return try T(from: &r)
    } else static if T.isEnum {
        return try deserializeEnum(&r)
    } else static if T.isConstructible {
        try r.beginObject(T.name)
        let value = try T.construct { static field in          // one instantiation per stored field
            static if field.has(Transient.self) {
                return field.defaultValue()                   // never saved; a @Transient field needs a default
            } else {
                try r.expectKey(field.name)
                return try deserialize(&r) as field.type      // must produce exactly field.type
            }
        }
        try r.endObject()
        return value
    } else {
        static error("\(T.name) can't be built field by field here: conform it to Serializable")
    }
}

func deserializeEnum<T>(_ r: mutable Reader) throws(LoadError) -> T {
    let tag = try r.readName()
    static for c in T.cases {
        if tag == Name(c.name) { return try T.makeCase(c) { static field in try deserialize(&r) as field.type } }
    }
    throw .unknownCase(tag)
}
```

**A static closure appears only as the argument of `T.construct` or `T.makeCase`**, which run its instances once each, in field order. It is checked as that sequence of bodies, unrolled. An instance names the enclosing function's places as the body of a `static for` there would. So it may move out of one that no later instance uses, as `rebuild` does with each field of an owned `old` ([above](#reflection-and-access-control)):

```swift
func rebuild<T>(_ old: owned T) -> T {
    return T.construct { static field in consume old[field] }   // each instance moves out its own field of 'old'
}
```

**`T.construct` calls `T`'s primary initializer with every field, in header order, and runs no secondary `init`** ([04](../04-types/structs.md#initializers)), so the use site must be able to call it. `T.isConstructible` (`const`) says whether it can. It is true only for a struct with a primary initializer, an imported C struct's included ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)), or a tuple type. Even then it is false when the type:

- is marked `@opaque`, as an imported C type is when a header only declares it, or when Rayo can't reproduce its layout or map its members ([08](../08-c-interop/imports-and-inline-c.md#what-imports-as-what));
- has stored fields the use site can't see (`private` ones, without `@reflect(private)`);
- has an `unsafe` stored field, or an `unsafe` primary initializer, and the use isn't inside `unsafe`, since `T.construct` would call it with no `unsafe` written ([10](../10-errors-and-safety/unsafe-code.md#what-needs-unsafe));
- has a primary initializer the use site can't call: a `private init` one, from another module, whatever `@reflect(private)` shows, since a `private init` guards the type's invariants ([above](#reflection-and-access-control)). The private fields `@reflect(private)` shows count as `public` here, so they don't stop the call.

`T.makeCase` does the same for one enum case's payload, and applies to every case of an enum reflection can see into, since a case and its payload are as visible as the enum.

## Tuples, field lists, and queries

An ECS system runs over every table whose entities have a given set of components, reading some of each row's components and changing others:

```swift
protocol Table { associatedtype Row }
struct Archetype<Row>(                                    // Row: a tuple of component types
    var rows = SoA<Row>(),                                // current allocator, as for List
    var entities = List<Entity>(),
): Table

func integrate<Row>(_ table: mutable Archetype<Row>, dt: Float) {
    const tf = Row.field(ofType: Transform.self)          // per instantiation; a compile error if absent
    const vf = Row.field(ofType: Velocity.self)
    let (var ts, vs) = &table.rows[fields: (tf, vf)]    // MutableSpan<Transform>, Span<Velocity>
    for (t, v) in zip(&ts, vs) { t.position += v.linear * dt }
}

struct World(                                             // one table per archetype the game declares
    var movers   = Archetype<(Transform, Velocity)>(),
    var sleepers = Archetype<(Transform, Velocity, Asleep)>(),
    var props    = Archetype<(Transform, Mesh)>(),
)

func integrateAll(_ w: mutable World, dt: Float) {          // "Transform and Velocity, but not Asleep"
    static for f in World.fields where f.type.Row.hasField(ofType: Transform.self)
                                     && f.type.Row.hasField(ofType: Velocity.self)
                                     && !f.type.Row.hasField(ofType: Asleep.self) {
        integrate(&w[f], dt: dt)                          // instantiated for 'movers' only
    }
}
```

**Tuples are reflected like structs.** A tuple type's elements are its `T.fields`, so generic code can take a tuple of types, such as `Archetype<(Transform, Velocity)>`, and `static for` over it.

**`value[fields: (f1, f2, …)]` projects several fields of one value at once, as a tuple of places.** In generic code, two separate projections whose fields may be one overlap where the borrows are checked, as two that `Row.field(ofType:)` picks may ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)). A field list is checked at instantiation instead:

- **Distinct fields.** The fields must be distinct `const` field descriptors, checked at instantiation. Distinct stored fields of a struct or tuple never overlap ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)), except those the next bullet names.
- **Overlapping members are rejected** at instantiation, since writing one can change the other ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)): two members of a union type (`T.isUnion`), which are all one place, and two imported bitfields in the same C memory location.
- **Mixed binding kinds.** Each element of the pattern has its own binding kind, so one projection can borrow one field shared and another exclusively (below).
- **`SoA`.** `s[fields:]` on an `SoA` `s` returns a tuple of its columns, each in the kind of its pattern element ([04](../04-types/data-layout.md#struct-of-arrays-soat)).

For one row of a table, held in a `var`:

```swift
var row: Row = …
let (t, var v) = &row[fields: (tf, vf)]       // t borrows the Transform shared, v the Velocity exclusively
```

## Enumerating a module's types

A registry of every component type is a `const` built from a module's list of types:

```swift
const componentTypes: [_ of TypeInfo] = Module("gameplay").types
    .filter { $0.conforms(Component.self) }
    .map { typeInfo($0.self) }                        // a const table in read-only data
```

**`Module.current.types` and `Module("gameplay").types` are compile-time lists of a module's type declarations**, usable in `static for` and in `const` evaluation. A module can list its own types and those of the modules it imports.

**A module's list holds its type declarations, top-level and nested, generated ones included, in source order** ([What a build declares](attributes-and-runtime-data.md#what-a-build-declares)). It holds only those that neither have generic parameters nor lie inside a generic type or a function, and, for another module, only its `public` ones. Each element names one type, usable as a type, as `field.type` is, so `$0.self` is its type value ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#value-parameters-and-type-values)). `Module("gameplay")` takes the name the build declares for the module, never an `import … as` name.

**Only imported lists and a module's declared types drive generation.** A module's own `types` list includes the types it generates, so no declaration may be generated from it, directly or through a `const`. `Module.current.declaredTypes` lists, in the same order, only those declared outside any `static if` or `static for`. So it may drive generation under the rule for the facts generation reads ([Generation runs in dependency order](declaration-generation.md#generation-runs-in-dependency-order)).

For example, an `enum AnyEvent` can have a case per type in `declaredTypes` that conforms to `Event`, as long as no case changes which of them do. `Module.current.types` may be read in function bodies, and in `const`s that no generating `static for` or `static if` reads. So `gameplay` could build the registry above from its own list ([Generation runs in dependency order](declaration-generation.md#generation-runs-in-dependency-order)).

## Compile-time lists

**These are compile-time lists, which `static for` walks and `const` evaluation reads:**

- `T.fields`, which for a tuple lists its element types ([above](#tuples-field-lists-and-queries));
- `T.cases` and a case's `payload`;
- a module's `types` and `declaredTypes`;
- a `const` inline array or `List`;
- a range of `const` integers.

**They support `filter`, `map`, `contains` and `count` in `const` evaluation.** A closure passed to one of them takes a list element as its parameter. The closure is instantiated once per element, as a static closure is ([above](#constructing-values-reflectively)), since the elements may differ in type, but it isn't marked `static`. `filter` and `map` give compile-time lists, which a `const` converts to an inline array or a `List` of their element type.
