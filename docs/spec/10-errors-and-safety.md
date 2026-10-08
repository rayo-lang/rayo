# 10 · Errors and safety

A **recoverable error**, such as a missing file, is a typed value that the caller must handle. A **bug**, such as dereferencing a stale handle, **panics** ([Panics](10-errors-and-safety/panics.md#panics)).

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

## Subchapters

- [Typed errors](10-errors-and-safety/typed-errors.md)
- [Panics](10-errors-and-safety/panics.md)
- [Unsafe code](10-errors-and-safety/unsafe-code.md)
- [Checks and build modes](10-errors-and-safety/checks-and-build-modes.md)
