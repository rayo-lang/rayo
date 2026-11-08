# Owning boxes and long-lived views

[06 · Memory and allocators](../06-memory-and-allocators.md)

When a value needs a lifetime independent of the local that created it, an owning pointer can hold it in allocated storage. `Box` has one owner; `Shared` and `LocalShared` count several. Long-lived views take a different route: they keep access to a buffer checked without copying its contents.

## Owning boxes

```swift
enum Tree { case leaf(Int); case node(Box<Tree>, Box<Tree>) }   // recursion goes through a Box
let rock = Shared(loadTexture("rock.tex"))                      // immutable, with any number of owners
```

**Four types own a value through a pointer.** They differ in how many owners the value may have, and on which threads:

| Type | Semantics |
| --- | --- |
| `Box<T>` | Unique owning pointer, move-only |
| `UniquePointer<T>` | Unique owner of an object, on one thread; hands out checked `WeakPointer<T>`s ([03](../03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)) |
| `Shared<T>` | Reference-counted pointer to a `Frozen` or `Synchronized` `T`, with an atomic count; hands out checked `WeakShared<T>`s |
| `LocalShared<T>` | Reference-counted pointer to a `Frozen` `T`, with a plain count, on one thread |

**`Box.leak` gives up a box's allocation for C to hold.** It applies only to a box whose value type is unscoped, a `T: ~Scoped`, since a `RawAllocation` holds the value with no borrows ([02](../02-views-and-dependencies/scoped-values.md#generic-code-and-scoped)). It returns the `RawAllocation` that holds the value, with its address, size, alignment and allocator word ([10](../10-errors-and-safety/unsafe-code.md#raw-allocations)).

**`Box.adopt`, which is `unsafe`, takes it back.** Its caller promises that the allocation came from leaking a `Box<T>`, and that it is adopted at most once, since a second `adopt` would make a second owner of the value.

### `Shared<T>`: data with many owners

**`Shared<T>` counts the owners of a value that many places, on any threads, hold at once:**

```swift
struct Texture(var pixels: List<UInt8>, var width: Int)                // Frozen: derived by the compiler
struct Material(var albedo: Shared<Texture>, var roughness: Float)      // Frozen too, since Shared<Texture> is

let rock = Shared(Texture(pixels: loadPixels("rock.tex"), width: 512))
let wet = Shared(Material(albedo: rock.share(), roughness: 0.2))       // share() adds an owner, visibly
let dry = Shared(Material(albedo: consume rock, roughness: 0.9))       // a move: the count doesn't change

let log = Shared(Mutex(List<Message>()))                               // Synchronized: changes only under its lock
log.value.lock { $0.append(m) }
```

**A `Shared<T>`'s count is atomic, and its `T` must be `Frozen` ([below](#frozen-types-with-no-interior-mutability)) or `Synchronized` ([07](../07-concurrency/synchronization.md#the-synchronized-contract)).** So any number of threads may read the value at once, and it changes only through its own synchronization, if at all.

**`LocalShared<T>` is the same with a plain count, for a `Frozen` `T` only, and with no weak links.** It is never `Sendable`, so all its owners stay on one thread and counting needs no atomic operation.

**Both follow these rules, except where one is named:**

- **Counting is visible.** Both are move-only, and each new owner takes an explicit `s.share()`, so the source shows every owner it adds. A move doesn't change the count. `s.value` lends the value read-only for as long as `s` is borrowed.
- **The last owner destroys the value.** Dropping the owner that takes the count to zero runs the value's `deinit` and frees its memory at once, on the thread that dropped it.
- **Immutable reference-counted values can't form cycles.** A `Frozen` value never changes, and neither does anything it owns. So a `Shared` of one can only point at values that existed before it, and nothing it owns can be changed to point back. A `Synchronized` value, though, can be changed to hold an owner of itself, as a `Shared<Mutex<Node>>` can, and that cycle leaks.
- **Weak links.** `s.weak()` on a `Shared<T>` returns a **`WeakShared<T>`**: 8 bytes and copyable, and it doesn't keep the value alive. `w.upgrade()` returns a new owner, a `Shared<T>?`, through an atomic compare-and-swap, never waiting for another thread. It reads `nil` once the value is destroyed or its storage stale ([Opening an owning value checks it](arena-safety.md#opening-an-owning-value-checks-it)). A weak link names its value by a generation that no other `Shared` value of the run gets, so it never names a later one. `WeakShared<any P>` holds an existential as `WeakPointer<any P>` does ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)).
- **Weak links as bits.** `w.bits` packs a weak link into a `UInt64`, which `WeakShared<T>(bits:)` checks as `WeakPointer<T>(bits:)` does, without the thread ([03](../03-handles-and-objects.md#weak-pointers-as-bits-and-handing-objects-to-c)).
- **Handing an owner to C.** `Shared.leak(s)` gives up the owner, keeping its count, and returns a weak link for C to hold as a `uint64_t`. `Shared.adopt(w)` returns that owner, and reads `nil` unless `w` names a live value with a leaked owner, so a forged, mistyped or repeated `adopt` is harmless. While C holds a leaked owner, the value stays at its address.
- **Threads.** `Shared<T>` and `WeakShared<T>` are `Sendable` when `T` is, and `LocalShared<T>` never is ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)). Weak pointers and weak links don't own, so a `Frozen` value may hold them without creating cycles. A `Frozen` value that crosses threads holds only weak links, since an object's weak pointers stay on its home thread.

