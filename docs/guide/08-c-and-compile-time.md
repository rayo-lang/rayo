# 8 · C and compile time

Your game runs on a console whose SDK is a C library with a header, `platform.h`. Through it you open a window, poll the gamepads and hear from the audio thread. You also want save games, without a hand-written writer for `Enemy` that falls behind each time `Enemy` gains a field.

```swift
import c "platform.h" as plat where prefix: "platform_"   // the SDK's C API, as Rayo declarations

struct Enemy(
    var pos: Vec3,
    var vel: Vec3 = .zero,
    var hp: Float = 100,
    @Transient var path: List<Vec3> = [],                 // a cache: rebuilt after loading, never saved
)

unsafe plat.window_create(1280, 720, "Rayo".cString)      // a direct call into C, which you vouch for
save(boss, into: &file)                                   // writes pos, vel and hp, found by reflection
```

Calling C takes no glue code. The work is in saying what C can't promise, and Rayo marks that code `unsafe`. Writing `save` once for every type takes code that runs in the compiler: `const`, `static if` and reflection over a type's fields. This chapter covers C first, then compile time.

## Importing a C header

**`import c` reads a C header and gives each declaration it can map a Rayo form** ([08](../spec/08-c-interop.md#importing-headers)):

```swift
import c "platform.h"                                     // declarations land in module 'platform'
import c "platform.h" as plat where prefix: "platform_"   // module 'plat': platform_poll_pad is plat.poll_pad
```

**Each C declaration Rayo can map imports as the Rayo declaration closest to it** ([08](../spec/08-c-interop.md#what-imports-as-what)). Take this part of `platform.h`:

```c
#define PLATFORM_MAX_PADS 4
typedef struct platform_window platform_window;      /* declared, never defined */
typedef struct platform_pad { float left_stick[2]; float right_stick[2]; uint32_t buttons; bool connected; } platform_pad;
platform_window* platform_window_create(int32_t width, int32_t height, const char* title);
bool platform_poll_pad(int32_t index, platform_pad* out);
```

Rayo sees these:

- `plat.PLATFORM_MAX_PADS` is a `const` `CInt` of 4. Prefix stripping is case-sensitive, so the macro keeps its name.
- `plat.window` is an `@opaque` struct, which Rayo code uses only through a pointer, `*plat.window`.
- `plat.pad` is a `@c struct` with C's layout, whose `left_stick` is a `[2 of Float]`. `plat.pad()` makes one of all zeros.
- `plat.window_create` is an `unsafe func` taking `(Int32, Int32, *CChar?)` and returning a `*plat.window?`.
- `plat.poll_pad` is an `unsafe func` taking `(Int32, *plat.pad?)` and returning a `Bool`.

A C pointer imports as a nullable raw pointer, `*T?`, unless the header marks it `_Nonnull`. C's `int` and `char` become `CInt` and `CChar`, aliases of the integer type with their size and signedness on the target. A C enum imports **open** by default ([08](../spec/08-c-interop.md#structs-unions-and-enums)): it may hold any value of its underlying type, so a `when` over it needs an `else`. A function-like macro isn't imported, so you wrap it in a C function in an `extern c` block ([08](../spec/08-c-interop.md#inline-c)). The import itself adds no symbol to the program: the SDK's code comes from linking its library, as in C.

## Calling C: `unsafe`

**Every imported C function is `unsafe` to call**, since a header can't say that a pointer outlives a call or that a buffer holds `n` elements ([08](../spec/08-c-interop.md#calling-imported-functions)):

```swift
func now() -> Double { plat.time_seconds() }            // error: a call into C needs 'unsafe'
func now() -> Double { unsafe plat.time_seconds() }     // 'unsafe' before one expression covers just it
```

**An `unsafe` block, `unsafe { … }`, marks code whose correctness the compiler takes on trust** ([10](../spec/10-errors-and-safety.md#unsafe-code)). As in Rust, it turns no check off: a list index is still checked inside it. It lets you write the operations the compiler can't check, such as a call into C, and in return you promise that each is correct. Among other things, every access through a raw pointer ([10](../spec/10-errors-and-safety.md#what-unsafe-code-upholds)):

- stays inside the allocation it points into;
- is aligned for its type;
- finds a valid value there, such as a `Bool` that is 0 or 1;
- reads and writes only where safe code could, so it breaks no live borrow.

Breaking one is undefined behavior, as in C. Code that uses such operations is **unsafe code**, the code to review most closely.

**Wrap each C call in a safe function**, which checks what C won't, so the rest of the game never writes `unsafe`:

```swift
func readPad(_ index: Int32) -> plat.pad? {
    precondition(index >= 0 && index < plat.PLATFORM_MAX_PADS)   // C wouldn't check it
    var raw = plat.pad()                                        // the C struct, all zeros
    let ok = unsafe plat.poll_pad(index, ptr(to: &raw))         // C fills it in through the pointer
    guard ok && raw.connected else { return nil }
    return raw
}
```

An `unsafe func` is a Rayo function whose callers need `unsafe`, as a C function's do. Its body is no `unsafe` block: it writes `unsafe` where it needs it, as any function does.

**A build can declare a module `@safe`, and every construct the compiler takes on trust is then an error in it** ([10](../spec/10-errors-and-safety.md#safe-modules)): `unsafe` code, `extern c` code, and unverified promises such as `@export`, which comes later in this chapter. Such a module can still `import c` a header for its types and constants, and call the safe wrappers that another module builds with `unsafe`.

## Raw pointers

**`*T` is a raw pointer that is never null, and `*T?` one that may be, with a C pointer's size** ([10](../spec/10-errors-and-safety.md#raw-pointers)). Rayo has no `const` pointer, so C's `const` is dropped.

- `ptr(to: &place)` gives a place's address, as in `readPad` above. It is `unsafe`.
- `p.pointee` is the `T` at `p`, and `p[i]` is `(p + i).pointee`. Each is `unsafe`, and no run-time check keeps it in bounds.
- `*Void` points at memory of no stated type, and `p.cast(to: UInt8.self)` turns it into a pointer you can read.
- `UInt(bitPattern: p)` turns a pointer into an integer, safely. The reverse is `unsafe`.
- A raw pointer borrows nothing, so the compiler doesn't stop you from using one after its place is gone. Using it only while its place lives is part of what `unsafe` promises.

Accessing a bare global `var`, or a variable a C header declares, needs `unsafe` too, since nothing checks which threads touch it ([10](../spec/10-errors-and-safety.md#what-needs-unsafe)).

## Passing memory to C

**A span hands C its pointer and its count, and a string literal hands C a C string:**

```swift
func upload(_ samples: Span<Float>) {                   // safe: a span always knows its count
    unsafe { plat.upload(samples.baseAddress, UInt(samples.count)) }
}
func log(_ level: Int32, _ text: StringView) {
    unsafe { plat.log(level, text.cchars.baseAddress, UInt(text.cchars.count)) }
}
```

- **Spans.** `baseAddress` is an `unsafe` field, so reading it needs `unsafe` too ([10](../spec/10-errors-and-safety.md#what-needs-unsafe)). The block is your promise, among others, that `platform_upload` only reads there, at most `count` floats, and none after it returns.
- **String literals.** A `StaticString`, such as a literal, is followed by a NUL, so `"Rayo".cString` passes to C as a `const char*` at no cost ([04](../spec/04-types.md#strings)).
- **Other strings.** They needn't end in a NUL, so `s.cchars` views any string's bytes as a `Span<CChar>`, for C functions that take a pointer and a length.

**When C keeps a pointer past the call, hand it the address a pin holds** ([Handles and objects](05-handles-and-objects.md)). A pin keeps a `StablePool` element at its address, and alive, for as long as the pin lives. `pin.address` is an `unsafe` field of type `*T`, and a pin is unscoped, so you can keep it in a field until C is done with the address:

```swift
// audio.h, imported as 'audio' where prefix: "audio_":
//     typedef struct audio_emitter { float gain; float pos[3]; } audio_emitter;
//     void audio_track(audio_emitter* e);      keeps 'e', and reads it on every update
struct Voice(var pin: Pin<audio.emitter>)          // holds the pin while C uses the address
let voice = Voice(pin: emitters.pin(h)!)           // emitters: a StablePool<audio.emitter>
unsafe { audio.track(voice.pin.address) }          // valid for as long as 'voice' keeps the pin
```

## Callbacks: `@c func`

**A `@c func` is a Rayo function that C can call through a function pointer** ([08](../spec/08-c-interop.md#callbacks)). The header's `void (*)(void* user, int event)` imports as `(@c (*Void?, CInt) -> Void)?`, and a `@c func` with those parameters converts to it:

```swift
let audioEvents = MpscQueue<AudioEvent>(capacity: 256)  // a global queue any thread may push to

@c func onAudioEvent(_ user: *Void?, _ event: CInt) {   // runs on the SDK's audio thread
    audioEvents.push(AudioEvent(raw: copy event))       // 'event' is borrowed, so copy it in
}

unsafe { plat.set_audio_callback(onAudioEvent, nil) }
```

- **Any thread.** C may call it from any thread, which is why it hands each event over through a queue ([Concurrency](07-concurrency.md)).
- **C's terms.** Its parameters and result have C representations ([08](../spec/08-c-interop.md#c-representations)). It can't throw, since C has no way to catch an error, and a panic in it stops the program without unwinding into C.
- **Borrowed parameters.** C never gives up what it passes through an imported callback type, so a `@c func` with an `owned` parameter doesn't convert to one.
- **Unsafe to call.** Calling through a `@c` pointer needs `unsafe`, since its type can't tell a Rayo function from a C one ([05](../spec/05-protocols-generics-and-closures.md#c-function-pointers)).

## Calling Rayo from C: `@export`

**`@export(c)` gives a function C linkage and an unmangled name, so C and C++ code can call it** ([08](../spec/08-c-interop.md#calling-rayo-from-c)). Say the studio's C++ level editor spawns enemies through the game:

```swift
@export(c) @c struct SpawnDesc(var pos: Vec3, var hp: Float)       // a C struct in the generated header
@export(c, name: "game_spawn") func spawnFromEditor(_ desc: SpawnDesc) -> Bool { ... }
```

- **A generated header.** The build writes a C header for the module, with every exported function and the types their signatures use.
- **C types only.** Parameters and results have C representations. Numbers, `Bool`, raw pointers and structs of them cross as C lays them out, a `Span<T>` as a struct of a pointer and a count, and a `Handle` as its 64 bits.
- **Plain C functions.** An exported function has no type parameters and can't throw. A parameter passes by value, whatever its Rayo convention, except a `mutable` one, which passes as a pointer.
- **The name is a promise.** The build fails when two objects it links define one name, but nothing checks a symbol the program loads at run time, or that every C caller uses this signature. So `@export` is an **unverified promise**, taken on trust as an `unsafe` block is ([10](../spec/10-errors-and-safety.md#unverified-promises)).

## What C must uphold

**C that calls Rayo, or that Rayo calls, takes on what `unsafe` Rayo code would promise in its place** ([08](../spec/08-c-interop.md#what-c-must-uphold)). C calls Rayo through a **C entry**, such as a `@c func` or an exported function, and may call one from any thread ([08](../spec/08-c-interop.md#c-entries-and-threads)). Rayo can't check C, so these are on the C side:

- every value it hands Rayo is valid for its Rayo type: a `Bool` is 0 or 1, a Rayo enum holds one of its cases, and a pointer that may not be null isn't;
- it reads Rayo memory only while Rayo keeps it alive and isn't writing it, and writes it only where Rayo code with exclusive access could;
- it never frees or keeps a value that Rayo passed it borrowed;
- it never `longjmp`s over a Rayo frame or unwinds through one;
- it enters Rayo only by an ordinary call, never from a signal handler.

Breaking one is undefined behavior, as a wrong `unsafe` block is. Where you can't trust what C passes, take the raw form and convert it with a checked conversion. An exported function can take an `Int32` in place of an enum, and an enum's `E(rawValue:)` gives `nil` for a value that is no case.

## Running code at compile time: `const`

**A `const`'s initializer runs in the compiler, and it may call ordinary functions** ([09](../spec/09-compile-time.md#running-code-at-compile-time-const)):

```swift
const sinTable: [1024 of Float] = makeSinTable()         // computed once, by the compiler

func makeSinTable() -> [1024 of Float] {
    var t: [1024 of Float] = .init(repeating: 0)
    for i in 0..<1024 { t[i] = sin(Float(i) / 1024 * 2 * .pi) }
    return t
}
```

A function needs no mark to run at compile time, unlike C++'s `constexpr`. It runs there if what it executes, on the input it gets:

- calls no C function;
- accesses no global other than a `const`;
- starts, parks or wakes no thread;
- makes no volatile access, and none through a pointer made from an integer;
- reads no clock.

```swift
const startTime = now()          // error: 'now' calls C, which can't run in the compiler
let startTime = now()            // fine: a global 'let' is initialized at startup
```

- **It computes what the program would.** Overflow wraps where overflow checks are off, as at run time, and a panic is a compile error.
- **Allocation works.** The compiler has a heap of its own, so a `const` can build a `List` with `append`. A `const` that run-time code names is frozen into the program's read-only data ([09](../spec/09-compile-time.md#consts-that-reach-run-time)).

## `static if` and `target`

**`static if` picks code at compile time, and the branch it doesn't take is parsed but never type-checked** ([09](../spec/09-compile-time.md#static-if-and-conditional-compilation)). Like C's `#if`, it can leave out declarations and whole imports. Unlike `#if`, its condition is a Rayo `const` expression, and it works inside generic code too (below). A condition that guards an import reads only literals, `target` and the `const`s of modules imported outside any `static if`. So a branch may name what exists only on another platform, or only in some builds:

```swift
static if target.platform == .ps5 {
    import c "platform_ps5.h" as plat where prefix: "platform_"
} else {
    import c "platform.h" as plat where prefix: "platform_"
}

func endFrame(_ game: Game) {
    static if target.hasFlag("editor") {
        drawGizmos(game)                 // declared only in editor builds, which declare the flag
    }
    static if game.paused { ... }        // error: a 'static if' condition must be a const
}
```

**`target` is a `const` that describes the build.** It has, among others:

- `platform`, `arch` and `endian`;
- `profile`, which is `.dev`, `.profile` or `.ship`;
- `flag("editor")`, a flag the build defines. Reading one the build doesn't define is a compile error, and `hasFlag("editor")` says whether it does.

`static error("…")` makes a branch a compile error with that message, as in `static if !target.hasFlag("sse4") { static error("needs SSE4") }`.

## Reflection: `T.fields` and `static for`

**Every type has metadata that code reads at compile time, and `static for` walks a list of it** ([09](../spec/09-compile-time.md#static-reflection)). Here is `save`:

```swift
func save<T>(_ value: T, into w: mutable Writer) {
    static if T.conforms(Pod.self) && T.isPaddingFree {
        w.bytes(of: value)                              // a Float or a Vec3: its bytes, as they are
    } else static if T.conforms(Serializable.self) {
        value.serialize(into: &w)                       // List, String and Map conform in std
    } else static if T.isConstructible {                // a struct whose fields this code all sees
        w.beginObject(T.name)
        static for field in T.fields {                  // unrolled: one copy of the body per field
            w.key(field.name)
            save(value[field], into: &w)                // each copy checked with its own field's type
        }
        w.endObject()
    } else {
        static error("\(T.name) can't be saved field by field: conform it to Serializable")
    }
}
```

- `T.fields` lists `T`'s stored fields in declaration order, each with a `name`, a `StaticString`, and a `type` ([09](../spec/09-compile-time.md#what-reflection-can-read)).
- `static for` instantiates its body once per field, and checks each copy with that field's type.
- `value[field]` reaches the field in place, as `value.pos` would. Only an imported bitfield or an under-aligned field goes through a temporary.
- `T.conforms(P.self)`, `T.isPaddingFree` and `T.isConstructible` are `const` queries, made for `static if`.

**In generic code, a `static if` branch is checked only for the types that take it.** So the first branch may call `w.bytes(of:)`, which accepts only a padding-free `Pod` type, and the `static error` fires only for a type that reaches the last branch.

`Enemy` isn't `Pod`, since its `List` owns memory, and it doesn't conform to `Serializable`, so it takes the third branch. The loop unrolls into the keys `pos`, `vel`, `hp` and `path`. The first three save their bytes, since `Vec3` and `Float` are `Pod` and padding-free, and `path`, a `List`, saves itself. `T.isConstructible` is true only where this code sees every field of `T`. So a type with fields hidden from `save` that isn't plain data or `Serializable` stops at the `static error`, instead of saving part of its state. A Rayo enum stops there too: the spec's serializer adds a branch that walks `T.cases` ([09](../spec/09-compile-time.md#static-reflection)).

**Reflection sees only what the code that uses it could name** ([09](../spec/09-compile-time.md#reflection-and-access-control)). In `Enemy`'s own module, `Enemy.fields` lists every field. In another module, such as a shared save library, it lists only the `public` ones, so `save` would stop at its `static error`. Writing `@reflect(private)` before `struct Enemy`, as the next section does, shows other modules every field. It grants nothing else: other modules still can't name a field that isn't `public`.

## Attributes

**An attribute is a struct that conforms to `Attribute`, and reflection reads it** ([09](../spec/09-compile-time.md#attributes)). Reflection gives a field's name and type, but not that the field is a cache to skip, or the range an editor's slider shows. The type's author says so with attributes:

```swift
struct Transient: Attribute {}                          // a field that save skips
struct Bounds(let min: Float, let max: Float): Attribute {
    init(_ min: Float, _ max: Float) { self.init(min: copy min, max: copy max) }   // the parameters are borrowed
}

@reflect(private)
struct Enemy(
    var pos: Vec3,
    var vel: Vec3 = .zero,
    @Bounds(0, 500) var hp: Float = 100,
    @Transient var path: List<Vec3> = [],
)
```

`save` skips `path` with a `where` clause on its loop, `static for field in T.fields where !field.has(Transient.self)`. An editor reads `@Bounds` to set up a slider:

```swift
func inspect<T>(_ value: mutable T, in ui: mutable Inspector) {
    static for f in T.fields where f.has(Bounds.self) {
        const b = f.attribute(Bounds.self)!             // this field's @Bounds, known at compile time
        ui.slider(f.name, &value[f], min: b.min, max: b.max)
    }
}
```

**An attribute's arguments must be `const`:**

```swift
let maxHp: Float = 500
struct Boss(@Bounds(0, maxHp) var hp: Float = 100)      // error: 'maxHp' is a global 'let', not a const
```

Declaring `const maxHp: Float = 500` fixes it. Reflection reads an attribute only on a field, a type or an enum case, so one anywhere else is a compile error. The built-in attributes, such as `@c`, `@export` and `@reflect`, are reserved names.

## In the spec

- [08 C interop](../spec/08-c-interop.md): importing headers and what each C declaration imports as, C representations, callbacks, `@export`, and everything C must uphold.
- [10 Unsafe code](../spec/10-errors-and-safety.md#unsafe-code): what needs `unsafe`, raw pointers, the full rules `unsafe` code keeps, and `@safe` modules.
- [05 C function pointers](../spec/05-protocols-generics-and-closures.md#c-function-pointers): which functions convert to a `@c` type, and when.
- [03 Pinning for C](../spec/03-handles-and-objects.md#pinning-for-c): what a pin guarantees while C holds its address.
- [09 Compile time](../spec/09-compile-time.md): `const` evaluation and freezing, `static if`, everything reflection reads, attributes, generated declarations, building values with `T.construct`, and `typeInfo` at run time.
