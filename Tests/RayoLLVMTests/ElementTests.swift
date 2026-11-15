import RayoLLVM
import Testing

@Suite("Running reads and stores of an array's elements")
struct ElementTests {
    @Test(arguments: [Build.debug, .release])
    func `an index outside the array panics at the index, in every build`(build: Build) throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 a: [3 of Int]
              var %1 i: UInt
              temp %2: UInt
            bb0:
              %0 @1:1-1:2 = array of Int(1, 2, 3) @1:1-1:2
              %1 @1:1-1:2 = operand UInt 3 @1:1-1:2
              _ = call builtin "print(_: Int)"(1) @1:1-1:2
              %2 @1:1-1:2 = index read %1 @1:1-1:2 below 3 @5:19-5:20
              _ = call builtin "print(_: Int)"(read %0[%2] @1:1-1:2) @1:1-1:2
              return
            }
            """
        #expect(try run(text, in: build) == .init(printed: "1\n", panic: "main.rayo:5:19: panic: index out of range\n"))
    }
}
