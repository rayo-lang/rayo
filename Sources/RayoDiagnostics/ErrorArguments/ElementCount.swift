/// How many elements an array holds, as an error names it: `1 element`, `2 elements`.
public struct ElementCount: Sendable, Hashable, ExpressibleByIntegerLiteral, CustomStringConvertible {
    public var count: Int

    public init(_ count: Int) { self.count = count }
    public init(integerLiteral count: Int) { self.count = count }

    public var description: String { count == 1 ? "1 element" : "\(count) elements" }
}
