@testable import RayoOwnership
import Testing

struct PersistentArrayTests {
    @Test func `an array holds the elements it is made of, and a change to a copy leaves the original as it was`() {
        let original = PersistentArray(Array(0..<1000))
        var copy = original
        copy[700] = -1

        #expect((0..<1000).map { original[$0] } == Array(0..<1000))
        #expect(copy[700] == -1)
        #expect(copy[699] == 699 && copy[701] == 701)
    }

    @Test func `arrays are equal where every element is, however each came to hold it`() {
        let original = PersistentArray(Array(0..<1000))
        var changed = original
        changed[3] = -1
        var changedBack = changed
        changedBack[3] = 3

        #expect(changed != original)
        #expect(changedBack == original)
        #expect(PersistentArray(Array(0..<1000)) == original)
        #expect(PersistentArray(Array(0..<999)) != original)
    }

    @Test func `a merge combines the elements at each index`() {
        let first = PersistentArray(Array(0..<100))
        let second = PersistentArray(Array(100..<200))

        let merged = first.merged(with: second, combining: +)
        #expect((0..<100).map { merged[$0] } == (0..<100).map { 2 * $0 + 100 })
    }

    @Test func `merging copies that differ in one element combines a few elements, not all of them`() {
        let original = PersistentArray(Array(repeating: 0, count: 10_000))
        var changed = original
        changed[5000] = 1

        var combined = 0
        let merged = original.merged(with: changed) { first, second in
            combined += 1
            return max(first, second)
        }
        #expect(merged[5000] == 1 && merged[4999] == 0)
        #expect(combined <= 64)
    }
}
