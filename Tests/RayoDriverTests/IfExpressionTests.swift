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
}
