# Attributes, runtime data and build inputs

[09 · Compile time](../09-compile-time.md)

## Attributes

Reflection gives a field's name and type, but not that the field is a cache a serializer should skip, what range and tooltip an editor's slider shows, or whether replication sends it. The type's author states such facts as attributes:

```swift
struct Bounds(let min: Float, let max: Float): Attribute {
    init(_ min: Float, _ max: Float) { self.init(min: copy min, max: copy max) }   // the parameters are borrowed
}
struct Tooltip(let text: static StringView): Attribute
struct Transient: Attribute {}     // skipped by serializers
struct Replicated(var reliable: Bool = false): Attribute

struct Enemy(
    @Bounds(0, 500) @Tooltip(text: "Hit points") var hp: Float = 100,
    @Replicated var pos: Vec3,
    @Transient var cachedPath: List<Vec3> = alloc [],
)
```

**An attribute is any struct that conforms to `Attribute`, and its arguments must be `const`.** Its value must be freezable, since `typeInfo` puts it in read-only data ([below](#runtime-type-info)) the way a `const` that reaches run time is frozen ([Consts that reach run time](constants-and-conditions.md#consts-that-reach-run-time)). Reflection reads an attribute on a field, a type or an enum case ([What reflection can read](reflection.md#what-reflection-can-read)). An editor's inspector, for example:

```swift
func inspect<T>(_ value: mutable T, in ui: mutable Inspector) {
    static for f in T.fields where f.has(Bounds.self) {
        const b = f.attribute(Bounds.self)!                // this field's @Bounds, known at compile time
        ui.slider(f.name, &value[f], min: b.min, max: b.max)
    }
}
```

**Reflection reads a user attribute only on a field, a type or an enum case, so one on any other declaration is a compile error.** A declaration may take one attribute type several times, as a type could take both `@Requires(Physics.self)` and `@Requires(Render.self)`, which `attributes(Requires.self)` lists.

**The built-in attributes are reserved names**: `@align`, `@c`, `@checks`, `@converts`, `@export`, `@guard`, `@inline`, `@noalloc`, `@nonexhaustive`, `@opaque`, `@packed`, `@pod`, `@reflect`, `@sendable` and `@threadlocal`. A toolchain may add attributes of its own that change no program's meaning.

## Runtime type info

For code that walks types **at run time**, `typeInfo(T.self)` returns a `TypeInfo`, a record in read-only data. The record is built from the same reflection and attributes, as a module other than `T`'s sees them ([Reflection and access control](reflection.md#reflection-and-access-control)), so a type has one record wherever it is made:

```swift
public struct TypeInfo private init(    // Frozen, derived: every field is Frozen
    public let id: UInt64,
    public let name: static StringView,
    public let size: Int,
    public let alignment: Int,
    public let fields: static Span<FieldInfo>,  // name, offset, type id, attributes
    public let cases: static Span<CaseInfo>,    // name, tag, payload fields, attributes
    public let attributes: static Span<AttributeInfo>,  // each: the attribute type's TypeInfo, and its value
)

let enemyInfo = typeInfo(Enemy.self)    // a global let: a TypeInfo can be kept anywhere

func showFields(_ info: TypeInfo, in ui: mutable Inspector) {   // one function for every type, at run time
    for f in info.fields {
        ui.label(f.name)
        for a in f.attributes { if let t = a[as: Tooltip.self] { ui.hint(t.text) } }
    }
}
```

**Only `typeInfo` builds a `TypeInfo`, `FieldInfo`, `CaseInfo` or `AttributeInfo`**, whose initializers are private to the module that declares them, so each record describes its type truthfully.

**An `AttributeInfo` gives its value only as the attribute's own type**, never as bytes, which would include its padding, and padding bytes are uninitialized ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)). `a[as: Tooltip.self]` is an optional place property that hands out the `Tooltip` it holds, or `nil` for another attribute type ([02](../02-views-and-dependencies/place-and-value-properties.md#optional-places-and-tuples-of-places)).

### Static views: views of immortal data

**A view of immortal data needn't stay in a scope, so it can be stored anywhere.** **Immortal data** is memory that is never freed, and that nothing writes once a value names it: the program image, or runtime tables. A view needn't be scoped when nothing can free its memory while it reads it ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)). The qualifier `static` marks such a view in its type:

