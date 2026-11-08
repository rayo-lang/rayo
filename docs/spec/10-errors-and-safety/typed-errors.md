# Typed errors

[10 · Errors and safety](../10-errors-and-safety.md)

A function that can fail in an expected way returns the failure to its caller as a value. Its result type, such as `Mesh!LoadError`, says what it returns when it succeeds and which errors it can fail with:

```swift
enum LoadError: Error {
    case notFound(path: StaticString)
    case corrupt(offset: Int)
    case unknownCase(Name)                  // reflective loaders (09)
    case badValue(field: StaticString)
    case outOfMemory
}

func loadMesh(_ path: StringView) -> Mesh!LoadError {
    let bytes = try readFile(path)                      // readFile returns List<UInt8>!IoError; converted below
    guard bytes.count >= MeshHeader.size else { throw .corrupt(offset: 0) }
    ...
}

extension LoadError {                                   // enables 'try' across error types
    @converts init(_ e: owned IoError) { self = if e == .missing { .notFound(path: "?") } else { .corrupt(offset: -1) } }
    @converts init(_ e: owned ParseError) { self = .corrupt(offset: e.offset) }
}
```

**A public function's result type names its error type, and failing costs the same as returning:** a function that can fail returns its result or its error as a tagged union, with no unwinding and no allocation. Unwinding is the path of a panic, which signals a bug rather than a failure the caller expects ([Panics](panics.md#what-a-panic-does)).

## Results

```swift
enum Result<Success, Failure: Error> {
    case success(Success)
    case failure(Failure)
}

func loadLevel(_ path: StringView) -> Level!(IoError | ParseError)   // the same as -> Result<Level, (IoError | ParseError)>
```

