import RayoCheckedProgram
import RayoIR
import Testing

/// Sets of a function of few locals and of one of many, which keep their bits in different ways, each with locals
/// spread over several words of the set's bits.
private let functions = [
    (localCount: 200, spread: [1, 63, 64, 130, 199]),
    (localCount: 6000, spread: [1, 63, 64, 130, 5000]),
].map { ($0.localCount, $0.spread.map { LocalID(index: $0) }) }

/// A set of `localCount` locals that holds `locals`.
private func set(of locals: [LocalID], among localCount: Int) -> LocalSet {
    var set = LocalSet(localCount: localCount)
    for local in locals {
        set.insert(local)
    }
    return set
}

struct LocalSetTests {
    @Test(arguments: functions)
    func `a set holds the locals inserted into it, until they are removed`(localCount: Int, spread: [LocalID]) {
        var locals = set(of: spread, among: localCount)
        locals.remove(spread[2])

        let held = (0..<localCount).map { LocalID(index: $0) }.filter(locals.contains)
        #expect(held == [spread[0], spread[1], spread[3], spread[4]])
    }

    @Test(arguments: functions)
    func `sets are equal where they hold the same locals, however each came to hold them`(
        localCount: Int, spread: [LocalID],
    ) {
        var changedBack = set(of: spread, among: localCount)
        changedBack.insert(LocalID(index: 7))
        changedBack.remove(LocalID(index: 7))

        #expect(changedBack == set(of: spread, among: localCount))
        #expect(set(of: Array(spread.dropLast()), among: localCount) != set(of: spread, among: localCount))
    }

    @Test(arguments: functions)
    func `a union holds the locals of either set`(localCount: Int, spread: [LocalID]) {
        let first = set(of: Array(spread.prefix(2)), among: localCount)
        let union = first.union(set(of: Array(spread.suffix(4)), among: localCount))

        #expect(union == set(of: spread, among: localCount))
        #expect(first.union(first) == first)
    }

    @Test(arguments: functions)
    func `the locals that one set holds and another leaves out come in the order of their IDs`(
        localCount: Int, spread: [LocalID],
    ) {
        let others = set(of: [spread[1], LocalID(index: 2)], among: localCount)

        let held = set(of: spread.reversed(), among: localCount)
        #expect(held.locals(notIn: others) == [spread[0], spread[2], spread[3], spread[4]])
        #expect(others.locals(notIn: set(of: spread, among: localCount)) == [LocalID(index: 2)])
        #expect(others.locals(notIn: others).isEmpty)
    }
}
