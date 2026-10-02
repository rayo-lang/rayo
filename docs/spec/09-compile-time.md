# 09 · Compile time

A network replication layer sends only the fields of an object that changed since the last update. For every type it needs a record with one optional per replicated field, under that field's name, and a function that fills the record in. In Rayo each is written once, for every type:

```swift
struct Player(
    @Replicated var pos: Vec3,                         // @Replicated marks the fields to send (an attribute, below)
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
if let hp = d.hp { send(hp) }                          // a generated field, named like a written one
```

`Delta<Player>` is an ordinary struct with two fields, `pos: Vec3?` and `hp: Float?`. `T.fields` is a list the compiler builds from `T`'s declaration, `static for` walks it inside the compiler, and `\(f.name)` names a declaration with the text of `f.name`. The loop in `diff` unrolls into two comparisons, each type-checked with its own field's type. Three pieces make this work:

1. **`const`**: evaluation at compile time, which runs ordinary functions under the conditions below.
2. **`static if` / `static for`**: compile-time control flow, unrolled or discarded before code generation, in code and where declarations go, so they can generate fields, cases, methods and whole types.
3. **Static reflection**: over every type, plus **user-defined attributes** such as `@Replicated`.

## Running code at compile time: `const`

A table worked out ahead of time, such as a sine table, a name hashed once or a list of presets, is a `const`, and the function that builds it is ordinary code that the compiler runs:

```swift
const maxPlayers = 8
const sinTable: [1024 of Float] = makeSinTable()        // runs in the compiler
const jumpId: Name = "jump"                             // hashed at compile time

func makeSinTable() -> [1024 of Float] {
    var t: [1024 of Float] = .init(repeating: 0)
    for i in 0..<1024 { t[i] = sin(Float(i) / 1024 * 2 * .pi) }
    return t
}
```

**A `const` initializer is evaluated at compile time**, and checked as the body of a function with no parameters that returns the `const`'s type, as a default value is ([01](01-values-and-ownership.md#default-arguments)). **Any function can run at compile time if what it executes, on that input:**

- calls no C function, whether imported or declared `extern c`;
- accesses no global other than a `const`, a `static const` included, and no thread-local other than the current allocator, which at compile time is a compile-time heap (below);
- starts, parks and wakes no thread: it reaches no blocking wait, `Runtime.park` or `Runtime.wake`;
- makes no volatile access, and no access through a pointer made from an integer;
- reads no clock.

A `const` whose initializer does anything else is a compile error, while a global `let`'s runs at startup instead ([07](07-concurrency.md#initialization-at-startup)).

