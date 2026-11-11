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
                var c = 0
                c = b
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

    @Test("a loop's body that assigns a local after moving it gives the next pass the value it assigned")
    func loops() {
        #expect(output("var i = 0\nvar x = 1\nwhile i < 2 {\ni += 1\nlet y = x\nprint(y)\nx = 2\n}") == "1\n2\n")
    }

    @Test("a path that returns after a move leaves the local's value on the others")
    func returnsAfterMove() {
        let source = """
            func main() {
                f(true)
                f(false)
            }
            func f(_ c: Bool) {
                let x = 1
                if c {
                    let y = x
                    return
                }
                print(x)
            }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "1\n", errors: ""))
    }

    @Test("an argument is borrowed, not moved, so the local keeps its value")
    func argumentsBorrow() {
        #expect(output("let x = 1\nprint(x)\nprint(x + x)\nlet y = x\nprint(y)") == "1\n2\n1\n")
    }
}
