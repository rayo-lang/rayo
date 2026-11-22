import Testing
import RayoDriver

struct MoveTests {
    @Test("a declaration, an assignment and a 'return' move a local's value, in debug and in release",
          arguments: [["--debug"], ["--release"]])
    func moves(mode: [String]) {
        let source = """
            func main() {
                var a = 1
                let b = a
                a = 2
                var c: Int
                c = consume b
                print(a)
                print(c)
                print(answer())
            }
            func answer() -> Int {
                let x = 42
                return x
            }
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "2\n1\n42\n", errors: ""))
    }
}
