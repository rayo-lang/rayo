/// The state of a dataflow analysis at a point of a function.
protocol DataflowState: Equatable {
    /// The state where a path on which `self` holds meets one on which `other` does. A merge only grows a state: what
    /// it returns holds all that each of the two holds, so merging either of them into it again changes nothing. A
    /// state can grow only so far, which is what brings the solver to a stop.
    func merged(with other: Self) -> Self
}
