import RayoIR
import Testing

struct BitSetTests {
    @Test func `a set holds the bits put in it, in order, and none it took out or never held`() {
        var set = bits([199, 0, 130, 64, 63], count: 200)
        set.remove(64)

        #expect(Array(set) == [0, 63, 130, 199])
        #expect(set.contains(130) && !set.contains(64) && !set.contains(1))
    }

    @Test func `a union holds the bits of either set, and a difference those of the first alone`() {
        var union = bits([1, 64, 129], count: 130)
        union.formUnion(bits([2, 64], count: 130))
        var difference = bits([1, 64, 129], count: 130)
        difference.subtract(bits([2, 64], count: 130))

        #expect(Array(union) == [1, 2, 64, 129])
        #expect(Array(difference) == [1, 129])
    }

    @Test func `sets are equal where they hold the same bits, however each came to hold them`() {
        var changedBack = bits([5, 70], count: 100)
        changedBack.insert(80)
        changedBack.remove(80)

        #expect(changedBack == bits([70, 5], count: 100))
        #expect(changedBack != bits([5], count: 100))
    }

    @Test func `combining sets of ten thousand bits combines each of their 157 words once`() {
        var merged = BitSet(count: 10_000)
        var combined = 0
        merged.combine(with: bits([9_999], count: 10_000)) { first, second in
            combined += 1
            return first | second
        }

        #expect(Array(merged) == [9_999])
        #expect(combined == 157)
    }
}

struct GenKillTests {
    @Test func `a change clears the bits it kills, then sets the bits it generates`() {
        var change = GenKill(count: 8)
        change.set(1, to: false)
        change.set(2, to: true)
        var set = bits([0, 1], count: 8)
        change.apply(to: &set)

        #expect(Array(set) == [0, 2])
    }

    @Test func `of two changes to one bit, the later one holds`() {
        var change = GenKill(count: 8)
        change.set(3, to: true)
        change.set(3, to: false)
        change.set(4, to: false)
        change.set(4, to: true)
        var set = bits([3], count: 8)
        change.apply(to: &set)

        #expect(Array(set) == [4])
    }
}

/// A set of `count` bits that holds `held`.
private func bits(_ held: [Int], count: Int) -> BitSet {
    var set = BitSet(count: count)
    for bit in held {
        set.insert(bit)
    }
    return set
}