**`Sender`, `Receiver` and `Future` values also count their owners internally.** Dropping a `Receiver` breaks the cycles that [07](../07-concurrency/synchronization.md#queues-and-channels) names, and the others leak.

### `Frozen`: types with no interior mutability

**Many owners can read a `Frozen` value at once, since nothing writes it through a shared borrow.** So `LocalShared` requires one, `Shared` requires one unless its value is `Synchronized` ([above](#sharedt-data-with-many-owners)), and so does freezing a value into read-only data ([09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)).

**The compiler derives `Frozen` for types with no interior mutability**: types that hold none of these, each a way for what a value holds to change while it is borrowed shared:

- a `Synchronized` field, such as a `Mutex`, an `Atomic` or a queue;
- an object owner, whose object is mutable through weak pointers;
- a raw pointer;
- a `Closure`, which counts as holding a `Synchronized` value, since its captures may hold one unseen in its type ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)).

**Nothing that is or holds a `Synchronized` value, at any depth, is `Frozen`**, whatever the `Synchronized` type's own fields look like, since its non-`mutating` methods write it ([07](../07-concurrency/synchronization.md#the-synchronized-contract)). Declaring `: unsafe Frozen` on such a type is a compile error.

**`Frozen` covers a value's fields and the buffers it owns, not the values it names.** Nothing writes a `Frozen` value's fields, or any buffer it owns, through a shared borrow of it: only bookkeeping that no reader observes, such as a `Shared`'s count, changes under one. Its owner may still mutate it, as a `var` of it. A weak pointer, a weak link or a handle in it only names another value, which isn't part of it and may change.

**A type the compiler can't derive `Frozen` for may declare `: unsafe Frozen`**, typically one holding a raw pointer to data that never changes. The declaration is an unverified promise ([10](../10-errors-and-safety/unsafe-code.md#unverified-promises)) of two things:

- nothing writes what a value of the type holds, or what it points at through a raw pointer, through a shared borrow of it, except bookkeeping that no reader observes;
- nothing at all writes a value of the type frozen into read-only data ([09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)).

**So a type that writes bookkeeping must keep its values from being freezable**, as a `Shared` does by not being `TrivialFree`. The language makes the promise for `StaticSpan` and `StaticString`, which point into immortal data ([09](../09-compile-time/attributes-and-runtime-data.md#staticspan-views-of-immortal-data)).

**Some types hide what they hold, or hold it through a raw pointer, yet are `Frozen` according to what they hold:**

- **Existentials.** An existential has no fields to check, so `any P` and `mutable any P` are `Frozen` only when `P` refines `Frozen`, or when they are written with `& Frozen`, which accepts only `Frozen` types, as for `Sendable` ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)).
- **Containers.** std's owning containers (`List`, `String`, `Map`, `Set`, `TrailingArray`, `Pool`, `StablePool`, `Box` and `Blob`) and the builtin `SoA` conform when every type they hold does: a `TrailingArray`'s header and elements, a `Map`'s keys and values, and each other container's elements. So `Box<any P>` is `Frozen` exactly when its `any P` is. The raw pointer inside each names one of these:
  - a buffer the container owns alone, written only by its `mutating` methods, apart from a `StablePool`'s pin counts (below). Those methods need exclusive access, which no shared borrow of a `Frozen` value that holds the container grants;
  - in a `String` made from a literal, immortal bytes that nothing writes ([04](../04-types/collections.md#literals)).
- **`Shared<T>` and `LocalShared<T>`.** Each is `Frozen` when its `T` is: its count is bookkeeping that no reader observes. So an asset graph, a `Shared<Material>` holding `Shared<Texture>`s, is `Frozen` all the way down. A `StablePool`'s pin counts are bookkeeping of the same kind ([03](../03-handles-and-objects.md#pinning-for-c)), so pinning an element of a `Frozen` pool, from any thread, leaves it `Frozen`.

## Long-lived views into long-lived buffers

**For a view that has to be stored in long-lived state, which a scoped `Span` can't be, the view is a checked `Slice<T>`** ([02](../02-views-and-dependencies/scoped-values.md#where-a-scoped-value-can-go)). Its buffer lives behind a `Shared` ([above](#sharedt-data-with-many-owners)), as a fixed-size **`Blob`** of bytes, or a `Blob` or `List` under an `RwLock`:

```swift
let package = Shared(try Blob.load("level3.pak"))       // Blob: fixed-size bytes, 16-byte-aligned unless asked
struct MeshComponent(var vertices: Slice<Vertex>)        // a checked view: a weak link to the buffer and an element range

let m = MeshComponent(vertices: try package.slice(of: Vertex.self, at: header.vertexOffset, count: header.vertexCount))
upload(m.vertices.read()!)                               // Span<Vertex>: one check, then none per element
```

**`Slice<T>` is unscoped, copyable and `Sendable`.** It can be unscoped because it reads its buffer only through a scoped span it hands out for each use, so nothing frees the buffer while it is read ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)). It holds a weak link to its buffer's `Shared`, so it keeps nothing alive, and once that value is destroyed every `Slice` into it reads `nil`.

**A `Blob` owns one allocation of bytes, with its length and alignment fixed at construction.** The alignment is 16 bytes unless the constructor asks for more, up to the page size, as in `Blob(count: n, align: 64)`.

**A slice is checked when it is made, and again at each read or lock:**

- **Reading and locking it.** `s.read()` gives a slice's elements as a `Span<T>?`, and `s.lock()` as a `MutableSpan<T>?`. Each is `nil` once the buffer is gone: its `Shared` value destroyed, or the buffer's storage stale after a reset or an unregistration. Each call checks the storage as an open does, reading `nil` where an open would panic ([Opening an owning value checks it](arena-safety.md#opening-an-owning-value-checks-it)).

  Each call upgrades the weak link, and the span holds that owner until the span's last use ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)). For a buffer under an `RwLock`, the span also holds the read lock for `read()`, or the write lock for `lock()`, until then. A slice of a bare `Shared<Blob>` is read-only: its `lock()` panics, since nothing writes a `Frozen` value.
- **What creation checks.** `T` must be `Pod` ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)), and a blob's bytes are always initialized (zeroed at construction, or filled by the load), so reading them as `T` is sound. `slice(of:at:count:)` throws unless all of these hold, which put every element inside the blob, aligned for `T`:
  - the range is in bounds;
  - `T`'s alignment is at most the blob's;
  - the offset is a multiple of `T`'s alignment.

  Locking as a `MutableSpan<T>` also requires `T.isPaddingFree`, as a mutable span cast does ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)), since a store through a padded `T` would leave bytes other slices read uninitialized.
- **Locked blobs.** A slice of a `Shared<RwLock<Blob>>` is read and locked under the blob's lock. A write lock can replace the whole blob with a shorter or less-aligned one. So each `read()` or `lock()` of such a slice also compares its end with the current blob's length, and `T`'s alignment with the blob's, under the lock it takes anyway. A failure reads as `nil`. A bare `Shared<Blob>` can't be replaced, so the range and alignment creation checked hold for its slices' whole life.
- **Lists.** `slice(at:count:)` on a `Shared<RwLock<List<T>>>` makes a `Slice<T>` of a range of its elements, which needn't be `Pod`. A write lock can grow, shrink or move the list's buffer, so each `read()` or `lock()` of such a slice finds the buffer again and compares the range with the list's current count, under the lock it takes. A failure reads as `nil`.
- **Limits.** `slice` throws when the offset or the count exceeds `UInt32.max`.

A `Font` owns its file's blob through a `Shared`, plus `Slice`s into it:

```swift
struct Font(
    var file: Shared<Blob>,          // an owner: the blob lives while any font that shares it does
    var glyphs: Slice<GlyphRecord>,  // stored views into that same blob
)
```
