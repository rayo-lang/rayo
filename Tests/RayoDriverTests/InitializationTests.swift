import Testing
import RayoDriver

struct InitializationTests {
    @Test("a local declared without a value is given one later, in debug and in release",
          arguments: [["--debug"], ["--release"]])
    func lateInitialization(mode: [String]) {
        let source = """
            func main() {
                let lo: Int, hi: Int
                lo = 1
                hi = 2
                var sum: Int
                sum = lo + hi
                sum = sum * 10
                sum += 4
                print(sum)
                print(pick(true))
                print(pick(false))
            }
            func pick(_ first: Bool) -> Int {
                let picked: Int
                if first {
                    picked = 1
                } else {
                    picked = 2
                }
                return picked
            }
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "34\n1\n2\n", errors: ""))
    }

    @Test("a declaration's bindings are declared in order, so a later one may take an earlier one's value")
    func severalBindings() {
        #expect(output("let a = 1, b = copy a + 1, c: Int\nc = a + b\nprint(c)") == "3\n")
    }

    @Test("a path that returns before a local is used needs no value in it")
    func returnsBeforeUse() {
        let source = """
            func main() {
                print(f(true))
                print(f(false))
            }
            func f(_ c: Bool) -> Int {
                let x: Int
                if c {
                    x = 5
                } else {
                    return 0
                }
                return x
            }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "5\n0\n", errors: ""))
    }

    @Test("a loop that a 'break' leaves only once the body has assigned a local leaves it initialized")
    func breakAfterAssignment() {
        let body = """
            let x: Int
            var i = 0
            while true {
                i += 1
                if i == 3 {
                    x = copy i
                    break
                }
            }
            print(x)
            """
        #expect(output(body) == "3\n")
    }

    @Test("a local declared in a loop's body is a new local on each pass", arguments: [["--debug"], ["--release"]])
    func declaredInLoop(mode: [String]) {
        let source = """
            func main() {
                var i = 0
                while i < 3 {
                    i += 1
                    let x: Int
                    x = i * 10
                    print(x)
                }
            }
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "10\n20\n30\n", errors: ""))
    }

    @Test("a 'var' is assigned any number of times, and one that was moved holds the value assigned after")
    func varAssignedOften() {
        #expect(output("var x: Int\nx = 1\nlet y = x\nx = 2\nx = x + y\nprint(x)\nprint(y)") == "3\n1\n")
    }
}
