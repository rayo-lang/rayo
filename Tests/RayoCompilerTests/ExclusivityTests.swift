import RayoDiagnostics
import Testing

@Suite("Accesses that conflict")
struct ExclusivityTests {
    @Test func `a borrowed argument's place can't change while the arguments after it are evaluated`() {
        // The call borrows `x` from where its first argument is evaluated, so the second can't assign it.
        let body = """
                var x = 1
                add(x, if x > 0 { x = 2; 1 } else { 3 })
            """
        let source = mainSource(body) + "\nfunc add(_ a: Int, _ b: Int) {}"
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.changedWhileBorrowed(name: "x", borrowed: "x")])
        #expect(coveredText(reported, in: source) == ["x"])
        #expect(reported.map(\.notes) == [["3:9: note: borrowed here"]])
    }

    @Test func `a place can change once the call that borrows it has returned, and take what the call gives`() {
        let body = """
                var x = 1
                x = double(x)
                print(x)
                x = 3
                print(double(x))
            """
        #expect(errors(mainSource(body) + "\nfunc double(_ n: Int) -> Int { n * 2 }") == [])
    }
}
