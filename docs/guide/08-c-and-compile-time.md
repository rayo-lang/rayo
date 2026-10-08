# 8 · C and compile time

The same game now runs on a console whose SDK is a C library with a header, `platform.h`. Through it you open a window, poll the gamepads and hear from the audio thread. You also want save games without rewriting the saver each time `Enemy` gains a field. Its current target and cached path should not be saved, so `@Transient` marks those fields to skip:

```swift
import c "platform.h" as plat where prefix: "platform_"   // the SDK's C API, as Rayo declarations

struct Enemy(
    var pos: Vec3,
    var vel: Vec3 = .zero,
    var hp: Float = 100,
    @Transient var target: Handle<Player>? = nil,       // a live player link, not part of a save game
    @Transient var path: List<Vec3> = [],                 // a cache: rebuilt after loading, never saved
)

unsafe plat.window_create(1280, 720, "Rayo".cString)      // a direct call into C, which you vouch for
save(boss.value, into: &file)                             // writes pos, vel and hp, found by reflection
```

Rayo calls C directly, with no glue code. Where C can't promise something, you promise it yourself, and Rayo marks that code `unsafe`. You write `save` once for every type, with code the compiler runs while it builds your program: `const`, `static if`, and reflection over a type's fields.

## Importing a C header

```c
#define PLATFORM_MAX_PADS 4
typedef struct platform_window platform_window;      /* declared, never defined */
typedef struct platform_pad { float left_stick[2]; float right_stick[2]; uint32_t buttons; bool connected; } platform_pad;
platform_window* platform_window_create(int32_t width, int32_t height, const char* title);
bool platform_poll_pad(int32_t index, platform_pad* out);
```

