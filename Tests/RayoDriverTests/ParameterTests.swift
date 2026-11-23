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

    // A `ref let` and a parameter that borrows its argument each hold a reference, which the function that borrows
    // takes as it is, as it takes an `if` whose every branch ends in such a place, while a place that holds a value
    // reaches the function that owns it. An `if` with a branch written with `&` gives a reference there, which the
    // function that owns its argument can't take, so it reaches the function that borrows it.
    @Test func `a place that holds a reference, given bare, reaches the function that borrows it`() {
        let source = """
            func main() {
                let a = 1
                let c = true
                ref let r = &a
                ref let s = &a
                show(a)
                show(r)
                relay(a)
                show(if c { r } else { s })
                show(if c { r } else { a })
                show(if c { a } else { &a })
                show(if c { r } else { &a })
            }
            func relay(_ n: &Int) { show(n) }
            func show(_ n: Int) { print(n + 10) }
            func show(_ n: &Int) { print(n + 20) }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "11\n21\n21\n21\n11\n21\n21\n", errors: ""))
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

    @Test func `'print' is lent a place or a value that no local holds, and prints what it is lent`() {
        let source = """
            func main() {
                let hp = 7
                let e = Enemy(hp: 2)
                let alive = true
                print(hp)
                print(&hp)
                print(e.hp)
                print(hitsToFell(e, by: 1))
                print(Enemy(hp: 4).hp)
                print(alive)
                print(UInt(hp))
            }
            struct Enemy(var hp: Int)
            func hitsToFell(_ e: &Enemy, by damage: Int) -> Int { e.hp / damage }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "7\n7\n2\n2\n4\ntrue\n7\n", errors: ""))
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
