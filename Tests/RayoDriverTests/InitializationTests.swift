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
}
