/// The effects of one block's statements and terminator, as a view into the effects of its body: one slice of them
/// for each statement in turn, then one for the terminator.
package struct BlockEffects: RandomAccessCollection {
    /// The block's effects, each statement's in turn and then the terminator's.
    package let all: ArraySlice<Effect>
    /// Where the effects of each of the block's statements and of its terminator begin in the body's effects, and then
    /// where the terminator's end. They index `all` too, since a slice keeps the indices of the array it is cut from.
    private let starts: ArraySlice<Int>

    /// The effects of a block, cut from `effects`: `starts` gives where each of its statements' and its terminator's
    /// begin, and then where the terminator's end.
    init(_ effects: [Effect], startingAt starts: ArraySlice<Int>) {
        all = effects[starts[starts.startIndex]..<starts[starts.endIndex - 1]]
        self.starts = starts
    }

    package var startIndex: Int { 0 }

    package var endIndex: Int { starts.count - 1 }

    /// The effects of the statement at `position`, or of the terminator at the position after the last statement.
    package subscript(position: Int) -> ArraySlice<Effect> {
        let start = starts.startIndex + position
        return all[starts[start]..<starts[start + 1]]
    }
}
