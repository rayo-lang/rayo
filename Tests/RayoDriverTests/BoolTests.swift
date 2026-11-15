import Testing
import RayoDriver

struct BoolTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `print writes the value of a Bool that a program computes`(mode: [String]) {
        let source = """
            func main() {
                let alive = isAlive(hp: 3)
                print(alive)
                print(!alive)
                print(2 * 3 < 5)
                print(isAlive(hp: 0) || 1 == 1)
            }
            func isAlive(hp: Int) -> Bool { hp > 0 }
            """
        #expect(run(source, options: mode) ==
            CommandResult(exitCode: 0, output: "true\nfalse\nfalse\ntrue\n", errors: ""))
    }
}
