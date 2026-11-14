import RayoDiagnostics
import Testing

@Suite("Accesses that conflict")
struct ExclusivityTests {
    @Test func `an argument may change a place an earlier one names, since a call's borrows begin with the call`() {
        // The second argument assigns `x` before the call borrows it for the first.
        let body = """
                var x = 1
                add(x, if x > 0 { x = 2; 1 } else { 3 })
            """
        #expect(errors(mainSource(body) + "\nfunc add(_ a: Int, _ b: Int) {}") == [])
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
