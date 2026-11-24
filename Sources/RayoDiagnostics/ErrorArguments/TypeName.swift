/// A type as an error names it: `Int`, or `the prelude's Int` where a struct or a function of the file has its name.
public enum TypeName: Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    /// A type whose name alone identifies it.
    case named(String)
    /// A prelude type whose name a struct or a function of the file also has.
    case shadowedPrelude(String)

    public init(stringLiteral name: String) { self = .named(name) }

    public var description: String {
        switch self {
        case .named(let name): name
        case .shadowedPrelude(let name): "the prelude's \(name)"
        }
    }

    /// The name with `the` before it, as in `the Int value`. A shadowed prelude type's, `the prelude's Int`, has
    /// its own.
    public var definite: String {
        switch self {
        case .named(let name): "the \(name)"
        case .shadowedPrelude: description
        }
    }

    /// The name with `a` or `an` before it, as in `a UInt` or `an Int`. A shadowed prelude type's, `the prelude's
    /// Int`, has its own.
    public var withArticle: String {
        switch self {
        case .named(let name): "\(Self.article(of: name)) \(name)"
        case .shadowedPrelude: description
        }
    }

    /// The article that goes before `name`: `an` where the name starts with a vowel's sound, and `a` elsewhere. A
    /// `U` is read as "you", as in `UInt`, so it takes `a`.
    private static func article(of name: String) -> String {
        guard let first = name.first, "AEIOaeio".contains(first) else { return "a" }
        return "an"
    }

    /// The name with the word `type` before it, as in `the local 'x' can't have type Void`, or, for a shadowed prelude
    /// type, `the prelude's type Void`.
    public var typePhrase: String {
        switch self {
        case .named(let name): "type \(name)"
        case .shadowedPrelude(let name): "the prelude's type \(name)"
        }
    }
}
