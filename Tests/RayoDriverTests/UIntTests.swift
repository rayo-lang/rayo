import Testing
import RayoDriver

struct UIntTests {
    @Test func `'print' writes a UInt in decimal, UInt.max too`() {
        #expect(output("let u: UInt = 18446744073709551615\nprint(u)") == "18446744073709551615\n")
    }
}
