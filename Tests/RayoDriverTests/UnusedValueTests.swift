import Testing
import RayoDriver

struct UnusedValueTests {
    @Test("'_ =' drops a value on purpose, which is still computed")
    func dropped() {
        let source = """
            func main() {
                _ = say(1)
                _ = print(2)
                let x = 3
                _ = copy x
            }
            func say(_ x: Int) -> Int {
                print(x)
                return copy x
            }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "1\n2\n", errors: ""))
    }
}