**`Success!Failure` is `Result<Success, Failure>`, a std enum in the prelude that holds a success value or an error** ([11](../11-compilation-model.md#the-prelude)). Its `Failure` is its **failure type**, and so is that of a function whose result type it is. The two spellings name one type, and either is valid wherever a type is. The success type comes first, as in `T?`, since Rayo writes what modifies a type after it.

**These rules say how a `Result` type is written with `!`:**

- **What follows `!` is a type name or a parenthesized type**, so an error union there is in parentheses, as in `Level!(IoError | ParseError)`.
- **`!` applies last.** `Handle<Enemy>?!LoadError` holds an optional, and a `Result` of a function type is written `(() -> Int)!LoadError`. An optional `Result` is written `(Mesh!LoadError)?`. `Mesh!LoadError?` is a compile error, since the failure type ends at its name, and an optional, which is no `Error`, could never be one.
- **A bare `!`** ends the result type of a function whose failure type is inferred ([below](#what-a-failure-type-names)).

**`Result` is an ordinary enum, so its payloads decide its conformances, as any enum's do.** It is:

- `Copyable` when `Success` and `Failure` both are ([01](../01-values-and-ownership/moves-copies-destruction.md#copyable-types)), so a `Result` holding a move-only `Level` is move-only;
- `Sendable` when both are ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)), so a loader thread can hand its outcome to another thread;
- `Frozen` when both are ([06](../06-memory-and-allocators/owning-values.md#frozen-types-with-no-interior-mutability));
- `TrivialFree` when both are ([06](../06-memory-and-allocators/allocation-lifecycle.md#releasing-a-value-without-destroying-it-trivialfree));
- scoped when either is ([02](../02-views-and-dependencies/scoped-values.md#which-types-are-scoped)).

Like every Rayo enum, it is never `Pod`, since a tag that no case uses is no value of it ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)). A `T!Never` has no tag, but isn't `Pod` either, so that no `Result` is: code that reads its bytes takes the `T` out with `try` first (below).

### What a failure type names

```swift
func tryMap<E: Error>(_ xs: Span<Int>, _ f: (Int) -> Int!E) -> List<Int>!E
func square(_ x: Int) -> Int { x * x }
let squares = tryMap(xs, square)     // square can't fail, so E is Never, and the call is a List<Int>
log("\(squares.count) squares")
```

**Three rules say what a failure type names:**

- **Error types.** A failure type conforms to `Error`, a marker protocol with no requirements; `Never` conforms too.
- **Not failing is failing with `Never`.** A `Never` failure has no values ([04](../04-types/enums.md#enums)), so every `T!Never` holds a `T`. It is laid out as `T`, with no tag ([04](../04-types/enums.md#enums)). So a function value of type `(Int) -> Int` converts to `(Int) -> Int!Never` and back at no cost ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)), and binds `E` to `Never`, as `square` does above.
- **Inferred errors.** A non-public function with a body may end its result type with a bare `!`, as in `-> Int!`. For such a function, the compiler infers the union of the error types its body can fail with, as it does for a closure literal without a written result type. Where functions call each other in a cycle, it infers the smallest such union. A function type, a requirement and any other declaration without a body name their failure type, since there is no body to infer it from.

**The errors a body can fail with are the members of what it propagates:** each `throw`, each `try` that propagates ([below](#propagating-errors-with-try)), and each `Result` it returns whole.

**A pair `R!E` of type parameters binds from a `Result` type as its two payloads, and from any other type `U` as `U!Never`, through the function-value conversion above.** So a function value returning `Int!IoError` binds `R` to `Int` and `E` to `IoError`, and one returning `Int` binds `E` to `Never`. A value argument binds the same way through the `.success` wrap ([below](#propagating-errors-with-try)), so `f(5)`, for `f<R, E>(_ x: R!E)`, binds `R` to `Int` and `E` to `Never`.

**`T!Never` is a type of its own, not another name for `T`.** So a conformance declared for `Result` never gives `T` a second one, and reflection reads a `T!Never` as the enum it is ([09](../09-compile-time/reflection.md#what-reflection-can-read)).

**A call whose result type, worked out at the call, is `T!Never` has type `T`, and so does an `await` whose awaitable's `Failure` is `Never` there** ([07](../07-concurrency/tasks.md#awaitables)). The result type is worked out after the call's generic arguments are substituted, so `tryMap(xs, square)` above is a `List<Int>`. The compiler takes the value out, which can't fail, so code that can't fail never writes `try`. A `try` on such a call is a compile error, since the call is no `Result`.

**This rule gives those two expressions their type, and converts nothing.** So a conformance, a member or an operator never sees a `T!Never` as a `T`. Generic code is checked once, so in a body generic over `E` or `X.Failure`, such a call is still an `R!E` or an `Output!Failure`, taken apart with `try`. A `T!Never` value from anywhere else, such as one a generic container stores, stays a `Result` too.

**No implicit conversion takes the `T` out of a `T!Never` value.** `try` does, and never fails on it. A `.success` pattern does too, and always matches, and `try?` gives a `T?` that is never `nil`.

**An initializer that can fail writes its result type as `-> Self!E`:**

```swift
public init(mass: Float) -> Self!PhysicsError    // a call to it evaluates to a Body!PhysicsError
```

- **It succeeds with the new value.** Reaching its end after `self.init`, or in an enum after `self` is assigned, returns `.success` of the new value ([04](../04-types/structs.md#initializers)). So does a `return` there, which takes no value. A `throw` fails it.
- **`-> Self!` infers `E`**, under the rule for a bare `!`, so only a non-public initializer with a body writes it.

**A witness that can't fail meets a requirement that can**, as `init()` meets `init() -> Self!E`. It does so through the conversion that a named function makes to such a type ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)).

```swift
protocol SeedSource { var seed: UInt64!IoError { get } }
struct FixedSeed(let seed: UInt64): SeedSource      // a stored UInt64 meets it: each read through SeedSource is a .success
```

**A property that can't fail meets a `{ get }` requirement that can.** Whatever meets `{ get }` of type `T` also meets `{ get }` of type `T!E` ([02](../02-views-and-dependencies/place-and-value-properties.md#properties-in-protocols)), as `seed` does above. It does so through the same wrapper, applied to its `get`, so a read through the requirement wraps the value in `.success`. Only a requirement with `get` alone is met this way:

- **`{ get set }` of type `T!E`** needs a witness of that type, since its `set` must take a failure too.
- **A place requirement of type `T!E`** needs a place that holds a `Result`, so a stored `T` doesn't meet it.

## Error unions

A function that can fail for more than one reason names every error type in its failure type:

```swift
func loadLevel(_ path: StringView) -> Level!(IoError | ParseError) {
    let bytes = try readFile(path)            // fails with IoError
    return try parseLevel(bytes)              // fails with ParseError
}

struct LoadReport(var lastError: (IoError | ParseError)?)
typealias Failure = (IoError | ParseError)
```

**`(IoError | ParseError)` is an error union: a tagged union with one member per error type**, laid out like an enum whose cases carry the members.

- **One set, one type.** Members are flattened and deduplicated by identity, and ordered by their `T.id`s, which no two types share ([09](../09-compile-time/reflection.md#what-reflection-can-read)), so the same set of types is the same type, with the same layout, everywhere in a program. `Never` is dropped from a union with other members, so `(Never | IoError)` is `IoError`, and a union of one type is that type.
- **An ordinary type.** Outside a function type's parameters, a union is written in parentheses, as it is after `!` and in `lastError` and `Failure` above. A value of one of its members, or of a union whose members it all has, converts to it implicitly, so assigning an `IoError` to `report.lastError` stores it ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)). It conforms to `Error`, is `Copyable`, `Sendable`, `Frozen` and `TrivialFree` exactly when every member is, and is scoped when any member is. Like a Rayo enum, it is never `Pod`, since a tag that no member uses is no value of it ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)). Its values are matched with the patterns of a `catch` ([below](#handling-errors-with-do-and-catch)).
- **Binding a type parameter in a union.** Where a union holds one type parameter, as `T!(E | IoError)` does, an argument binds it to the members of the argument's error type that the union's other members don't name, or to `Never` when none is left. So a closure that fails with `(ParseError | IoError)` binds `E` to `ParseError`, and one that fails with only `IoError`, or can't fail, binds it to `Never`. A union holding two type parameters binds neither.

## Propagating errors with `try`

```swift
func loadBossLevel(_ path: StringView) -> Level!LoadError {
    let level = try loadLevel(path)            // the level, or a return with the error, converted to LoadError
    guard level.hasBoss else { throw .badValue(field: "boss") }
    return level                               // returned as .success(level)
}
```

**A function that can fail returns success with `return` and failure with `throw`:**

- **`return v`** of a `T`, where the result type is `T!E`, returns `.success(v)`, as a value converts to `T?` ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)). A `Result` returned whole is returned as it is. Its failure type may also be one that converts implicitly to the result's, as a member converts to its union ([above](#error-unions)).
- **`throw e`** returns `.failure(e)`, converting `e`'s members as `try` does (below). Inside a `do` block, it fails the block instead ([below](#handling-errors-with-do-and-catch)).

**`try r` gives the success value of the `Result` `r`, or fails with its error.** `r` is any expression whose type is a `Result`: a call, a local or a field. On an operand of any other type, `try` is a compile error, and the operand takes no implicit conversion into a `Result`, so `let n: Int = try 5` is an error too. `try` takes `r` as a value, so a place moves in, as it does into an `owned` parameter ([01](../01-values-and-ownership/moving-values-out.md#what-can-be-moved-from)). On a `T!Never`, it gives the `T`, and never fails.

**`try` applies to the whole postfix chain after it**, as every prefix operator does ([12](../12-grammar/constructs.md#expressions)). So `try f().x` names the `x` of `f()`'s `Result`, and a member of the success value is written `(try f()).x`.

**When `try r` is expected to be a `T`, `r` is expected to be a `Result` whose success type is `T`**, with its failure type left open. So in `try deserialize(&r) as Mesh`, the `as` binds `deserialize`'s `T` to `Mesh` ([09](../09-compile-time/reflection.md#constructing-values-reflectively)).

**A `try` whose operand's failure type isn't `Never` stands in a function or closure whose result is a `Result`, or in a `do` block.** Anywhere else it is a compile error, since the error would have nowhere to go.

**A property can fail only through the value its `get` returns:**

```swift
var level: Level!IoError { get { try load(path) } }   // a get body: it propagates an IoError, or returns .success
var cache: Mesh!LoadError { borrow { slot } }         // hands out a place that holds a Result; the borrow can't fail
```

- **A `get` body is a function body**, so `try` and `throw` work in it where the property's type is a `Result`, as in `level`. A subscript's `get` works the same way.
- **Reading a value property is a call** to its `get` ([02](../02-views-and-dependencies/place-and-value-properties.md#value-properties-get-and-set)), so the rule for a call that can't fail covers it ([above](#what-a-failure-type-names)). With `var value: Int!E { get }` on a `Cell<E>`, `c.value` is an `Int` where `c` is a `Cell<Never>`.
- **A `set` can't fail.** It takes the new value and returns `Void`, so a change that must report a failure is a method.
- **A `borrow` or `mutate` body can't fail either**, since it hands out a place, and a failure is no place. So a `try` or `throw` that would leave the body is a compile error. A place property of type `T!E` hands out a place that holds a `Result`, as `cache` does. An optional place property is how one hands out no place ([02](../02-views-and-dependencies/place-and-value-properties.md#optional-places-and-tuples-of-places)).

**The error propagates member by member.** When the enclosing function infers its errors, the members join that union unchanged. Otherwise each member must be the enclosing failure type, or one of its members, or convert to it:

- **Conversion.** A member converts through the target type's `@converts` initializer whose single parameter is exactly that member, declared `owned`. The error moves in, so the new error may carry what the error borrowed, never a view of the error itself ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)). A type may have one such initializer per source type, and it can't fail. It is declared in the target type's module or the source type's, and imports form no cycle, so only one of the two can see both types, and no two modules give one pair different conversions.
- **Into a union.** When the target is a union, a member that is one of its members stays itself, and otherwise exactly one of its members may convert from it. If two could, the `try` or `throw` is an error.
- **A local lookup.** The lookup looks only at the target type, or for a generic error type at its constraints, so it stays bounded and local. With no matching initializer, the `try` is a compile error.

**`try?` and `try!`.** `try? r` gives an optional, `nil` for a failure, so it drops the error. On a `T?!E` it gives a `T??`, so a success that holds `nil` stays apart from a failure. `try! r` panics on a failure ([Panics](panics.md#what-panics)). Like `try`, each takes `r` as a value, and is a compile error on an operand that isn't a `Result`.

**Conversions in generic code.** A protocol may require a conversion, and a `try` in generic code then converts through that requirement:

```swift
protocol FromIo: Error { @converts init(_ e: owned IoError) }   // every conforming error converts from IoError

func load<E: FromIo>(_ p: StringView) -> List<UInt8>!E {
    let bytes = try readFile(p)        // readFile fails with IoError: converted through E's requirement
    ...
}
```

## Keeping an error as a value

```swift
let outcome = loadLevel(path)       // no 'try': a Level!(IoError | ParseError), kept as a value
loader.report(outcome)              // handed on: whoever takes it apart handles the error
loadLevel(path)                     // error: the Result is never used
_ = loadLevel(path)                 // fine: the outcome is dropped on purpose
```

**A call written without `try` evaluates to its `Result`**, so code keeps an error by leaving `try` out. It can store the `Result`, move it to another thread, and take it apart later with `try` or `when`.

**A `Result` that is never used is a compile error, as every unused value whose type isn't `Void` or `Never` is** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unused-values)). So no error is dropped without the code saying so, however deeply a value holds it, as in the `(Void!IoError)?` that `player?.save()` gives. `_ = r` drops one on purpose.

**A closure literal called in place turns a block of `try`s into one `Result`**, since its body fails as the body of a function with a bare `!` does ([above](#what-a-failure-type-names)). So `Result` needs no other way to run code and keep its error:

```swift
let outcome = {
    let bytes = try readFile(path)
    return try parseLevel(bytes)
}()                                 // a Level!(IoError | ParseError): the first failure, kept as a value
```

**A `Result` is an ordinary enum, so `when`, `if case` and `guard case` match it as they match any enum** ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)). A pattern on `.failure` matches an error union with the patterns of a `catch` ([below](#handling-errors-with-do-and-catch)). A place subject is borrowed, so a `when` reads a `Result` the code only borrows, which `try` can't take, and binds its payload in place:

```swift
func show(_ outcome: Level!(IoError | ParseError)) {
    let first = try? outcome                                    // error: 'outcome' is borrowed, and 'try?' takes it
    when outcome {
        .success(let level) { preview(level) }                  // looks at the level in place
        .failure(IoError.missing) { showMissingFileDialog() }
        .failure(let e as ParseError) { log("parse error at \(e.offset)") }
        .failure { showDiskErrorDialog() }                      // the rest of IoError
    }
}
```

`try copy r` takes a copy of a copyable `Result` instead.

## Handling errors with `do` and `catch`

```swift
do {
    let level = try loadLevel(path)           // the do block's error type: IoError | ParseError
    start(level)
} catch IoError.missing {                      // one case of one member, qualified by its type
    showMissingFileDialog()
} catch is IoError {                           // the rest of IoError
    showDiskErrorDialog()
} catch let e as ParseError {                  // a whole member, by type
    log("parse error at \(e.offset)")
}

func loadOrDefault(_ path: StringView) -> Level!IoError {
    do {
        return try loadLevel(path)
    } catch is ParseError {                    // ParseError is handled here...
        return Level()
    }                                          // ...and IoError propagates, as a 'try' would
}
```

**A `do` block's error type is the union of what its body's `try`s and `throw`s propagate, and its `catch` clauses handle it member by member.**

- **Matching.** A clause matches one member by type (`catch let e as IoError`, `catch is ParseError`), or by one of its cases, with the patterns, `where` guards and coverage of a `when` arm ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)). An unqualified case, such as `.notFound`, must name a case of exactly one member, and otherwise must be qualified, as in `catch IoError.missing`. A `catch` with no pattern, or with `_` or `let e`, matches whatever the earlier clauses leave, and `let e` binds it as the union of the members it can be.
- **Exhaustiveness.** It is checked member by member, with a `when` arm's coverage. What no clause covers, whole members and the rest of a partly covered one, propagates from the `do` as a `try` would. Where nothing can propagate, in a function that can't fail or in a `defer` block, the clauses must cover every member.

## Cleanup

**These rules say when a `defer` block runs, and what its body may do:**

- **`defer { }` runs on every scope exit.** An error return is one, and so is a panic's unwind ([Panics](panics.md#unwinding)). It runs where the destruction order places it ([01](../01-values-and-ownership/moves-copies-destruction.md#destruction)).
- **Control leaves a `defer` block early only by a panic.** A `return`, a `throw`, a `try` that propagates, and a `break` or `continue` that targets a loop outside the block are compile errors in it. It may call a function that never returns, such as `fatalError`, whose panic unwinds out of the block, except where an unwind runs it ([Panics](panics.md#what-ends-the-program)).
- **A `defer` body is checked as if written at each point where it may run.** Those are these points in its scope, so it uses only what every one of them allows:
    - every exit, a propagating `try` or `throw` included;
    - every point that can panic, each property accessor's call included, as the unwind leaves it ([Panics](panics.md#unwinding));
    - in a `task` function, every `await` it is live across, where destroying the task runs it ([07](../07-concurrency/tasks.md#semantics)).
