import Testing
import RayoDriver

struct ParameterTests {
    @Test("a call passes its arguments to the parameters in order, labeled as the parameters are declared")
    func labels() {
        let source = """
            func main() {
                print(difference(from: 10, take: 3))
                print(scaled(4, by: 5))
            }
            func difference(from a: Int, take b: Int) -> Int { a - b }
            func scaled(_ value: Int, by: Int) -> Int { value * by }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "7\n20\n", errors: ""))
    }

    @Test func `a lent argument reaches the function that borrows it, and a bare one the function that owns it`() {
        let source = """
            func main() {
                let a = 1
                show(a)
                show(&a)
            }
            func show(_ n: Int) { print(n + 10) }
            func show(_ n: &Int) { print(n + 20) }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "11\n21\n", errors: ""))
    }

    @Test func `a place given to a '&T' parameter without '&' is lent, and stays its caller's`() {
        let source = """
            func main() {
                var boss = Enemy(stats: Stats(hp: 7), slots: [1, 2])
                show(boss)
                boss.stats.hp = 9
                show(boss)
                print(total(boss.slots))
            }
            struct Enemy(var stats: Stats, var slots: [2 of Int])
            struct Stats(var hp: Int)
            func show(_ e: &Enemy) { print(hpOf(e.stats)) }
            func hpOf(_ s: &Stats) -> Int { s.hp }
            func total(_ a: &[2 of Int]) -> Int { a[0] + a[1] }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "7\n9\n3\n", errors: ""))
    }

    @Test func `a bare argument that every overload borrows tells none of them apart`() {
        let source = """
            func main() {
                let a = 1
                show(a, a)
                show(a, &a)
            }
            func show(_ n: &Int, _ m: Int) { print(n + m + 10) }
            func show(_ n: &Int, _ m: &Int) { print(n + m + 20) }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "12\n22\n", errors: ""))
    }

    @Test("functions recurse, directly and through each other, in debug and in release",
          arguments: [["--debug"], ["--release"]])
    func recursion(mode: [String]) {
        // `sum` recurses a hundred thousand calls deep, which the stack that linking gives the program must hold.
        let source = """
            func main() {
                print(fibonacci(20))
                if isEven(7) { print(1) } else { print(0) }
                print(sum(to: 100000))
            }
            func fibonacci(_ n: Int) -> Int {
                if n < 2 { return copy n }
                return fibonacci(n - 1) + fibonacci(n - 2)
            }
            func isEven(_ n: Int) -> Bool {
                if n == 0 { return true }
                return isOdd(n - 1)
            }
            func isOdd(_ n: Int) -> Bool { n != 0 && isEven(n - 1) }
            func sum(to n: Int) -> Int {
                if n == 0 { return 0 }
                return n + sum(to: n - 1)
            }
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "6765\n0\n5000050000\n", errors: ""))
    }
}