`import c` reads the header and makes its declarations available in a Rayo module ([08](../spec/08-c-interop/imports-and-inline-c.md#importing-headers)). The module would be named `platform` after the file; `as plat` gives it a shorter name. The import also strips the `platform_` prefix where it matches, so the C name `platform_poll_pad` becomes `plat.poll_pad`.

Rayo maps each C declaration to the closest Rayo form ([08](../spec/08-c-interop/imports-and-inline-c.md#what-imports-as-what)). From the part of `platform.h` above, you get:

- `plat.PLATFORM_MAX_PADS` is a `const` `CInt` of 4. Prefix stripping is case-sensitive, so the macro keeps its name.
- `plat.window` is an `@opaque` struct, which Rayo code uses only through a pointer, `*plat.window`.
- `plat.pad` is a `@c struct` with C's layout, whose `left_stick` is a `[2 of Float]`. `plat.pad()` makes one of all zeros.
- `plat.window_create` is an `unsafe func` taking `(Int32, Int32, *CChar?)` and returning a `*plat.window?`.
- `plat.poll_pad` is an `unsafe func` taking `(Int32, *plat.pad?)` and returning a `Bool`.

A C pointer imports as a raw pointer that may be null, `*T?`, unless the header marks it `_Nonnull` ([below](#raw-pointers)). C's `int` and `char` become `CInt` and `CChar`, whose size and signedness follow the target. A C enum is **open**: it may hold any value of its underlying type, so a `when` over it needs an `else` ([08](../spec/08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)).

Function-like macros do not import. You can wrap one in a C function inside an `extern c` block ([08](../spec/08-c-interop/imports-and-inline-c.md#inline-c)). Importing the header itself adds no implementation to your program; the SDK's code comes from linking its library.

## Calling C: `unsafe`

```swift
func now() -> Double { plat.time_seconds() }            // error: a call into C needs 'unsafe'
func now() -> Double { unsafe plat.time_seconds() }     // 'unsafe' before an expression covers just it

func readPad(_ index: Int32) -> plat.pad? {
    precondition(index >= 0 && index < plat.PLATFORM_MAX_PADS)   // C wouldn't check it
    var raw = plat.pad()                                        // the C struct, all zeros
    let ok = unsafe plat.poll_pad(index, ptr(to: &raw))         // C fills it in through the pointer
    guard ok && raw.connected else { return nil }
    return raw
}
```

The header tells Rayo the function's parameter types, but cannot say whether its pointers remain valid or how many elements a buffer holds. Every imported C function therefore needs `unsafe` at the call ([08](../spec/08-c-interop/imports-and-inline-c.md#calling-imported-functions)). In `now`, it covers one expression; around several operations, write `unsafe { … }` ([10](../spec/10-errors-and-safety/unsafe-code.md#unsafe-code)).

`unsafe` lets you perform operations the compiler cannot verify. It does not disable ordinary checks: a list index inside the block still gets a bounds check. In return, you promise that every access through a raw pointer ([10](../spec/10-errors-and-safety/unsafe-code.md#what-unsafe-code-upholds)):

- stays inside the allocation it points into;
- is aligned for its type;
- finds a valid value there, such as a `Bool` that is 0 or 1;
- reads and writes only where safe code could, so it breaks no live borrow.

Breaking that promise is undefined behavior, as in C. Code that makes such promises is **unsafe code**. `readPad` keeps the promise close to the call: it checks the index first, supplies a valid `pad`, and returns an ordinary optional. Callers can use the wrapper without writing `unsafe`.

**An `unsafe func` is one whose callers need `unsafe`.** Its body isn't an `unsafe` block: it writes `unsafe` where it needs it, as any function does.

**A build can declare a module `@safe`, and everything the compiler takes on trust is then an error in it** ([10](../spec/10-errors-and-safety/unsafe-code.md#safe-modules)). That covers `unsafe` code, `extern c` code, and unverified promises such as `@export` ([below](#calling-rayo-from-c-export)).

**A `@safe` module can still import a C header**, for its types and constants. It can also call the safe wrappers that another module builds with `unsafe`.

## Raw pointers

```swift
var raw = plat.pad()
let p = unsafe ptr(to: &raw)                    // the address of 'raw': a *plat.pad
let address = UInt(bitPattern: p)               // safe: a pointer turned into an integer
unsafe {
    p.pointee.buttons = 0                       // the plat.pad that 'p' points at
    let bytes = p.cast(to: UInt8.self)          // the same address, as a *UInt8
    let third = copy bytes[2]                   // reads (bytes + 2).pointee, which nothing bounds-checks
}
```

**`*T` is a raw pointer that is never null, and `*T?` one that may be** ([10](../spec/10-errors-and-safety/unsafe-code.md#raw-pointers)). `*T?` has a C pointer's size, since its `nil` is the null pointer.

**Rayo has no `const` pointer**, so an import drops C's `const`.

**`ptr(to:)` gives a place's address, and needs `unsafe`.**

**`p.pointee` is the value `p` points at, and `p[i]` is `(p + i).pointee`.** Each needs `unsafe`, and no run-time check keeps it in bounds.

**`*Void` points at memory of no stated type.** `p.cast(to: U.self)` converts between pointer types, so you can read such memory as bytes.

**Turning a pointer into an integer is safe, and turning an integer into a pointer is `unsafe`.**

**A raw pointer borrows nothing**, so the compiler won't stop you from using one after its place is gone. Using it only while the place lives is part of what `unsafe` promises.

**Accessing a bare global `var`, or a variable a C header declares, needs `unsafe` too**, since every thread can reach it ([10](../spec/10-errors-and-safety/unsafe-code.md#what-needs-unsafe)).

## Passing memory to C

```swift
func upload(_ samples: Span<Float>) {                   // safe: a span always knows its count
    unsafe { plat.upload(samples.baseAddress, UInt(samples.count)) }
}
func log(_ level: Int32, _ text: StringView) {
    unsafe { plat.log(level, text.cchars.baseAddress, UInt(text.cchars.count)) }
}
```

**A span hands C a pointer and a count.** Its `baseAddress` is an `unsafe` field, so reading it needs `unsafe` ([10](../spec/10-errors-and-safety/unsafe-code.md#what-needs-unsafe)). With that `unsafe`, you promise, among other things, that C only reads there, at most `count` elements, and none after the call returns.

**A string literal passes to C as a C string, at no cost.** A `StaticString`, such as a literal, is followed by a NUL, so `"Rayo".cString` is a `const char*` ([04](../spec/04-types/collections.md#strings)).

**Other strings needn't end in a NUL, so you pass them with a length.** `s.cchars` views any string's bytes as a `Span<CChar>`, for C functions that take a pointer and a length.

### When C keeps the pointer

```swift
// audio.h, imported as 'audio' where prefix: "audio_":
//     typedef struct audio_emitter { float gain; float pos[3]; } audio_emitter;
//     void audio_track(audio_emitter* e);      keeps 'e', and reads it on every update
struct Voice(var pin: Pin<audio.emitter>)          // holds the pin while C uses the address
let voice = Voice(pin: emitters.pin(h)!)           // emitters: a StablePool<audio.emitter>
unsafe { audio.track(voice.pin.address) }          // valid for as long as 'voice' keeps the pin
```

**When C keeps a pointer past the call, hand it the address a pin holds.** A pin keeps a `StablePool` element alive, and at its address, for as long as the pin lives ([Handles and objects](05-handles-and-objects.md)).

**`pin.address` is an `unsafe` field of type `*T`.** A pin is unscoped, so you can keep it in a field until C is done with the address.

## Callbacks: `@c func`

```swift
let audioEvents = MpscQueue<AudioEvent>(capacity: 256)  // a global queue any thread may push to

@c func onAudioEvent(_ user: *Void?, _ event: CInt) {   // runs on the SDK's audio thread
    audioEvents.push(AudioEvent(raw: copy event))       // 'event' is borrowed, so copy it in
}

unsafe { plat.set_audio_callback(onAudioEvent, nil) }
```

**A `@c func` is a Rayo function that C can call through a function pointer** ([08](../spec/08-c-interop/calling-rayo-from-c.md#callbacks)).

**A C function-pointer type imports as a `@c` function type.** The header's `void (*)(void* user, int event)` imports as `(@c (*Void?, CInt) -> Void)?`, and a `@c func` with those parameters converts to it.

**C may call a `@c func` from any thread.** So hand what it receives to the rest of the game through something every thread may use, such as a queue ([Concurrency](07-concurrency.md)).

**Its parameters and result must have C representations** ([08](../spec/08-c-interop/calling-rayo-from-c.md#c-representations)).

**It can't throw, since C has no way to catch an error.** A panic in it stops the program, without unwinding into C.

**C never gives up what it passes through an imported callback type**, so a `@c func` with an `owned` parameter doesn't convert to one.

**Calling through a `@c` pointer needs `unsafe`**, since its type can't tell a Rayo function from a C one ([05](../spec/05-protocols-generics-and-closures/functions-and-closures.md#c-function-pointers)).

## Calling Rayo from C: `@export`

Say your studio's level editor, written in C++, asks the game whether an enemy description is valid:

```swift
@export(c) @c struct SpawnDesc(var pos: Vec3, var hp: Float)       // a C struct in the generated header
@export(c, name: "game_can_spawn") func canSpawn(_ desc: SpawnDesc) -> Bool {
    desc.hp > 0
}
```

**`@export(c)` gives a function C linkage and an unmangled name, so C and C++ code can call it** ([08](../spec/08-c-interop/calling-rayo-from-c.md#calling-rayo-from-c)).

**The build writes a C header for the module**, with every exported function and the types their signatures use.

**An exported function takes and returns only types with C representations.** Numbers, `Bool`, raw pointers and structs of them cross to C unchanged. A `Span<T>` crosses as a struct of a pointer and a count, and a `Handle` as its 64 bits.

**A struct crosses with its fields in the order Rayo lays them out in memory, and the generated header declares them in that order.** Rayo sorts a struct's fields by alignment, largest first, so no padding falls between them, and fields of equal alignment keep their declared order ([04](../spec/04-types/structs.md#structs)).

**`@c` keeps a struct's fields in the order you declare them, and checks that each has a C representation** ([04](../spec/04-types/structs.md#structs)). Use it when something outside your program fixes the layout, such as a C library's header, a file format or a network packet. Every struct that `import c` makes is a `@c struct`.

**An exported function is a plain C function.** It has no type parameters, and it can't throw.

**An exported function's parameters pass by value, whatever their conventions, except a `mutable` one, which passes as a pointer.**

**An exported name is a promise the compiler can't check.** The build fails when two objects it links define one name. But nothing checks a symbol the program loads at run time, or that every C caller uses this signature. So `@export` is an **unverified promise**, taken on trust as an `unsafe` block is ([10](../spec/10-errors-and-safety/unsafe-code.md#unverified-promises)).

## What C must uphold

**C that calls Rayo, or that Rayo calls, takes on the promises that `unsafe` Rayo code would make in its place** ([08](../spec/08-c-interop/c-contract-and-embedding.md#what-c-must-uphold)).

**C calls Rayo through a C entry, and may do so from any thread.** A **C entry** is a function C can call, such as a `@c func` or an exported function ([08](../spec/08-c-interop/calling-rayo-from-c.md#c-entries-and-threads)).

**Rayo can't check C, so C must keep these promises:**

- every value it hands Rayo is valid for its Rayo type: a `Bool` is 0 or 1, a Rayo enum holds one of its cases, and a pointer that may not be null isn't;
- it reads Rayo memory only while Rayo keeps it alive and isn't writing it, and writes it only where Rayo code with exclusive access could;
- it never frees or keeps a value that Rayo passed it borrowed;
- it never `longjmp`s over a Rayo frame or unwinds through one;
- it enters Rayo only by an ordinary call, never from a signal handler.

Breaking one is undefined behavior, as a wrong `unsafe` block is.

**Where you can't trust what C passes, take the raw form, and convert it with a checked conversion.** An exported function can take an `Int32` in place of a Rayo enum. The enum's `E(rawValue:)` then gives `nil` for a value that is no case.

## Running code at compile time: `const`

```swift
const sinTable: [1024 of Float] = makeSinTable()         // computed once, by the compiler

func makeSinTable() -> [1024 of Float] {
    var t: [1024 of Float] = .init(repeating: 0)
    for i in 0..<1024 { t[i] = sin(Float(i) / 1024 * 2 * .pi) }
    return t
}

const startTime = now()          // error: 'now' calls C, which can't run in the compiler
let startTime = now()            // fine: a global 'let' is initialized at startup
```

**A `const`'s initializer runs in the compiler, and it can call ordinary functions** ([09](../spec/09-compile-time/constants-and-conditions.md#running-code-at-compile-time-const)).

**A function needs no mark to run at compile time.** It runs there if what it executes, on the input it gets:

- calls no C function;
- accesses no global other than a `const`;
- starts, parks or wakes no thread;
- makes no volatile access, and none through a pointer made from an integer;
- reads no clock.

**A `const` whose initializer does anything else is a compile error.** A global `let` runs its initializer at startup instead.

**The compiler computes what the program would.** Code keeps the checks it has at run time, so an overflow wraps where overflow checks are off. A panic is a compile error.

**Allocation works.** The compiler has a heap of its own, so a `const` can build a `List` with `append`.

**A `const` that run-time code names is frozen into the program's read-only data** ([09](../spec/09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)), since the running program has no compile-time heap.

## `static if` and `target`

```swift
static if target.platform == .ps5 {
    import c "platform_ps5.h" as plat where prefix: "platform_"
} else {
    import c "platform.h" as plat where prefix: "platform_"
}

static if !target.hasFlag("sse4") {
    static error("needs SSE4")           // fails every build that doesn't declare the flag
}

func endFrame(_ game: Game) {
    static if target.hasFlag("editor") {
        drawGizmos(game)                 // declared only in editor builds, which declare the flag
    }
    static if game.paused { return }     // error: a 'static if' condition must be a const
}
```

**`static if` keeps or drops code at compile time, by a condition that must be `const`** ([09](../spec/09-compile-time/constants-and-conditions.md#static-if-and-conditional-compilation)).

**The branch it doesn't take is parsed, but never type-checked.** So that branch can name what exists only on another platform, or only in some builds.

**At the top level, `static if` can keep or drop declarations, and whole imports.** A condition that guards an import reads only literals, `target` and the `const`s of modules imported outside any `static if`. So which modules a file imports never depends on what an import provides.

**`target` is a `const` that describes the build.** It has, among others:

- `platform`, `arch` and `endian`;
- `mode`, which is `.debug` or `.release`;
- `flag("editor")`, a flag the build defines.

**Reading a flag the build doesn't define is a compile error.** `hasFlag("editor")` says whether the build defines it.

**`static error("…")` makes a branch a compile error with that message.**

## Reflection: `T.fields` and `static for`

```swift
func save<T>(_ value: T, into w: mutable Writer) {
    static if T.conforms(Pod.self) && T.isPaddingFree {
        w.bytes(of: value)                              // a Float or a Vec3: its bytes, as they are
    } else static if T.conforms(Serializable.self) {
        value.serialize(into: &w)                       // List, String and Map conform in std
    } else static if T.isConstructible {                // a struct whose fields this code all sees
        w.beginObject(T.name)
        static for field in T.fields where !field.has(Transient.self) {   // skip live links and caches
            w.key(field.name)
            save(value[field], into: &w)                // each copy checked with its own field's type
        }
        w.endObject()
    } else {
        static error("\(T.name) can't be saved field by field: conform it to Serializable")
    }
}
```

**Every type has metadata that code reads at compile time** ([09](../spec/09-compile-time/reflection.md#static-reflection)). Reading it is **reflection**.

**`T.fields` lists `T`'s stored fields in declaration order** ([09](../spec/09-compile-time/reflection.md#what-reflection-can-read)). Each has a `name`, a `StaticString`, and a `type`.

**`static for` repeats its body once per field, and checks each copy with that field's type.**

**`value[field]` reaches the field in place, as `value.pos` would.** Only an imported bitfield or an under-aligned field goes through a temporary.

**`T.conforms(P.self)`, `T.isPaddingFree` and `T.isConstructible` are `const` queries**, so `static if` can test them.

**In generic code, the compiler checks a `static if` branch only for the types that take it.** So `w.bytes(of:)`, which accepts only a padding-free `Pod` type, compiles in its branch. The `static error` fires only for a type that reaches the last branch.

**`Enemy` takes the third branch.** It isn't `Pod`, since its `List` owns memory, and it doesn't conform to `Serializable`. The loop visits `pos`, `vel` and `hp`, skipping the `@Transient` target and path. Those three fields save their bytes, since `Vec3` and `Float` are padding-free `Pod` types.

**`T.isConstructible` is true only where this code sees every field of `T`.** So a type with fields hidden from `save`, which is neither plain data nor `Serializable`, stops at the `static error` instead of saving part of its state.

**A Rayo enum stops there too.** The spec's serializer adds a branch that walks `T.cases` ([09](../spec/09-compile-time/reflection.md#static-reflection)).

**Reflection sees only what the code that uses it could name** ([09](../spec/09-compile-time/reflection.md#reflection-and-access-control)). In `Enemy`'s own module, `Enemy.fields` lists every field. In another module, such as a shared save library, it lists only the `public` ones, so there `save` stops at its `static error`.

**`@reflect(private)` on a type shows other modules all its fields.** It grants nothing else: other modules still can't name a field that isn't `public`.

## Attributes

```swift
struct Transient: Attribute {}                          // a field that save skips
struct Bounds(let min: Float, let max: Float): Attribute {
    init(_ min: Float, _ max: Float) { self.init(min: copy min, max: copy max) }   // the parameters are borrowed
}

@reflect(private)
struct Enemy(
    var pos: Vec3,
    var vel: Vec3 = .zero,
    @Bounds(0, 5000) var hp: Float = 100,
    @Transient var target: Handle<Player>? = nil,
    @Transient var path: List<Vec3> = [],
)

func inspect<T>(_ value: mutable T, in ui: mutable Inspector) {
    static for f in T.fields where f.has(Bounds.self) {
        const b = f.attribute(Bounds.self)!             // this field's @Bounds, known at compile time
        ui.slider(f.name, &value[f], min: b.min, max: b.max)
    }
}
```

**An attribute is a struct that conforms to `Attribute`** ([09](../spec/09-compile-time/attributes-and-runtime-data.md#attributes)). Reflection gives a field's name and type, but not that the field is a cache to skip, or the range an editor's slider shows. Attributes let the type's author say so. The `save` function above skips `target` and `path` because both carry `@Transient`.

**Reflection reads the attributes on a field.** `f.has(A.self)` says whether the field carries an `A`, and `f.attribute(A.self)` gives its value, or `nil`.

**An attribute's arguments must be `const`:**

```swift
let maxHp: Float = 500
struct Boss(@Bounds(0, maxHp) var hp: Float = 100)      // error: 'maxHp' is a global 'let', not a const

const maxHp: Float = 500
struct Boss(@Bounds(0, maxHp) var hp: Float = 100)      // fine
```

**An attribute of your own goes only on a field, a type or an enum case**, since reflection reads it only there. Anywhere else, it's a compile error.

**The built-in attributes, such as `@c`, `@export` and `@reflect`, are reserved names.**

## In the spec

- [08 C interop](../spec/08-c-interop.md): importing headers and what each C declaration imports as, C representations, callbacks, `@export`, and everything C must uphold.
- [10 Unsafe code](../spec/10-errors-and-safety/unsafe-code.md#unsafe-code): what needs `unsafe`, raw pointers, the full rules `unsafe` code keeps, and `@safe` modules.
- [05 C function pointers](../spec/05-protocols-generics-and-closures/functions-and-closures.md#c-function-pointers): which functions convert to a `@c` type, and when.
- [03 Pinning for C](../spec/03-handles-and-objects.md#pinning-for-c): what a pin guarantees while C holds its address.
- [09 Compile time](../spec/09-compile-time.md): `const` evaluation and freezing, `static if`, everything reflection reads, attributes, generated declarations, building values with `T.construct`, and `typeInfo` at run time.
