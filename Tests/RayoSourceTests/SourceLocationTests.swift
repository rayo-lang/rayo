import RayoSource
import Testing

struct SourceLocationTests {
    @Test func `two positions at the same line and column are the same, whatever offsets they hold`() {
        let lexed = SourceLocation(line: 3, column: 5, offset: 27)
        let named = SourceLocation(line: 3, column: 5, offset: 0)
        #expect(lexed == named)
        #expect(Set([lexed, named]).count == 1)
        #expect(lexed != SourceLocation(line: 3, column: 6, offset: 27))
    }

    @Test func `positions come in the order of their lines, then of their columns`() {
        let positions = [
            SourceLocation(line: 2, column: 1, offset: 0), SourceLocation(line: 1, column: 9, offset: 0),
            SourceLocation(line: 2, column: 4, offset: 0), SourceLocation(line: 1, column: 2, offset: 0),
        ]
        #expect(positions.sorted().map(\.description) == ["1:2", "1:9", "2:1", "2:4"])
    }
}
