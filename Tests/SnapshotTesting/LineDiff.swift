/// The lines that differ between two texts, with a few unchanged lines around each change, as a reader compares them.
public struct LineDiff: CustomStringConvertible {
    /// A line of the diff: kept by both texts, removed from the expected one, or added in the actual one.
    private enum Line {
        case kept(String)
        case removed(String)
        case added(String)
    }

    /// The unchanged lines shown on each side of a change.
    private static let context = 2

    private let lines: [Line]

    /// The diff from `expected` to `actual`.
    public init(from expected: String, to actual: String) {
        let old = expected.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let new = actual.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let difference = new.difference(from: old)

        // The lines each side drops or gains, by where they are in that side.
        var removals = Set<Int>()
        var insertions = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removals.insert(offset)
            case .insert(let offset, _, _): insertions.insert(offset)
            }
        }

        // Walk both sides together: a removed line comes before the lines added in its place.
        var lines: [Line] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            if oldIndex < old.count, removals.contains(oldIndex) {
                lines.append(.removed(old[oldIndex]))
                oldIndex += 1
            } else if newIndex < new.count, insertions.contains(newIndex) {
                lines.append(.added(new[newIndex]))
                newIndex += 1
            } else {
                lines.append(.kept(old[oldIndex]))
                oldIndex += 1
                newIndex += 1
            }
        }
        self.lines = lines
    }

    /// The changed lines, `-` before an expected one and `+` before an actual one, each run of them between the
    /// unchanged lines around it, and `...` where unchanged lines are left out.
    public var description: String {
        // Show each line within `context` lines of a change.
        let changed = lines.indices.filter { if case .kept = lines[$0] { false } else { true } }
        let shown = lines.indices.filter { index in
            changed.contains { abs($0 - index) <= Self.context }
        }

        // Mark a gap wherever shown lines skip unchanged ones.
        var output: [String] = []
        var previous: Int?
        for index in shown {
            if let previous, index > previous + 1 { output.append("...") }
            output.append(Self.text(of: lines[index]))
            previous = index
        }
        return output.joined(separator: "\n")
    }

    /// `line` as the diff shows it.
    private static func text(of line: Line) -> String {
        switch line {
        case .kept(let text): "  \(text)"
        case .removed(let text): "- \(text)"
        case .added(let text): "+ \(text)"
        }
    }
}
