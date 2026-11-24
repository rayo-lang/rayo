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

    // An `if` that ends in a shared reference, or has a branch written `&`, reaches it too; a bare value doesn't.
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

/// A struct and an array type, and functions that make values of them, for programs whose functions own them.
private let ownedTypes = """
    struct Enemy(var stats: Stats, var slots: [2 of Int])
    struct Stats(var hp: Int)
    func makeEnemy(hp: Int) -> Enemy { Enemy(stats: Stats(hp: copy hp), slots: [1, 2]) }
    """

struct OwningParameterTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `a parameter that owns a struct or an array takes a moved place, a copy, or a value`(mode: [String]) {
        let source = """
            func main() {
                let boss = makeEnemy(hp: 7)
                print(keep(copy boss))
                print(keep(makeEnemy(hp: 3)))
                print(keep(Enemy(stats: Stats(hp: 4), slots: [5, 6])))
                print(keep(consume boss))
                let slots: [2 of Int] = [10, 20]
                print(total(copy slots))
                print(total([30, 40]))
                print(total(consume slots))
            }
            func keep(_ e: Enemy) -> Int { e.stats.hp }
            func total(_ a: [2 of Int]) -> Int { a[0] + a[1] }
            \(ownedTypes)
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "7\n3\n4\n7\n30\n70\n30\n",
                                                            errors: ""))
    }

    // The caller's copy stays as it was, whatever the function does with its own.
    @Test func `a function changes and lends the struct its parameter owns, and its fields and elements`() {
        let source = """
            func main() {
                let boss = makeEnemy(hp: 7)
                print(changed(copy boss))
                print(boss.stats.hp + boss.slots[0])
                print(replaced(consume boss))
            }
            func changed(_ e: Enemy) -> Int {
                e.stats.hp += 10
                e.slots[0] = 100
                e.stats = Stats(hp: e.stats.hp * 2)
                return hpOf(e) + e.slots[0] + e.slots[1]
            }
            func hpOf(_ e: &Enemy) -> Int { e.stats.hp }
            func replaced(_ e: Enemy) -> Int {
                print(e.stats.hp)
                e = makeEnemy(hp: 40)
                return e.stats.hp
            }
            \(ownedTypes)
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "136\n8\n7\n40\n", errors: ""))
    }

    @Test func `a function passes the struct its parameter owns on, stores it, and returns it`() {
        let source = """
            func main() {
                let squad = enlist(makeEnemy(hp: 5))
                print(squad.lead.stats.hp)
                let back = handBack(makeEnemy(hp: 6))
                print(back.stats.hp)
                print(passOn(makeEnemy(hp: 8)))
                print(splitStats(makeEnemy(hp: 9)).hp)
            }
            struct Squad(var lead: Enemy)
            func enlist(_ e: Enemy) -> Squad { Squad(lead: consume e) }
            func handBack(_ e: Enemy) -> Enemy {
                e.stats.hp += 1
                return consume e
            }
            func passOn(_ e: Enemy) -> Int { keep(consume e) }
            func keep(_ e: Enemy) -> Int { e.stats.hp * 10 }
            func splitStats(_ e: Enemy) -> Stats {
                let s = consume e.stats
                print(e.slots[1])
                return consume s
            }
            \(ownedTypes)
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "5\n7\n80\n2\n9\n", errors: ""))
    }

    @Test func `a lent struct reaches the overload that borrows it, and a moved one the overload that owns it`() {
        let source = """
            func main() {
                let boss = makeEnemy(hp: 3)
                show(&boss)
                show(copy boss)
                show(consume boss)
            }
            func show(_ e: Enemy) { print(e.stats.hp + 10) }
            func show(_ e: &Enemy) { print(e.stats.hp + 20) }
            \(ownedTypes)
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "23\n13\n13\n", errors: ""))
    }
}
