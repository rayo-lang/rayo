# 10 · Errors and safety

Rayo gives expected failures and broken assumptions different paths. An expected failure, such as a missing file, is a **recoverable error**: a typed value that the caller must handle. A broken assumption, such as dereferencing a stale handle, **panics** ([Panics](10-errors-and-safety/panics.md#panics)). The language also defines which checks run in each build and where code must take responsibility with `unsafe`.

```swift
enum ConfigError: Error {
    case notFound
    case badValue(field: StaticString)
}

func loadConfig(_ path: StringView) throws(ConfigError) -> Config { ... }   // the signature names the error type

do {
    settings = try loadConfig(path)       // a missing file is expected: it comes back as a value
} catch .notFound {
    settings = Config()                   // fall back to the defaults
} catch .badValue(let field) {
    log("bad value for \(field)")
}

let pos = borrow enemies[target]!.pos     // a stale handle here is a bug: '!' panics
```

The type in `loadConfig`'s signature tells the caller which failures it may catch. The `catch` arms handle them as values; the `!` on the last line takes the panic path if the handle has gone stale.

## Subchapters

- [Typed errors](10-errors-and-safety/typed-errors.md)
- [Panics](10-errors-and-safety/panics.md)
- [Unsafe code](10-errors-and-safety/unsafe-code.md)
- [Checks and build modes](10-errors-and-safety/checks-and-build-modes.md)
