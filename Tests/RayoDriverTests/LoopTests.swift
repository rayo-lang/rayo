import Testing

struct LoopTests {
    @Test("'while' repeats while its condition holds; 'continue' skips a pass and 'break' leaves the loop")
    func loops() {
        #expect(output("""
            var i = 0
            var sum = 0
            while true {
                i += 1
                if i % 2 == 0 { continue }
                if i > 9 { break }
                sum += i
            }
            print(sum)
            """) == "25\n")
    }
}