- **What runs is what counts.** A function with a branch that reads a global `let` still runs in the compiler on an input that never takes that branch.
- **It computes what run time would.** Each scope keeps the diagnostic checks it has at run time, as `target.checks` reports them ([10](10-errors-and-safety.md#check-levels)), so an overflow wraps where overflow checks are off. A panic is a compile error that reports it.
- **`unsafe` and `unchecked` code run too, checked.** Every raw access is checked against what [10](10-errors-and-safety.md#unsafe-code) asks of an access through a raw pointer, and every memory-safety check an `unchecked` block removes still runs, so an access outside its allocation, into freed memory, misaligned or of an invalid value is a compile error. `unsafe` code that breaks a promise evaluation can't check, such as respecting a live borrow, gets no promise about the `const`'s value, as it gets none at run time. A diagnostic check that an `unchecked` block removes stays off, as at run time ([10](10-errors-and-safety.md#check-levels)).
- **Allocation works.** At compile time the current allocator is a compile-time heap, so containers, strings and allocators run as they do at run time, and `makePresets()` below can build a `List` with `append`. `.system` allocates from the compile-time heap too. Running out of it exceeds the toolchain's limit (below), never an allocation failure that code observes, so no value depends on the building machine's memory.
- **One thread.** Evaluation runs on one thread, so no `const`'s value depends on thread timing.
- **Evaluation is bounded.** A `const`'s evaluation that runs past the toolchain's limit is a compile error, so a runaway loop fails the build instead of hanging it; a global `let`'s leaves the global to startup ([07](07-concurrency.md#initialization-at-startup)).
- **No cycles.** A `const` whose evaluation reads itself, directly or through other `const`s, is a compile error.

### Consts that reach run time

A `const` can allocate while the compiler builds it, but the running program has no compile-time heap. So a `const` that **reaches run time**, named outside compile-time code (`const` initializers, `static if` and `static for` conditions and lists, and attribute arguments), whether or not that code runs, is copied into the program's read-only data:

```swift
struct Preset(var name: String, var hp: Float) {
    func clone() -> Preset { Preset(name: name.clone(), hp: copy hp) }   // so a List<Preset> can be cloned
}

const enemyPresets: List<Preset> = makePresets()       // built in the compiler, allocating as it goes

func makePresets() -> List<Preset> {
    var a = List<Preset>()
    a.append(Preset(name: "grunt", hp: 50))
    a.append(Preset(name: "brute", hp: 400))
    return a
}

func presets() -> Span<Preset> { enemyPresets.span }   // a view of static storage: any function may return it

struct World(var presets: StaticSpan<Preset>, …)

func setUp(_ world: mutable World) {
    world.presets = enemyPresets.staticSpan            // an unscoped view, so a field can keep it
    var edited = enemyPresets.clone()                  // fine: a run-time copy, in the current allocator
    edited.append(Preset(name: "boss", hp: 900))
    enemyPresets.append(Preset(name: "boss", hp: 900))   // error: a const is never mutated
}
```

**A `const` that reaches run time is frozen into read-only data.** It keeps its declared type, and its buffers carry the static allocator ([06](06-memory-and-allocators.md#the-static-allocator)), as a global `let` in static data does ([07](07-concurrency.md#initialization-at-startup)). Freezing copies each compile-time heap allocation that the value reaches through a raw pointer, a container's included, once, into read-only data aligned at least as the allocation was, as one allocation ([10](10-errors-and-safety.md#unsafe-code)). It points each pointer at the same offset in the copy, and makes every allocator word in the value the static allocator's, whether or not it records an allocation: an empty `List`'s and a literal-backed `String`'s record none. An address that evaluation turned into an integer names nothing at run time ([10](10-errors-and-safety.md#unsafe-code)).

- **Its views are static storage.** Its `.span` is a `Span` of static storage, which rule 5 lets any function return ([02](02-views-and-dependencies.md#rule-5-the-callee-side)).
- **Unscoped views.** For a `List` or an `[N of T]` reached from a `const` through stored fields and storage projections, as `enemyPresets[i].name` is, the compiler also provides a `staticSpan` property, and for a `String` a `staticString` property. It returns an unscoped `StaticSpan<T>` or `StaticString`, which may be kept anywhere because what it views is never freed ([below](#staticspan-views-of-immortal-data)).
- **Strings are null-terminated.** The compiler stores a NUL after the text of every `String` it freezes, not counted in its length, so a `staticString` is null-terminated as every `StaticString` is ([04](04-types.md#strings)).

**What can be frozen.** A `const` that reaches run time must be **freezable**, or it is a compile error. A freezable value:

- is `Frozen`: nothing writes what it holds or owns through a shared borrow ([06](06-memory-and-allocators.md#frozen-types-with-no-interior-mutability)), and nothing ever mutates a value in static data. A type declared `: unsafe Frozen` promises that nothing writes a frozen value of it, bookkeeping included. So it holds no `Synchronized` value, and a global `let` of a `Synchronized` type is initialized at startup, in memory its methods can write ([07](07-concurrency.md#initialization-at-startup));
- is `TrivialFree` ([06](06-memory-and-allocators.md#releasing-a-value-without-destroying-it-trivialfree)). A frozen value is never destroyed, which skips only frees, and those free nothing under the static allocator. So a `Shared` or a `LocalShared` isn't freezable, although it may be `Frozen`: its count is written at run time, and its `deinit` isn't `PlainDeinit`;
- holds no `StablePool`, whose pin counts are written at run time, as `Shared`'s count is ([03](03-handles-and-objects.md#pinning-for-c));
- holds no weak pointer or weak link at any depth, since the objects and `Shared` values they name exist only at run time ([03](03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert), [06](06-memory-and-allocators.md#sharedt-data-with-many-owners)). So a `Slice` or a `Waker`, which holds a weak link, isn't freezable either;
- holds no `Allocator` id but `.system`, since an allocator registered at compile time doesn't exist at run time. So a global `let` that registers one, such as `let frameArena = Allocator.register(Arena(size: 64.mb))`, is initialized at startup;
- holds no stale owning value: every owning value in it would pass an open when evaluation ends ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it));
- reaches, through its raw pointers, only live compile-time heap memory, which freezing copies (above), or immortal data: a literal's bytes, what a `StaticSpan` or `StaticString` views, another `const`'s frozen data, type metadata and code. Never freed memory, and never a pointer made from an integer that evaluation got from a pointer; one made from an integer that never was an address, such as a device register's, is frozen as it is;
- is unscoped ([02](02-views-and-dependencies.md#scoped-values)), unless every view it holds depends on nothing, as a function value made from a named function does ([05](05-protocols-generics-and-closures.md#function-typed-values)): freezing follows only raw pointers, so any other view would still point at compile-time memory. A frozen value views frozen data through a `StaticSpan` or a `StaticString` (above);
- has a `Sendable` type, as every global that safe code reaches does ([07](07-concurrency.md#global-state)).

The same test decides which global `let`s go into static data ([07](07-concurrency.md#initialization-at-startup)). A `const` that doesn't reach run time, such as a list iterated by `static for`, may hold anything.

## `static if` and conditional compilation

```swift
static if target.platform == .ps5 || target.platform == .xboxSeries {
    typealias GpuResourceId = UInt64
} else {
    typealias GpuResourceId = UInt32
}

func store<T>(_ value: T, into w: mutable Writer) {
    static if T.conforms(Pod.self) && T.isPaddingFree {
        w.bytes(of: value)                                      // fast path for plain data: safe, one memcpy
    } else {
        serialize(value, into: &w)
    }
}
```

**Conditions must be `const`. The branch not taken is parsed but not type-checked, so it can mention symbols that only exist on another platform.**

- **At the top level**, `static if` can include or exclude declarations and whole `import` and `import c` statements. A condition that guards an import reads only literals, `const`s of modules imported outside any `static if`, and the prelude's `target`, never a declaration of the module's own that shadows it ([11](11-compilation-model.md#modules-and-names)), so which modules a file imports never depends on what an import provides or on the module's own declarations. No `import` goes inside a `static for`, at any depth.
- **Per instantiation.** In generic code, a branch is checked only for the instantiations whose condition holds ([05](05-protocols-generics-and-closures.md#protocols-and-generics)). That lets `store` call `w.bytes(of:)`, which accepts only a padding-free `Pod` type ([04](04-types.md#plain-data-pod-and-bit-casts)). `T.isPaddingFree` is a reflection query ([below](#what-reflection-can-read)).
- **Refusing an instantiation or a build.** `static error("…")` turns a branch that must not be instantiated or built into a compile error with that message, as the serializer [below](#static-reflection) does. It stands where a statement, a member, a field or a top-level declaration can, as in `static if !target.flag("sse4") { static error("needs SSE4") }`.

**`target`** is a `const` the prelude declares ([11](11-compilation-model.md#modules-and-names)). It exposes:

- `platform`, `arch` and `endian`;
- `profile`: `.dev`, `.profile` or `.ship`;
- `checks`: the set of diagnostic checks that are on where it is read, as `@checks` names them ([10](10-errors-and-safety.md#check-levels));
- `cStackReserve`: the stack, in bytes, that a call into C checks is left, unless the C function called declares its own need with `stack(n)` ([08](08-c-interop.md#the-stack-a-c-call-needs));
- flags the build defines: `target.flag("editor")`, or `target.flag("poolSize")` for one holding a number, with the type and value the build gives it ([below](#what-a-build-declares)). Reading a flag the build doesn't declare is a compile error, and `target.hasFlag("editor")`, a `const` `Bool`, says whether it declares one, so a library can read a flag that only some builds define inside `static if target.hasFlag("editor") { … }`.

## Static reflection

```swift
struct Stats(var hp: Float, var armor: Float)

func dump<T>(_ value: T) {
    static for field in T.fields {                      // unrolled in the compiler: one copy of the body per field
        log("\(field.name) = \(value[field])")          // each copy is checked with its own field's type
    }
}

dump(Stats(hp: 100, armor: 5))                          // compiles to two log calls, for hp and armor
```

**Every type has compile-time metadata. `static for` iterates over compile-time lists: the body is instantiated once per element, and each instance is type-checked with that element's concrete types.** The rest of its checks run on the unrolled code as [05](05-protocols-generics-and-closures.md#protocols-and-generics) says, so a move in the body moves once per element.

A complete serializer dispatches on the kind of type it gets, walking a struct's fields and an enum's cases with `static for`:

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

- `Transient` is an attribute that a type's author puts on the fields a serializer should skip ([Attributes](#attributes)).
- `@reflect(private)` lets `serialize` see a type's private fields ([below](#reflection-and-access-control)).

### What reflection can read

**Fields and cases:**

| Expression | Meaning |
| --- | --- |
| `T.fields` | Compile-time list of stored fields, in declaration order |
| `field.name` | `StaticString`: the field's name, or, for an unlabeled tuple element or an imported struct's anonymous union or struct member, its position among the fields, `0`, `1`, … |
| `field.type` | The field's type, usable as a type |
| `field.hasDefault` | A `const`: whether the declaration has an initializer, or is an optional `var` that isn't `unsafe`, which defaults to `nil` ([04](04-types.md#initializers)) |
| `field.defaultValue()` | A call that evaluates that default |
| `T.field(ofType: U.self)`, `T.hasField(ofType: U.self)` | The one stored field of type `U` (a compile error if there are none or several), and whether there is exactly one |
| `T.cases`, `c.name`, `c.payload` | Enum cases, their names as `StaticString`s, and their payload types (a list of fields, like `T.fields`) |
| `field.attribute(Bounds.self)`, `T.attribute(A.self)`, `c.attribute(A.self)` | That attribute's value on the field, the type or the enum case, the first one where it is written more than once, or `nil` |
| `field.attributes(Requires.self)`, `T.attributes(A.self)`, `c.attributes(A.self)` | A compile-time list of every value of that attribute there, in order |
| `field.has(Transient.self)`, `T.has(A.self)`, `c.has(A.self)` | Whether the attribute is present |

**The type as a whole:**

| Expression | Meaning |
| --- | --- |
| `T.name`, `T.baseName`, `T.module`, `T.id` | The type's declared name, after its enclosing types' names and joined to them by `.`, with its generic arguments resolved, such as `Tag<Player>`, `Outer.Inner` or `(Int, Float)`; the name its declaration gives it alone, such as `Tag` or `Inner`, and an empty string for a type with no declaration; its module's name, empty for a structural type; each a `StaticString`; and a stable 64-bit type id that no other type of the program has (below) |
| `T.layoutId` | A 64-bit hash of every representation `T` depends on (below) |
| `field.offset`, `field.bitRange`, `T.size`, `T.alignment` | Layout facts |
| `T.isPaddingFree` | Whether `T`'s layout has no padding bytes ([04](04-types.md#plain-data-pod-and-bit-casts)) |
| `T.isEnum`, `T.isStruct`, `T.isTuple`, `T.isUnion` | Kind queries for dispatching in `static if` |
| `T.isConstructible` | Whether `T.construct` applies here ([below](#constructing-values-reflectively)) |
| `T.conforms(P.self)`, `T == U`, `T != U` | Protocol conformance and type equality, for use in `static if` |

**Reaching into a value:**

| Expression | Meaning |
| --- | --- |
| `value[field]` | Projection of that field (read, `modify` on a changeable place, or `consume` on one the code may move from) |
| `value[fields: (f1, f2)]` | Several distinct fields projected at once as a tuple of disjoint places ([below](#tuples-field-lists-and-queries)) |
| `value[case: c]` | A projection of case `c`'s payload, as a tuple whose fields are `c.payload`, a one-element tuple for a one-field payload ([04](04-types.md#tuples-ranges-and-arrays)), or `nil` when `value` holds another case (read, `modify` on a changeable place, or `consume`, which moves the payload out only when `value` holds `c`, as an `owned` pattern does) |

- **Projections.** `value[field]` lends the field in place, as an accessor that yields does ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)). It is a storage projection, which a view can outlive, except on an imported bitfield or an under-aligned field, which go through a temporary, so it is access-bound there. Every `value[field]` is checked per instantiation, for one field ([05](05-protocols-generics-and-closures.md#protocols-and-generics)), so generic code sees a storage projection or an access-bound one exactly as the instantiation does. Each element of `value[fields: …]` follows the same terms.
- **Imported bitfields.** `T.fields` lists them with the types they import as. `field.offset` is the storage unit's offset, `field.bitRange` locates the field within it, and the field is read and written through its accessors ([08](08-c-interop.md#structs-unions-and-enums)).
- **Anonymous members.** An imported struct's anonymous union or struct member is listed in `T.fields` as **one field of its type**, never as separate fields, so a union's members, which overlap, stay one place ([below](#tuples-field-lists-and-queries)).
- **Types reflection can't see into.** A type the compiler builds, a closure literal's or a task's state or an interpolated literal's value; a language type whose layout is left open ([11](11-compilation-model.md#what-the-language-leaves-open)), such as `any P` or a function type; and every other language type but a tuple, such as a number, `Bool`, a raw or object pointer, an inline array, a `Simd` vector, `StaticString` or `Name`, has no fields or cases to reflect: `T.fields` and `T.cases` are empty, the kind queries and `T.isConstructible` are false, and `value[field]` and `T.construct` don't apply. Only `T.size`, `T.alignment`, `T.isPaddingFree` and `T.layoutId` observe its layout.
- **`T.id` names one type.** It hashes `T`'s identity, which two types share exactly when they are the same type:
    - **a declared type** has one part for each declaration from its module inward to itself: a module, type, extension, function, property, subscript, accessor, block, closure literal, `static if` branch or `static for` element. A part holds everything that tells its declaration apart from the others its scope may hold, so two declarations that may coexist never share a part:
        - its kind and its name;
        - an extension's extended type and constraints;
        - a function's, property's or subscript's whole signature, with `static`, its `self` convention, parameter labels, types and conventions, result, `throws` and `where` clause;
        - an accessor's kind (`get`, `set`, `read`, `modify`);
        - for a block, closure or branch, which has no name, its position in the scope around it;
        - every compile-time argument the declaration's body is instantiated with: its generic arguments, written or implied, such as `Self` and each `some P` parameter's type, a `static for` element's index, the field a static closure's body is instantiated for ([below](#constructing-values-reflectively)), and the element a compile-time list's `filter` or `map` closure is instantiated for ([below](#enumerating-a-modules-types)).

      So two sibling blocks' local `struct Scratch`s differ, and so do local types of a `get` and a `set`, or of a method's shared and mutable forms ([04](04-types.md#shared-mutable-and-consuming-forms-of-one-method)). An imported C type has, in place of these parts, the identity [08](08-c-interop.md#importing-headers) gives it;
    - **the type's own generic arguments**, a value argument by its value, and whether it is an unscoped existential, so `Tag<Player>` and `Tag<Enemy>` differ, and so do `Box<any P>` and `Box<(any P)>` ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch));
    - **a type with no name**, a closure literal's or a task's state or an interpolated literal's value, has its parts as a declared type does, with, in place of a name, its position among the unnamed types of its innermost scope, counted after `static if` and `static for` are expanded. So a generic `task func`'s state differs for each of the function's generic arguments, and each element of a `static for` has its own;
    - **a structural type**, a tuple, inline array, raw pointer, existential, function type or error union, is one part holding its kind, the identities of the types in it, with aliases and parentheses resolved, and every other fact of its form: a tuple's labels; an inline array's count; an existential's `any` or `mutable any`, and its protocols, as a set; a function type's `unsafe`, closure kind, `@sendable`, `@noalloc`, or `@c` with its stack need in bytes, `target.cStackReserve` when none is written, its thrown type, `Never` when none is written, and each parameter's `keep` and convention; an error union's members, as a set. So `Closure<unsafe () -> Void>` and `Closure<() -> Void>` differ.

  The id stays the same from build to build while that identity does. No two types of one program share an id: a build in which two identities would hash to one id fails. So within one program an id match is exact, and a type-erased container can trust it. Across builds, two different identities share an id only by a 64-bit hash collision, which no build checks.
- **`T.layoutId`** hashes `T`'s own representation, its layout, the scalar type each part holds, so that `Int8` and `Bool` differ, and an enum's cases, tags and raw values, and those of the types of its stored fields, elements and payloads, recursively, including through `StaticSpan`, `Slice`, `Shared` and each owning container's element types, but not through raw pointers, object owners or weak pointers. Unlike `T.id`, it changes, barring a 64-bit hash collision, whenever any of those does, so a binary cache or a type-erased container can tell when data laid out for `T` is stale, or holds bit patterns that are no longer values of it.

### Reflection and access control

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

**Reflection sees only what the use site could name, or what `@reflect(private)` shows**, and obeys the rules for writing the field by name there:

- **Which fields are listed.** `T.fields` lists every field inside `T`'s own module, and elsewhere only the `public` ones, or all of them when `T` is `@reflect(private)`.
- **`@reflect(private)`** lets reflective code in other modules, such as a serializer, list the type's private fields and read them, and, where the use site can call the type's primary initializer ([below](#constructing-values-reflectively)), write them and pass them to `T.construct`. It grants nothing else, so a `private init` keeps guarding the type's invariants.
- **Writing.** `value[field]` projects for `modify` only a `var` of a changeable place ([01](01-values-and-ownership.md#changeable-places)) that code there could assign by name, or that `@reflect(private)` lets it write.
- **Moving out.** `consume value[field]` moves the field out where consuming it by name could ([01](01-values-and-ownership.md#what-can-be-moved-from)): from a place the code may move from, with no `deinit` along the path, and `consume value[case: c]` moves a payload out under the same conditions. A private field of another module's type is moved out only where `@reflect(private)` lets the use site write it.
- **`unsafe` fields and unions.** A field declared `unsafe`, such as `Span`'s `baseAddress`, is read or written through reflection only inside `unsafe`, as by name. Reading a union member follows the union read rule of [04](04-types.md#untagged-unions).

### Constructing values reflectively

Loaders (save files, network replication, asset import) need the reverse of `serialize`: building a `T` field by field, including fields with no default. **Static closures** do it: closures whose body is instantiated once per field, like a `static for` body. A static closure appears only as the argument of `T.construct` or `T.makeCase`, which run its instances once each, in field order, and it is checked as that sequence of bodies, unrolled: an instance names the enclosing function's places as the body of a `static for` there would, so it may move out of one that no later instance uses, as `T.construct { static field in consume old[field] }` does with each field of an owned `old` ([above](#reflection-and-access-control)):

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

**`T.construct` calls `T`'s primary initializer with every field, in header order, and runs no secondary `init`** ([04](04-types.md#initializers)), so the use site must be able to call it. `T.isConstructible` (`const`) says whether it can. It is true only for a struct with a primary initializer, an imported C struct's included ([08](08-c-interop.md#structs-unions-and-enums)), or a tuple type, and even then false when the type:

- is marked `@opaque`;
- has stored fields the use site can't see (`private` ones, without `@reflect(private)`);
- has an `unsafe` stored field, or an `unsafe` primary initializer, and the use isn't inside `unsafe`, since `T.construct` would call it with no `unsafe` written ([10](10-errors-and-safety.md#unsafe-code));
- has a primary initializer the use site can't call: a `private init` one, from another module, whatever `@reflect(private)` shows. The private fields `@reflect(private)` shows count as `public` here, so they don't stop the call.

`T.makeCase` does the same for one enum case's payload, and applies to every case of an enum reflection can see into, since a case and its payload are as visible as the enum.

### Tuples, field lists, and queries

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
    for (var t, v) in zip(&ts, vs) { t.position += v.linear * dt }
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

**Tuples are reflected like structs.** A tuple type's elements are its `T.fields`, so generic code can take a tuple of types (`Archetype<(Transform, Velocity)>`) and `static for` over it.

**Field-list projections.** `value[fields: (f1, f2, …)]` projects several fields of one value at once, as a tuple of places.

- **Distinct fields.** The fields must be distinct `const` field descriptors, checked at instantiation. Distinct stored fields of a struct or tuple never overlap ([01](01-values-and-ownership.md#which-places-overlap)), except those the next bullet names.
- **Overlapping members are rejected** at instantiation: two members of a union type (`T.isUnion`), which are all one place, and two imported bitfields in the same C memory location ([01](01-values-and-ownership.md#which-places-overlap)).
- **Mixed binding kinds.** Each element of the pattern has its own binding kind: for a `var row: Row`, `let (t, var v) = &row[fields: (tf, vf)]` borrows the `Transform` shared and the `Velocity` exclusively.
- **`SoA`.** `s[fields:]` on an `SoA` `s` returns a tuple of its columns, each in the kind of its pattern element ([04](04-types.md#struct-of-arrays-soat)).

### Enumerating a module's types

A registry of every component type is a `const` built from a module's list of types:

```swift
const componentTypes: [_ of TypeInfo] = Module("gameplay").types
    .filter { $0.conforms(Component.self) }
    .map { typeInfo($0.self) }                        // a const table in read-only data
```

**`Module.current.types` and `Module("gameplay").types` are compile-time lists of a module's type declarations, usable in `static for` and in `const` evaluation. A module can list its own types and those of the modules it imports.**

- **What a module's list holds.** Its type declarations, top-level and nested, generated ones included, that neither have generic parameters nor lie inside a generic type or a function, in source order ([below](#what-a-build-declares)), and, for another module, only its `public` ones. Each element names one type, usable as a type, as `field.type` is, so `$0.self` is its type value ([05](05-protocols-generics-and-closures.md#protocols-and-generics)). `Module("gameplay")` takes the name the build declares for the module, never an `import … as` name.
- **Compile-time lists.** `T.fields`, `T.cases`, a case's `payload`, a module's `types` and `declaredTypes`, a `const` inline array or `List`, and a range of `const` integers are compile-time lists; a tuple's element types are listed by its `T.fields` ([above](#tuples-field-lists-and-queries)). They support `filter`, `map`, `contains` and `count` in `const` evaluation, with closures whose parameter is a list element, each instantiated once per element, as a static closure is ([above](#constructing-values-reflectively)), without being marked `static`, since the elements may differ in type. `filter` and `map` give compile-time lists, which a `const` converts to an inline array or a `List` of their element type.
- **Only imported lists and a module's declared types drive generation.** A module's own `types` list includes the types it generates, so no declaration may be generated from it, directly or through a `const`. `Module.current.declaredTypes` lists, in the same order, only those declared outside any `static if` or `static for`, so it may drive generation under the rule for the facts generation reads ([below](#generation-runs-in-dependency-order)): an `enum AnyEvent` can have a case per declared type that conforms to `Event`, as long as no case changes which of them do. `Module.current.types` may be read in function bodies, and in `const`s that no generating `static for` or `static if` reads, so `gameplay` could build the registry above from its own list ([below](#generation-runs-in-dependency-order)).

## Generating declarations

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

**`static if` and `static for` work where declarations go, in a struct's header, in the body of a struct, enum, union or extension, never a protocol, and at a file's top level, and generate whatever may appear there:**

- in a struct's header, stored fields ([04](04-types.md#structs));
- in such a body, any member ([12](12-grammar.md#files-and-declarations)): computed properties, a union's stored members, constants, methods, initializers, subscripts, nested types and type aliases, an enum's cases, and a `deinit`, which is still the type's only one;
- at the top level, any declaration ([12](12-grammar.md#files-and-declarations)): structs, unions, enums, protocols and type aliases; functions and `task` functions; constants; global `let`s and `var`s, `@threadlocal var`s included; extensions; and `extern c` blocks and `extern c func` declarations. A top-level `static if` can also include or exclude `import` statements, `import c` ones included ([above](#static-if-and-conditional-compilation)).

### Computed names

```swift
struct Merged<A, B>(                                      // Merged<Enemy, Player> is an error if both have an 'hp'
    static for f in A.fields { var \(f.name): f.type },
    static for f in B.fields { var \(f.name): f.type },
)
```

A generated declaration needs a name that comes from the element it was made for. **`\(e)` stands for the identifier that `e`, a `const` string, spells.** It may appear only where [12](12-grammar.md#files-and-declarations) allows, and the string must be a valid identifier, so `Columns<(Transform, Velocity)>` is an error: a tuple element's `field.name` is its position, `0`. Generated declarations that end up with the same name conflict exactly as written ones would, so two stored fields of one name are a compile error, as in `Merged` above, and functions may overload ([05](05-protocols-generics-and-closures.md#functions-and-closures)).

### Generated declarations are ordinary declarations

**Every rule treats generated declarations as if they were written out**: layout, access control, conformances, exclusivity, moves and partial moves, per-field dependency sets, destruction order and reflection. So the generated stored fields of one value are disjoint places ([01](01-values-and-ownership.md#which-places-overlap)), and `Columns<Particle>.fields` lists them:

```swift
struct Particle(var pos: Vec3, var vel: Vec3)

var columns = Columns<Particle>()                         // fields: pos: List<Vec3>, vel: List<Vec3>
step(&columns.pos, columns.vel.span, dt)                  // two fields of one value: disjoint, as if written out
```

### Generated members are checked per instantiation

**A type whose header or body generates declarations from its type parameters has members that depend on its type arguments, so each instantiation is checked on its own, as a `static for` body is ([05](05-protocols-generics-and-closures.md#protocols-and-generics)).** Concrete code names the members directly: `delta.hp`, `columns.pos`. Generic code over `Delta<T>` reaches them through reflection or a computed name, as `diff` does, and an error there is reported at the instantiation. Generic code that uses none of this is still checked once, at its definition.

**Generic code sees such a type at its safe bound.** Whatever its generated members could change, generic code assumes they do:

- **When they may include a `deinit` or a stored field**, it may have a `deinit` that isn't `PlainDeinit`, at any depth, so there it may be move-only, destroying it counts as a use ([02](02-views-and-dependencies.md#when-destroying-a-value-counts-as-using-it)), nothing moves out of it ([01](01-values-and-ownership.md#what-can-be-moved-from)), and it isn't `Pod` or `TrivialFree`.
- **When they may include a stored field**, that field may be of any type, so it may be scoped, as a type parameter may ([02](02-views-and-dependencies.md#generic-code-and-scoped)), and it isn't sealed, shallow, `Frozen` or `Sendable` either.
- **When they may include an enum case**, a `when` over it ends in `else`.

A `where` clause that states a property, such as `where Res<T>: Copyable`, lets the code rely on it, and each caller's type arguments must meet it.

### Generation runs in dependency order

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

- **Module lists.** Only imported modules' lists, and a module's own `declaredTypes`, drive generation ([above](#enumerating-a-modules-types)).
- **Fields, cases and other facts.** A list of fields or cases is complete once every member it depends on is. Generation is a cycle, and a compile error, when a declaration that any `static if` or `static for` generates, directly or through other generated declarations or the `const`s they feed, could change a list that a `static for` iterates or a fact that a `static if` or `static for` reads: a conformance, whether a type is copyable, or its layout. The declaration may be a member, a top-level declaration, an extension or a conformance, and the test is on what it could change, whether or not its branch is taken. `static if Echo.conforms(Copyable.self) { deinit { … } }` inside `Echo` is one, and so is `static if !Foo.conforms(Printable.self) { extension Foo: Printable { … } }`. A type that only holds a type generated from it is fine: `Delta<Node>` iterates the fields `Node` declares.

## Attributes

Reflection gives a field's name and type, but not that the field is a cache a serializer should skip, what range and tooltip an editor's slider shows, or whether replication sends it. The type's author states such facts as attributes:

```swift
struct Bounds(let min: Float, let max: Float): Attribute {
    init(_ min: Float, _ max: Float) { self.init(min: copy min, max: copy max) }   // the parameters are borrowed
}
struct Tooltip(let text: StaticString): Attribute
struct Transient: Attribute {}     // skipped by serializers
struct Replicated(var reliable: Bool = false): Attribute

struct Enemy(
    @Bounds(0, 500) @Tooltip(text: "Hit points") var hp: Float = 100,
    @Replicated var pos: Vec3,
    @Transient var cachedPath: List<Vec3> = [],
)
```

**An attribute is any struct that conforms to `Attribute`. Its arguments must be `const`**, and its value freezable, since `typeInfo` puts it in static data ([below](#runtime-type-info)) as a `const` that reaches run-time code is frozen ([above](#consts-that-reach-run-time)). Reflection reads it on a field, a type or an enum case ([table](#what-reflection-can-read)). An editor's inspector, for example:

```swift
func inspect<T>(_ value: mutable T, in ui: mutable Inspector) {
    static for f in T.fields where f.has(Bounds.self) {
        const b = f.attribute(Bounds.self)!                // this field's @Bounds, known at compile time
        ui.slider(f.name, &value[f], min: b.min, max: b.max)
    }
}
```

- **Where they go.** Reflection reads a user attribute only on a field, a type or an enum case, so one on any other declaration is a compile error. A declaration may take one attribute type several times, as in `@Requires(Physics.self) @Requires(Render.self)`, which `attributes(Requires.self)` lists.
- **Built-in attributes** are reserved names: `@align`, `@c`, `@checks`, `@converts`, `@export`, `@guard`, `@inline`, `@noalloc`, `@nonexhaustive`, `@opaque`, `@packed`, `@pod`, `@reflect`, `@sendable` and `@threadlocal`. A toolchain may add attributes of its own that change no program's meaning.

## Runtime type info

For code that walks types **at run time**, `typeInfo(T.self)` materializes a `TypeInfo`, a read-only record in static data built from the same reflection and attributes, as a module other than `T`'s sees them ([above](#reflection-and-access-control)), so a type has one record wherever it is made:

```swift
public struct TypeInfo private init(    // Frozen, derived: every field is Frozen
    public let id: UInt64,
    public let name: StaticString,
    public let size: Int,
    public let alignment: Int,
    public let fields: StaticSpan<FieldInfo>,  // name, offset, type id, attributes
    public let cases: StaticSpan<CaseInfo>,    // name, tag, payload fields, attributes
    public let attributes: StaticSpan<AttributeInfo>,  // each: the attribute type's TypeInfo, and its value
)

let enemyInfo = typeInfo(Enemy.self)    // a global let: a TypeInfo can be kept anywhere

func showFields(_ info: TypeInfo, in ui: mutable Inspector) {   // one function for every type, at run time
    for f in info.fields {
        ui.label(f.name)
        for a in f.attributes { if let t = a[as: Tooltip.self] { ui.hint(t.text) } }
    }
}
```

**Only `typeInfo` builds a `TypeInfo`, `FieldInfo`, `CaseInfo` or `AttributeInfo`**, whose initializers are private to the module that declares them, so each record describes its type truthfully. **An `AttributeInfo` gives its value only as the attribute's own type**, never as bytes, which would include its padding: `a[as: Tooltip.self]` is an optional projection of the `Tooltip` it holds, `nil` for another attribute type.

### `StaticSpan`: views of immortal data

**`StaticSpan<T>` is a view of immortal read-only data: the program image, or runtime tables that are never freed. So unlike `Span` it is unscoped.**

- Its `T` is `~Scoped`, as an unscoped type's contents are ([02](02-views-and-dependencies.md#generic-code-and-scoped)), and has only values that could be frozen ([above](#consts-that-reach-run-time)): it is `Frozen` and `TrivialFree`, and holds no `StablePool`, weak pointer or weak link. So no safe code writes what a `StaticSpan` views, as it could through an `Atomic`, a `Shared` count or a pin count.
- Only the compiler and the runtime create `StaticSpan`s safely. `unsafe` code that makes one, and C that passes one to Rayo, promise the same of its data ([08](08-c-interop.md#what-c-must-uphold)).
- The data is never written either, so `StaticSpan` is `Frozen`, through the `unsafe Frozen` conformance the language declares for it ([06](06-memory-and-allocators.md#frozen-types-with-no-interior-mutability)).

## What a build declares

**A build declares the settings that change what code means:**

- the modules, in a list whose order startup follows where imports leave it open, each with its name, unique in the build, and its source files, in an order that sets the source order of its declarations ([07](07-concurrency.md#initialization-at-startup)). A generated declaration stands, in that order, where the `static if` or `static for` that generates it does, a `static for`'s in element order;
- which of the modules form the prelude ([11](11-compilation-model.md#modules-and-names)), and whether the build is a program, with the module whose `main` it runs ([07](07-concurrency.md#shutdown)), or a library that a C program embeds ([08](08-c-interop.md#embedding-rayo-in-a-c-program));
- for each module, whether it is `@safe` ([10](10-errors-and-safety.md#safe-modules)), and its diagnostic check settings ([10](10-errors-and-safety.md#choosing-checks-for-a-module-or-a-scope));
- the build profile and the target, which `target` exposes ([above](#static-if-and-conditional-compilation));
- the flags that `target.flag` reads, each a `const` `Bool`, `Int` or `StaticString`;
- for each `import c`, the header it reads and each header its config block names, and for it and each `extern c` block, the preprocessor definitions its C is read with ([08](08-c-interop.md#importing-headers)).