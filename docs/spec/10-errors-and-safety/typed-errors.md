# Typed `throws`

[10 · Errors and safety](../10-errors-and-safety.md)

A function that can fail in an expected way reports the failure to its caller as a value, and its signature says which errors it can throw:

```swift
enum LoadError: Error {
    case notFound(path: StaticString)
    case corrupt(offset: Int)
    case unknownCase(Name)                  // reflective loaders (09)
    case badValue(field: StaticString)
    case outOfMemory
}

func loadMesh(_ path: StringView) throws(LoadError) -> Mesh {
    let bytes = try readFile(path)                      // readFile throws(IoError); converted below
    guard bytes.count >= MeshHeader.size else { throw .corrupt(offset: 0) }
    ...
}

extension LoadError {                                   // enables 'try' across error types
    @converts init(_ e: owned IoError) { self = if e == .missing { .notFound(path: "?") } else { .corrupt(offset: -1) } }
    @converts init(_ e: owned ParseError) { self = .corrupt(offset: e.offset) }
}
```

**A public function's `throws` names its error type, and throwing costs the same as returning:** a throwing function returns its result or its error as a tagged union, with no unwinding and no allocation.

**Three rules say what a `throws` clause names:**

- **Error types.** A type a function throws conforms to `Error`, a marker protocol with no requirements; `Never` conforms too.
- **Not throwing is throwing `Never`.** A function type that doesn't throw is the one that throws `Never` ([04](../04-types/enums.md#enums)). So a function value that doesn't throw binds a thrown type parameter to `Never`, as `abs` does below.
- **Inferred errors.** A non-public function with a body may write bare `throws`. For such a function, the compiler infers the union of the error types its body can throw, as it does for a closure literal. Where functions call each other in a cycle, it infers the smallest such union. A function type, a requirement and any other declaration without a body name their error type, since there is no body to infer it from.

```swift
func tryMap<E: Error>(_ xs: Span<Int>, _ f: (Int) throws(E) -> Int) throws(E) -> List<Int>
func square(_ x: Int) -> Int { x * x }
let squares = tryMap(xs, square)     // square throws nothing, so E is Never
```

## Error unions

A function that can fail for more than one reason names every error type in its `throws`:

```swift
func loadLevel(_ path: StringView) throws(IoError | ParseError) -> Level {
    let bytes = try readFile(path)            // throws IoError
    return try parseLevel(bytes)              // throws ParseError
}

struct LoadReport(var lastError: (IoError | ParseError)?)   // outside 'throws', a union is written in parentheses
typealias Failure = (IoError | ParseError)
```

**`throws(IoError | ParseError)` names an error union: a tagged union with one member per error type**, laid out like an enum whose cases carry the members.

- **One set, one type.** Members are flattened and deduplicated by identity, and ordered by their `T.id`s, which no two types share ([09](../09-compile-time/reflection.md#what-reflection-can-read)), so the same set of types is the same type, with the same layout, everywhere in a program. `Never` is dropped from a union with other members, so `(Never | IoError)` is `IoError`, and a union of one type is that type.
- **An ordinary type.** Outside `throws` and a function type's parameters, a union is written in parentheses, as `lastError` and `Failure` are above. A value of one of its members, or of a union whose members it all has, converts to it implicitly, so assigning an `IoError` to `report.lastError` stores it ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)). It conforms to `Error`, is `Copyable`, `Sendable`, `Frozen` and `TrivialFree` exactly when every member is, and is scoped when any member is. Like a Rayo enum, it is never `Pod`, since a tag that no member uses is no value of it ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)). Its values are matched with the patterns of a `catch` ([below](#handling-errors-with-do-and-catch)).
- **Binding a type parameter in a union.** Where a union holds one type parameter, as `throws(E | IoError)` does, an argument binds it to the members of the argument's error type that the union's other members don't name, or to `Never` when none is left. So a closure that throws `(ParseError | IoError)` binds `E` to `ParseError`, and one that throws only `IoError`, or nothing, binds it to `Never`. A union holding two type parameters binds neither.

## Propagating errors with `try`

**`try f()` propagates, member by member**, and `throw e` throws `e`'s members the same way. When the enclosing function infers its errors, the members join that union unchanged. Otherwise each member must be the enclosing function's error type, or one of its members, or convert to it:

- **Conversion.** A member converts through the target type's `@converts` initializer whose single parameter is exactly that member, declared `owned`. The thrown value moves in, so the new error may carry what the thrown value borrowed, never a view of the thrown value itself ([02](../02-views-and-dependencies/dependency-rules/absorption-and-accesses.md#rule-5-the-callee-side)). A type may have one such initializer per source type, and it neither throws nor fails. It is declared in the target type's module or the source type's, and imports form no cycle, so only one of the two can see both types, and no two modules give one pair different conversions.
- **Into a union.** When the target is a union, a thrown member that is one of its members stays itself, and otherwise exactly one of its members may convert from it. If two could, the `try` or `throw` is an error.
- **A local lookup.** The lookup looks only at the target type, or for a generic error type at its constraints, so it stays bounded and local. With no matching initializer, the `try` is a compile error.

**`try?` and `try!`.** `try? f()` gives an optional. `try! f()` panics on an error.

**Conversions in generic code.** A protocol may require a conversion, and a `try` in generic code then converts through that requirement:

```swift
protocol FromIo: Error { @converts init(_ e: owned IoError) }   // every conforming error converts from IoError

func load<E: FromIo>(_ p: StringView) throws(E) -> List<UInt8> {
    let bytes = try readFile(p)        // readFile throws IoError: converted through E's requirement
    ...
}
```

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

func loadOrDefault(_ path: StringView) throws(IoError) -> Level {
    do {
        return try loadLevel(path)
    } catch is ParseError {                    // ParseError is handled here...
        return Level()
    }                                          // ...and IoError propagates, as a 'try' would
}
```

**A `do` block's error type is the union of what its body throws, and its `catch` clauses handle it member by member.**

- **Matching.** A clause matches one member by type (`catch let e as IoError`, `catch is ParseError`), or by one of its cases, with the patterns, `where` guards and coverage of a `when` arm ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)). An unqualified case, such as `.notFound`, must name a case of exactly one member, and otherwise must be qualified, as in `catch IoError.missing`. A `catch` with no pattern, or with `_` or `let e`, matches whatever the earlier clauses leave, and `let e` binds it as the union of the members it can be.
- **Exhaustiveness.** It is checked member by member, with a `when` arm's coverage. What no clause covers, whole members and the rest of a partly covered one, propagates from the `do` as a `try` would. Where nothing can propagate, in a function that doesn't throw or in a `defer` block, the clauses must cover every member.

## Cleanup

**These rules say when a `defer` block runs, and what its body may do:**

- **`defer { }` runs on every scope exit.** An error return is one, and it runs where the destruction order places it ([01](../01-values-and-ownership/moves-copies-destruction.md#destruction)).
- **Control never leaves a `defer` block early.** A `return`, a `throw`, a `try` that propagates, and a `break` or `continue` that targets a loop outside the block are compile errors in it. It may call a function that never returns, such as `fatalError`.
- **A `defer` body is checked as if written at each point where it may run.** Those are every exit of its scope, a propagating `try` or `throw` included, and, in a `task` function, every `await` it is live across, where destroying the task runs it ([07](../07-concurrency/tasks.md#semantics)). So it uses only what every one of those points allows.
