import Testing

/// A struct, and functions that take and give arrays, which the bodies below use.
private let declarations = """
    struct Hit(var damage: Int)
    func sum(_ a: [2 of Int]) -> Int { 0 }
    func none(_ a: [0 of Bool]) {}
    func pick(_ a: [2 of Int]) {}
    func pick(_ a: [3 of Int]) {}
    func made() -> [2 of Int] { .init(repeating: 1) }
    func returned() -> [2 of Bool] { return .init(repeating: true) }
    struct Holder(var hits: [2 of Hit])
    """

struct ArrayLiteralTests {
    @Test func `an element of an array literal is moved into the array, as a struct's field is`() {
        #expect(errors("func main() {\nlet h = Hit(damage: 1)\n_ = [h]\n_ = h\n}\n" + declarations) == [
            .usedAfterMove(name: "h"),
        ])
    }
}

struct ArrayInitializerTests {
    @Test func `the value an array is filled with is copied into it, so it is borrowed and stays usable`() {
        let source = """
            func main() {
            let h = Hit(damage: 1)
            let a: [2 of Hit] = .init(repeating: h)
            _ = a
            _ = h
            }

            """
        #expect(errors(source + declarations) == [])
    }

    @Test func `a value that was moved can't fill an array`() {
        let source = """
            func main() {
            let h = Hit(damage: 1)
            _ = h
            let a: [2 of Hit] = .init(repeating: h)
            _ = a
            }

            """
        #expect(errors(source + declarations) == [.usedAfterMove(name: "h")])
    }
}
