# 2 · Moves and copies

Your renderer records a `CommandList` each frame and hands it to `submit`, which queues it for the GPU. Vertex data lives in GPU buffers, and each buffer must be released exactly once. In C++, both are easy to get wrong: a list used after `std::move` still compiles, and a buffer struct copied by accident is freed twice. In Rayo, each mistake is a compile error:

```swift
struct GpuBuffer(let id: UInt32, let size: Int) {
    deinit { releaseGpuMemory(id) }              // runs when the buffer's owner lets go of it
}

func createBuffer(size: Int) -> GpuBuffer { ... }
func submit(_ cmds: owned CommandList) { ... }   // 'owned': submit keeps the list

var cmds = CommandList()
cmds.draw(mesh)
submit(cmds)                                     // the list moves into submit
cmds.draw(mesh)                                  // error: 'cmds' was moved

let vertices = createBuffer(size: 65536)
let twin = copy vertices                         // error: 'GpuBuffer' is not copyable
```

Both errors come from one idea: every value has one owner, and the compiler tracks which place that is. This chapter shows how values change owners, how you copy one when you mean to, and when each is destroyed.

## Owners

**Every value has one owner, which decides when the value is destroyed** ([01](../spec/01-values-and-ownership.md)). An **owner** is a place, such as a local or an `owned` parameter, or a value that owns others. Owners nest: a local owns a list, and the list owns each element.

```swift
func spawnWave() {
    var wave = List<Enemy>()                // 'wave' owns the list, and the list owns each enemy
    wave.append(Enemy(pos: [0, 0, 5]))
    let first = wave[0]                     // uses the enemy without owning it: the list still does
}                                           // 'wave' ends here: the list and its enemies are destroyed
```

Code that uses a value without owning it **borrows** it, as `first` does, and as a parameter does by default ([01](../spec/01-values-and-ownership.md)). Chapter 3 is about borrowing ([Borrowing](03-borrowing.md)). The one exception to a single owner is reference counting: `Shared<T>` lets several owners share a value, and the last one to let go destroys it ([Memory and allocators](06-memory-and-allocators.md)).

## Moves

