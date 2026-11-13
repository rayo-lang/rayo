/// The way a dataflow analysis carries its state through a function.
enum DataflowDirection: Sendable {
    /// With the run: from a block's entry to its exit, and on into its successors.
    case forward
    /// Against the run: from a block's exit to its entry, and back into its predecessors.
    case backward
}
