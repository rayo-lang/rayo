import RayoCheckedProgram
import RayoIR
import Testing

/// Locals spread over several words of a set's bits, and over more than one node of the array that holds them.
private let spread = [1, 63, 64, 130, 5000].map { LocalID(index: $0) }

/// A set of 6000 locals that holds `locals`.
private func set(of locals: [LocalID]) -> LocalSet {
    var set = LocalSet(localCount: 6000)
    for local in locals {
        set.insert(local)
    }
    return set
}

struct LocalSetTests {
    @Test func `a set holds the locals inserted into it, until they are removed`() {
        var locals = set(of: spread)
        locals.remove(LocalID(index: 64))

        #expect((0..<6000).filter { locals.contains(LocalID(index: $0)) } == [1, 63, 130, 5000])
    }

    @Test func `sets are equal where they hold the same locals, however each came to hold them`() {
        var changedBack = set(of: spread)
        changedBack.insert(LocalID(index: 7))
        changedBack.remove(LocalID(index: 7))

        #expect(changedBack == set(of: spread))
        #expect(set(of: Array(spread.dropLast())) != set(of: spread))
    }

    @Test func `a union holds the locals of either set`() {
        let union = set(of: Array(spread.prefix(2))).union(set(of: Array(spread.suffix(4))))

        #expect(union == set(of: spread))
    }

    @Test func `the locals that one set holds and another leaves out come in the order of their IDs`() {
        let others = set(of: [LocalID(index: 63), LocalID(index: 2)])

        #expect(set(of: spread.reversed()).locals(notIn: others) == [1, 64, 130, 5000].map { LocalID(index: $0) })
        #expect(others.locals(notIn: set(of: spread)) == [LocalID(index: 2)])
        #expect(others.locals(notIn: others).isEmpty)
    }
}