```swift
let title: static StringView = "Rayo"                        // a literal is a static view
let modes: [2 of static StringView] = ["easy", "hard"]       // so an array of literals can be a global
struct Hint(let text: static StringView, let delay: Float)   // and a plain struct can store one

func show(_ hint: Hint) {
    let shown: StringView = hint.text                        // fine: it converts to the plain view
    let kept: static StringView = shown                      // error: a plain view never converts to a static one
}
```

**A static view is a `static StringView` or a `static Span<T>`, a shared view that views only immortal data, so unlike the plain view it is unscoped.** It is copyable, as the plain view is. Only these two views take `static`. Its conversion to the plain view is one of the implicit conversions ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)). It meets `where return borrows static`, since it depends on nothing, while a view of a global `let` borrows static storage but isn't a static view ([02](../02-views-and-dependencies/dependency-lifetimes.md#precise-dependencies-opt-in)). A range of a static view, such as `title[0..<2]`, is a static view too, since it views the same immortal data.

These rules keep a static view's data immortal, or follow from it:

- **Its elements.** A `static Span<T>`'s `T` is `~Scoped`, as an unscoped type's contents are ([02](../02-views-and-dependencies/scoped-values.md#generic-code-and-scoped)), and has only values that could be frozen ([Consts that reach run time](constants-and-conditions.md#consts-that-reach-run-time)): it is `Frozen` and `TrivialFree`, and holds no `StablePool`, weak pointer or weak link. So no safe code writes the data behind a static view, as it could through an `Atomic`, a `Shared` count or a pin count.
- **Who makes one.** Only the compiler and the runtime create static views safely, such as a literal, a frozen `const`'s `.view` and `.span`, a `Name`'s text, and the names and lists that reflection and `typeInfo` give. `unsafe` code that makes one, and C that passes one to Rayo, promise the same of its data ([08](../08-c-interop/c-contract-and-embedding.md#what-c-must-uphold)).
- **Its own conformance.** The data is never written either, so a static view is `Frozen`, through the `unsafe Frozen` conformance the language declares for it ([06](../06-memory-and-allocators/owning-values.md#frozen-types-with-no-interior-mutability)).

## What a build declares

**A build declares the settings that change what code means.** Two builds of one program with the same build declarations disagree about a safe program only where the language leaves it open ([11](../11-compilation-model.md#what-the-language-leaves-open)). A build declares these:

- **Modules.** The modules, in a list whose order startup follows where imports leave it open, each with its name, unique in the build, and its source files. The files' order sets the source order of the module's declarations ([07](../07-concurrency/global-state.md#initialization-at-startup)). A generated declaration stands, in that order, where the `static if` or `static for` that generates it does, a `static for`'s in element order.
- **The prelude.** Which of the modules form the prelude ([11](../11-compilation-model.md#the-prelude)).
- **Program or library.** Whether the build is a program, with the module whose `main` it runs ([07](../07-concurrency/global-state.md#shutdown)), or a library that a C program embeds ([08](../08-c-interop/c-contract-and-embedding.md#embedding-rayo-in-a-c-program)). Code without a `main` can only be a library, since a program starts at its `main`. The compiler checks it as it checks a program's code, and rejects a build of it as a program.
- **Safety and checks.** For each module, whether it is `@safe` ([10](../10-errors-and-safety/unsafe-code.md#safe-modules)), and its diagnostic check settings ([10](../10-errors-and-safety/checks-and-build-modes.md#choosing-checks-for-a-module-or-a-scope)).
- **Mode and target.** The build mode and the target, which `target` exposes ([`static if` and conditional compilation](constants-and-conditions.md#static-if-and-conditional-compilation)).
- **Panic strategy.** Whether a panic unwinds, the default, or aborts the program ([10](../10-errors-and-safety/panics.md#panic-strategy)).
- **Flags.** The flags that `target.flag` reads, each a `const` `Bool`, `Int` or `static StringView`.
- **Seed bytes.** For a program on a platform with no source of randomness, the bytes startup takes as the process seed, without which the build fails ([08](../08-c-interop/c-contract-and-embedding.md#what-the-runtime-needs-from-the-platform)).
- **C headers.** For each `import c`, the header it reads and each header its config block names. For each `import c` and each `extern c` block, the preprocessor definitions its C is read with, so no other import's macros reach an `import c` ([08](../08-c-interop/imports-and-inline-c.md#importing-headers)).
