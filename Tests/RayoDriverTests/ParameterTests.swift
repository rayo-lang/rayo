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

    @Test func `a call that lends its argument reaches the function that borrows it, and one that doesn't, the other`() {
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
