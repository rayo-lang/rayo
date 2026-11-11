import Testing
import RayoDriver

struct StructTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `a struct's name is a type, which locals, parameters and results may have, in debug and in release`(
        mode: [String],
    ) {
        let source = """
            func main() {
                var shot: Shot
                print(1)
            }
            func relay(_ s: Shot) -> Shot { kept(s) }
            func kept(_ s: Shot) -> Shot {
                var k: Shot
                k = copy s
                let t = k
                return t
            }
            struct Shot(var hit: Hit, let team: Bool)
            struct Hit(var damage: Int)
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "1\n", errors: ""))
    }

    @Test func `a local may share a struct's name, which a type names the struct by, and any other use the local`() {
        let body = "let S = 2\nvar s: S\nprint(S)"
        #expect(run("func main() {\n\(body)\n}\nstruct S(var a: Int)") ==
            CommandResult(exitCode: 0, output: "2\n", errors: ""))
    }
}
