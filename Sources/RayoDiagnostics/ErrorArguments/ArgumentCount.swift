/// How many arguments a function takes, as an error names it: `1 argument`, `2 arguments`.
public struct ArgumentCount: Sendable, Hashable, ExpressibleByIntegerLiteral, CustomStringConvertible {
    public var count: Int

    public init(_ count: Int) { self.count = count }
    public init(integerLiteral count: Int) { self.count = count }

    public var description: String { count == 1 ? "1 argument" : "\(count) arguments" }
}
