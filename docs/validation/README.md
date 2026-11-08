# Validate the language design

The [spec](../spec/README.md) defines Rayo. These documents check its rules while the language is designed and later when it is implemented. They are nonnormative: when a check exposes a missing or conflicting rule, the spec must be corrected.

- [Safety argument](safety-argument.md) traces the rules to the invariants that keep safe code free of undefined behavior. It is an informal argument, not a mechanically verified proof.
- [Hard cases](hard-cases.md) test whether the rules admit useful systems programs at a reasonable cost. Each case asks for code and a verdict, and can be exercised again against an implementation.