**Assigning a value, returning it or passing it to a parameter that keeps it moves it** ([01](../spec/01-values-and-ownership.md#moves)). A **move** hands the value to a new owner. The place it came from can't be used until it gets a new value:

```swift
var cmds = CommandList()
cmds.draw(mesh)
submit(cmds)                       // moves the list into submit
print(cmds.count)                  // error: 'cmds' was moved
cmds = CommandList()               // a new value makes 'cmds' usable again
cmds.draw(mesh)                    // fine
```

These take what they are given, and so move it:

- an assignment, as in `grunt.pos = spawn`;
- `return`, which is how `createBuffer` hands back the buffer it made;
- an argument for an `owned` parameter, such as `submit`'s;
- an argument of a struct's primary initializer, which takes every field `owned`, since the new value owns its fields;
- the element given to `append`, since the list keeps it.

**The callee owns an `owned` argument as a local owns its value** ([01](../spec/01-values-and-ownership.md#parameters)). `submit` may move the list on, into a queue, say. If it doesn't, the list is destroyed when `submit` returns.

**A move changes the owner and nothing else.** It runs none of your code and allocates nothing. It copies at most the value's bytes, into the place that takes it. So there is no move constructor to write. A move leaves no object behind to use by mistake: the compiler knows the place holds nothing.

### Copyable types move too

**A move is a move whatever the type, even a `Vec3` or an `Int`.** In C++ and Swift, and for Rust's `Copy` types, passing a small struct by value copies it, and the original stays usable. In Rayo, a place given to something that keeps it moves, whatever its type. A plain parameter only borrows, so it moves nothing:

```swift
var spawn = Vec3(0, 0, 5)
var grunt = Enemy(pos: copy spawn)       // a copy moves in, and 'spawn' stays
var brute = Enemy(pos: spawn)            // 'spawn' itself moves in
var scout = Enemy(pos: spawn)            // error: 'spawn' was moved
var drone = Enemy(pos: [2, 0, 5])        // fine: a new value, so no variable moves or is copied
```

A move never makes a second value. One exists only where the code asks for it: with `copy` or `clone()`, by taking a copyable `const` ([below](#constants)), or through one of a few operations that copy ([01](../spec/01-values-and-ownership.md#operations-that-copy)). To keep the original, pass `copy x`. To keep it without a copy, pass a new value instead, such as a literal or a call's result.

## Copies

**Copies are written out** ([01](../spec/01-values-and-ownership.md#copies)):

- **`copy x`** duplicates a copyable value's bytes, as a `memcpy`. It never allocates.
- **`x.clone()`** copies a move-only value, such as a `List` or a `String`. It allocates, and its name says so. `List` and `String` have one, and a type of your own gets one by declaring a `clone()` method.

```swift
var aim = copy brute.pos                 // Vec3 is copyable: a memcpy
aim.y += 2                               // brute.pos is unchanged
var backup = wave.clone()                // List owns heap memory: clone allocates a new buffer
var other = copy wave                    // error: 'List<Enemy>' is not copyable
```

**A type is copyable when every part of it is, and nothing opts it out.** A struct or enum is **copyable** when:

- all its fields and enum payloads are copyable;
- it declares no `deinit` ([below](#destruction));
- it doesn't list `~Copyable`;
- it isn't of a kind that is always move-only, such as a lock guard ([Concurrency](07-concurrency.md#locks-mutex-and-rwlock)).

Every other type is **move-only**. `Enemy` is copyable, since a `Vec3` and a `Float` are. A copyable type can't own heap memory, which is why `copy` never allocates. So `List`, `String`, `Box` and every other type that owns memory is move-only, and copying one takes a call that allocates.

**`~Copyable` makes a type move-only although its fields could be copied.** Use it for a value that must have one owner:

```swift
struct UploadSlot(let offset: Int, let size: Int): ~Copyable   // a copy would let two uploads write one slot
```

The compiler derives `Copyable` for each copyable type. It is a **marker protocol**: one with no requirements, which states a property of a type ([05](../spec/05-protocols-generics-and-closures.md#conformances)). Listing it, as `struct Handle<T>(…): Copyable` does, asks the compiler to confirm it ([Handles and objects](05-handles-and-objects.md)). A `~Copyable`, like a `deinit`, is declared in the type's own module, so all code that uses the type sees the same answer.

## Destruction

**A value is destroyed when its owner's scope ends, or when its owner is given a new value** ([01](../spec/01-values-and-ownership.md#destruction)). Destruction runs in reverse order:

- a scope's locals, last declared first;
- a statement's temporaries, at the end of the statement, last made first;
- a value's parts: its own `deinit` first, then its fields, last declared first.

An `owned` parameter counts as a local of the function's body, declared before the body's own locals.

### `deinit`

**A `deinit` is code that runs when a value of its type is destroyed.** It goes in the struct's body, and takes no parameters:

```swift
struct GpuBuffer(let id: UInt32, let size: Int) {
    deinit { releaseGpuMemory(id) }
}

func drawTerrain() {
    var vertices = createBuffer(size: 65536)
    let indices = createBuffer(size: 16384)
    vertices = createBuffer(size: 131072)        // the first vertex buffer is released here
}                                                 // 'indices' is released, then 'vertices'
```

**A type with a `deinit` is move-only.** A copy would run the `deinit` a second time, and release one buffer twice. A move runs no code, so only the buffer's last owner runs it. That is how `GpuBuffer` gets its guarantee: whichever place owns the buffer last releases it, once.

A `deinit` is declared in the type's own module, in its body or in an extension with no conditions ([04](../spec/04-types.md#initializers)). Safe code never runs one twice, but it can skip one. After an arena is reset, destroying a list whose buffer the arena held skips its elements' `deinit`s ([Memory and allocators](06-memory-and-allocators.md#stale-values-objects-and-heaps)).

## Moving out of what you own

**Only code that owns a place can move a value out of it** ([01](../spec/01-values-and-ownership.md#what-can-be-moved-from)). Moving a value out, implicitly or with `consume`, is **consuming** the place ([01](../spec/01-values-and-ownership.md#moving-values-out)). These are the places code can move from:

- a local that owns its value: one bound to a value, such as a call's result, or one declared `owned` (below);
- an `owned` parameter;
- a temporary, such as a call's result passed straight to an `owned` parameter;
- a field of one of those, when no type on the way to it declares a `deinit` ([below](#moving-a-field-out)).

### `owned let` and `consume`

**A `let` of a place borrows it, and a bare `var` of one is an error.** Chapter 1 showed `let first = enemies[0]` naming an element without copying it. `owned let x = place`, or `owned var`, moves the value out instead ([01](../spec/01-values-and-ownership.md#bindings)):

```swift
var current = createBuffer(size: 65536)
owned var previous = current             // moves: 'previous' takes the buffer over
current = createBuffer(size: 65536)      // 'current' gets a new buffer, and is usable again
var spare = current                      // error: a bare 'var' of a place: write '&' or 'owned'
```

**`consume x` writes a move as an expression.** It gives up a value where nothing would take it otherwise:

```swift
let n = countDraws(consume cmds)         // countDraws only borrows: the list is destroyed after this statement
consume previous                         // releases the buffer here, not at the end of the scope
```

### Moving a field out

**A field can move out of a value you own when no type on the way declares a `deinit`.** The rest of the value stays where it is, and the compiler tracks it field by field:

```swift
struct Frame(var cmds: CommandList, var number: Int)    // no deinit

func finish(_ frame: owned Frame) {
    submit(frame.cmds)               // moves the field out of 'frame'
    log("frame \(frame.number)")     // fine: 'number' still holds its value
    archive(frame)                   // error: 'frame.cmds' was moved
}                                    // the fields still held are destroyed here
```

Until the field gets a value again, the whole value can't be used or passed. If the scope ends first, each field still held is destroyed on its own, last declared first.

**A `deinit` keeps its value whole.** It runs on all of `self`, and would find a field missing. So moving a field out of a value whose type declares one is a compile error:

```swift
struct RenderPass(var cmds: CommandList, let id: Int) {
    deinit { log("pass \(id) ended") }
}

func close(_ pass: owned RenderPass) {
    submit(pass.cmds)                                  // error: RenderPass's deinit needs all of 'pass'
    submit(replace(&pass.cmds, with: CommandList()))   // fine: leaves a list behind for the deinit
}
```

The type's own code is the exception: its `deinit`, and a `consuming` method that ends the value with `discard self`, may move fields out. A **`consuming` method** takes `self` owned, as chapter 3 shows ([Borrowing](03-borrowing.md#three-ways-to-pass-an-argument)), and `discard self` ends the value without running its `deinit` ([01](../spec/01-values-and-ownership.md#what-can-be-moved-from)).

### Places you don't own

**Nothing moves out of a place the code doesn't own.** So none of these can be consumed:

- a borrowed or `mutable` parameter, or a field of one;
- a `let` or `var` that borrows a place;
- an element of a collection, which the collection hands out through a method such as `popLast()`;
- a global, a `const` included.

The spec lists a few more ([01](../spec/01-values-and-ownership.md#what-can-be-moved-from)). This holds for copyable values too, so returning a borrowed parameter's field takes `copy`:

```swift
func aimAt(_ e: Enemy) -> Vec3 { e.pos }           // error: 'e' is borrowed, so 'e.pos' can't move out
func aimAt(_ e: Enemy) -> Vec3 { copy e.pos }      // fine: returns a copy
```

**`replace`, `swap` and `take()` move a value out of a place you may change, and leave one behind.** A `mutable` parameter lends the caller's place for change, so the caller still owns it:

```swift
struct Renderer(var cmds: CommandList, var front: GpuBuffer, var back: GpuBuffer, var retired: List<GpuBuffer>)

func endFrame(_ r: mutable Renderer) {
    submit(r.cmds)                                   // error: the caller still owns 'r'
    submit(replace(&r.cmds, with: CommandList()))    // moves the list out, and leaves an empty one
    swap(&r.front, &r.back)                          // the buffers trade places: none is copied or released
    let done = r.retired.take()                      // moves the list out, and leaves 'r.retired' empty
}                                                    // 'done' ends here, releasing the retired buffers
```

A type may offer its own `take()`: an optional's leaves `nil`, and a list's leaves it empty. So a place you don't own always holds a value, even after an early return or a `throw`.

## Places that hold no value

**The compiler tracks, on every path, whether each place holds a value** ([01](../spec/01-values-and-ownership.md#places-that-hold-no-value)). A binding may start without one, and a `let` is then assigned at most once on each path:

```swift
let size: Int
if hiRes { size = 4096 } else { size = 1024 }
var vertices = createBuffer(size: size)      // fine: every path gave 'size' a value
```

**A place that holds a value on only some paths is maybe-initialized where they join.** A **maybe-initialized** place can't be used until it is assigned again:

```swift
var cmds = CommandList()
if needsFlush {
    submit(cmds)                    // moves on this path only
}
cmds.draw(mesh)                     // error: 'cmds' may have been moved
```

The fix gives the place a value on every path:

```swift
if needsFlush {
    submit(cmds)
    cmds = CommandList()            // so both paths leave 'cmds' holding a list
}
cmds.draw(mesh)                     // fine
```

**At the end of a scope, and when a place is assigned, its old value is destroyed if, and only if, the place still holds one.** So without its last line, the first version would destroy `cmds` at the end of its scope only on the path where `submit` didn't take it.

## Constants

**A `const` of a copyable type is taken as a new value each time, with no `copy`** ([01](../spec/01-values-and-ownership.md#constants)):

```swift
const maxLights = 8

var lightsLeft = maxLights          // a new Int: a 'var' of a copyable const needs no 'copy'
lightsLeft -= 1                     // maxLights is unchanged
```

`Vec3.zero` is taken the same way, so `Enemy(pos: .zero)` needs no `copy`. A `const` the program uses at run time lives in read-only data for the whole run, so nothing moves out of it or changes it. A `const` of a move-only type, such as a `List`, can only be borrowed or cloned. Chapter 8 shows how the compiler computes a `const` ([C and compile time](08-c-and-compile-time.md)).

## In the spec

- [01 Values and ownership](../spec/01-values-and-ownership.md#moves): moves, copies and every operation that copies, destruction order, and each place that can or can't be moved from.
- [01 Parameters](../spec/01-values-and-ownership.md#parameters): the `owned` convention, and how a callee holds what it is given.
- [01 Bindings](../spec/01-values-and-ownership.md#bindings): every form of `let` and `var`, with what each does to a place.
- [04 Initializers](../spec/04-types.md#initializers): why the primary initializer moves its arguments, and where a `deinit` is declared.
- [05 Conformances](../spec/05-protocols-generics-and-closures.md#conformances): marker protocols, and why `~Copyable` is declared with the type.
- [06 Stale values](../spec/06-memory-and-allocators.md#stale-values-and-the-deinits-a-reset-runs): when an arena reset skips a `deinit`.
