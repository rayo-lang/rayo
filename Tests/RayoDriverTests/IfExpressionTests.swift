import Testing
import RayoDriver

struct IfExpressionTests {
    @Test("a 'let' binds the value of the branch that runs, in debug and in release",
          arguments: [["--debug"], ["--release"]])
    func binds(mode: [String]) {
        let source = """
            func main() {
                pick(true)
                pick(false)
            }
            func pick(_ c: Bool) {
                let y = if c { 10 } else { 20 }
                print(y)
            }
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "10\n20\n", errors: ""))
    }

    @Test("an 'if' gives its value to a 'return', an argument, an initializer, an operator, another 'if' and '_ ='",
          arguments: [
        ("print(sign(-4))\nprint(sign(0))\nprint(sign(if c { 5 } else { -5 }))", "-1\n0\n1\n"),
        ("let p = Point(x: if c { 3 } else { 4 }, y: 5)\nprint(p.x)", "3\n"),
        ("print(1 + if c { 10 } else { 20 })\nprint(-if c { 6 } else { 7 })", "11\n-6\n"),
        ("let n = if c { if !c { 1 } else { 2 } } else { 3 }\nprint(n)", "2\n"),
        ("var x: Int\nx = if c { 8 } else { 9 }\nx += if c { 1 } else { 0 }\nprint(x)", "9\n"),
        ("let n = if c {\nlet t = 4\nt * t\n} else {\n0\n}\nprint(n)", "16\n"),
        ("_ = if c { print(7) } else { print(8) }", "7\n"),
    ])
    func positions(body: String, expected: String) {
        let source = """
            func main() {
            let c = true
            \(body)
            }
            func sign(_ n: Int) -> Int {
                return if n < 0 { -1 } else if n > 0 { 1 } else { 0 }
            }
            struct Point(var x: Int, var y: Int)
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: expected, errors: ""))
    }

    @Test("an 'else if' chain that ends in 'else' gives the value of the first branch whose condition holds",
          arguments: [(1, "10\n"), (2, "20\n"), (3, "0\n")])
    func elseIf(value: Int, expected: String) {
        #expect(output("""
            let n = \(value)
            let y = if n == 1 { 10 } else if n == 2 { 20 } else { 0 }
            print(y)
            """) == expected)
    }

    @Test("a branch that ends in 'return', 'break' or 'continue' leaves, and the other gives the value")
    func leavingBranches() {
        let source = """
            func main() {
                print(half(8))
                print(half(7))
                var i = 0
                var sum = 0
                while true {
                    i += 1
                    let odd = if i % 2 == 0 { continue } else { copy i }
                    let next = if odd > 7 { break } else { odd }
                    sum += next
                }
                print(sum)
            }
            func half(_ n: Int) -> Int {
                let even = if n % 2 == 0 { copy n } else { return -1 }
                return even / 2
            }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "4\n-1\n16\n", errors: ""))
    }

    @Test("a branch that ends in a local gives the local's value whole, and an argument only borrows it",
          arguments: [(true, "1\n2\n1\n"), (false, "3\n4\n3\n")])
    func locals(chosen: Bool, expected: String) {
        let source = """
            func main() {
                let a = Point(x: 1, y: 2)
                let b = Point(x: 3, y: 4)
                let c = \(chosen)
                show(if c { a } else { b })
                let p = if c { a } else { b }
                print(p.x)
            }
            func show(_ p: Point) {
                print(p.x)
                print(p.y)
            }
            struct Point(var x: Int, var y: Int)
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: expected, errors: ""))
    }
}
