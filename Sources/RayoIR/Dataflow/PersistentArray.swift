/// An array of a fixed count whose copies share the parts none of them changed, so copying, merging and comparing
/// copies cost only what differs between them.
package struct PersistentArray<Element: Equatable>: Equatable {
    /// Up to `nodeWidth` elements of the array, in order; a class, since copies share it.
    private final class Leaf {
        /// The first `count` slots hold elements of the array, and the rest repeat the first, since an inline array
        /// holds a value in every slot.
        var elements: NodeSlots<Element>
        let count: Int

        init(_ elements: Slots<Element>, count: Int) {
            self.elements = NodeSlots(values: elements)
            self.count = count
        }

        convenience init(_ elements: Span<Element>) {
            self.init(Slots { slot in elements[slot < elements.count ? slot : 0] }, count: elements.count)
        }

        init(copying leaf: Leaf) {
            elements = leaf.elements.copy()
            count = leaf.count
        }
    }

    /// Up to `nodeWidth` nodes of the level below, in order; a class, since copies share it.
    private final class Branch {
        /// The nodes below, and nil in each slot past `count`.
        var children: NodeSlots<Child?>
        let count: Int

        init(_ children: Slots<Child?>, count: Int) {
            self.children = NodeSlots(values: children)
            self.count = count
        }

        convenience init(_ children: ArraySlice<Child>) {
            let start = children.startIndex
            self.init(Slots { slot in slot < children.count ? children[start + slot] : nil }, count: children.count)
        }

        init(copying branch: Branch) {
            children = branch.children.copy()
            count = branch.count
        }
    }

    /// A node below a branch: a leaf in a branch just above the leaves, and a branch in any other.
    private enum Child {
        case leaf(Leaf)
        case branch(Branch)

        /// The node itself, which tells whether two arrays share it.
        var node: AnyObject {
            switch self {
            case .leaf(let leaf): leaf
            case .branch(let branch): branch
            }
        }
    }

    package let count: Int
    /// The elements in order, filling the leaves from the first. An array with no elements has a root with no leaves.
    private var root: Branch
    /// How far an index shifts right to give the root's child that holds it.
    private let rootShift: Int

    package init(_ elements: [Element]) {
        count = elements.count

        // Fill the leaves in order, then each level of branches above them, until one branch holds the rest.
        let span = elements.span
        var level: [Child] = []
        for start in stride(from: 0, to: count, by: nodeWidth) {
            level.append(.leaf(Leaf(span.extracting(start..<min(start + nodeWidth, count)))))
        }
        var shift = bitsPerLevel
        while level.count > nodeWidth {
            let below = level
            level = stride(from: 0, to: below.count, by: nodeWidth).map { start in
                .branch(Branch(below[start..<min(start + nodeWidth, below.count)]))
            }
            shift += bitsPerLevel
        }
        root = Branch(level[...])
        rootShift = shift
    }

    package subscript(index: Int) -> Element {
        get {
            precondition(0 <= index && index < count, "index out of range")
            var branch = root
            var shift = rootShift
            while true {
                switch branch.children.values[(index >> shift) & indexMask]! {
                case .leaf(let leaf):
                    return leaf.elements.values[index & indexMask]
                case .branch(let child):
                    branch = child
                    shift -= bitsPerLevel
                }
            }
        }
        set {
            // A write that changes nothing is skipped, since it would copy nodes that other copies share.
            guard self[index] != newValue else { return }
            Self.replace(at: index, with: newValue, in: &root, shift: rootShift)
        }
    }

    /// Combines the elements at each index. Shared parts are kept as they are, so `combine(x, x)` must be `x`.
    package func merged(with other: Self, combining combine: (Element, Element) -> Element) -> Self {
        precondition(count == other.count, "merged arrays have one count")
        var merged = self
        merged.root = Self.merged(root, other.root, shift: rootShift, combine)
        return merged
    }

    package static func == (first: Self, second: Self) -> Bool {
        first.count == second.count && equal(first.root, second.root)
    }

    /// Sets the element at `index` under `branch`, whose children hold an index shifted right by `shift`.
    private static func replace(at index: Int, with element: Element, in branch: inout Branch, shift: Int) {
        // A node another copy shares is copied first, so the change reaches this copy alone.
        if !isKnownUniquelyReferenced(&branch) { branch = Branch(copying: branch) }

        // Taking the child out of its slot drops the branch's reference to it, so a child no copy shares is unique.
        let slot = (index >> shift) & indexMask
        switch branch.children.values[slot].take()! {
        case .leaf(var leaf):
            if !isKnownUniquelyReferenced(&leaf) { leaf = Leaf(copying: leaf) }
            leaf.elements.values[index & indexMask] = element
            branch.children.values[slot] = .leaf(leaf)
        case .branch(var child):
            replace(at: index, with: element, in: &child, shift: shift - bitsPerLevel)
            branch.children.values[slot] = .branch(child)
        }
    }

    /// The branch holding the combined elements of `first` and `second`, branches at the same place in two arrays,
    /// whose children hold an index shifted right by `shift`.
    private static func merged(
        _ first: Branch, _ second: Branch, shift: Int, _ combine: (Element, Element) -> Element,
    ) -> Branch {
        if first === second { return first }
        let children = first.children.reading { firstChildren in
            second.children.reading { secondChildren in
                mergedSlots(firstChildren, secondChildren, count: first.count, isSame: { $0?.node === $1?.node }) {
                    merged($0!, $1!, shift: shift, combine)
                }
            }
        }
        return switch children {
        case .first: first
        case .second: second
        case .new(let children): Branch(children, count: first.count)
        }
    }

    /// The node holding the combined elements of `first` and `second`, children at the same place in two arrays of
    /// branches whose children hold an index shifted right by `shift`.
    private static func merged(
        _ first: Child, _ second: Child, shift: Int, _ combine: (Element, Element) -> Element,
    ) -> Child {
        switch (first, second) {
        case (.leaf(let first), .leaf(let second)):
            .leaf(merged(first, second, combine))
        case (.branch(let first), .branch(let second)):
            .branch(merged(first, second, shift: shift - bitsPerLevel, combine))
        default:
            preconditionFailure("arrays of one count have nodes of one shape")
        }
    }

    /// The leaf holding the combined elements of `first` and `second`, leaves at the same place in two arrays.
    private static func merged(_ first: Leaf, _ second: Leaf, _ combine: (Element, Element) -> Element) -> Leaf {
        if first === second { return first }
        let elements = first.elements.reading { firstElements in
            second.elements.reading { secondElements in
                mergedSlots(firstElements, secondElements, count: first.count, isSame: ==, combining: combine)
            }
        }
        return switch elements {
        case .first: first
        case .second: second
        case .new(let elements): Leaf(elements, count: first.count)
        }
    }

    /// Whether `first` and `second`, branches at the same place in two arrays of one count, hold equal elements.
    private static func equal(_ first: Branch, _ second: Branch) -> Bool {
        if first === second { return true }
        return first.children.reading { firstChildren in
            second.children.reading { secondChildren in
                slotsMatch(firstChildren, secondChildren, count: first.count) { equal($0!, $1!) }
            }
        }
    }

    /// Whether `first` and `second`, children at the same place in two arrays of one count, hold equal elements.
    private static func equal(_ first: Child, _ second: Child) -> Bool {
        switch (first, second) {
        case (.leaf(let first), .leaf(let second)):
            equal(first, second)
        case (.branch(let first), .branch(let second)):
            equal(first, second)
        default:
            preconditionFailure("arrays of one count have nodes of one shape")
        }
    }

    /// Whether `first` and `second`, leaves at the same place in two arrays, hold equal elements.
    private static func equal(_ first: Leaf, _ second: Leaf) -> Bool {
        if first === second { return true }
        return first.elements.reading { firstElements in
            second.elements.reading { secondElements in
                slotsMatch(firstElements, secondElements, count: first.count, by: ==)
            }
        }
    }
}

/// The slots of a node, held in the node itself, so each node takes one allocation.
private typealias Slots<Slot> = [32 of Slot]
private let nodeWidth = Slots<Int>.count
/// The bits of an index that each level of nodes takes.
private let bitsPerLevel = nodeWidth.trailingZeroBitCount
private let indexMask = nodeWidth - 1

/// A node's slots. Noncopyable, so `reading` borrows them without retaining any, where a read of a class's copyable
/// property copies the slots and retains each.
private struct NodeSlots<Slot>: ~Copyable {
    var values: Slots<Slot>

    func reading<Result>(_ read: (Span<Slot>) -> Result) -> Result {
        read(values.span)
    }

    /// The same slots, for a copy of the node that another array can change.
    func copy() -> Self {
        let slots = values.span
        return NodeSlots(values: Slots { slots[$0] })
    }
}

/// What merging the slots of two nodes gives: the slots of one of them as they are, or new slots unlike either's.
private enum MergedSlots<Slot> {
    case first
    case second
    case new(Slots<Slot>)
}

/// Combines the first `count` slots of two nodes, leaving slots that match each other as they are. The result is
/// one node's slots where it matches that node by `isSame`, and new slots from the first slot where it matches neither.
private func mergedSlots<Slot>(
    _ first: Span<Slot>, _ second: Span<Slot>, count: Int, isSame: (Slot, Slot) -> Bool,
    combining combine: (Slot, Slot) -> Slot,
) -> MergedSlots<Slot> {
    var matchesFirst = true
    var matchesSecond = true
    for slot in 0..<count where !isSame(first[slot], second[slot]) {
        let combined = combine(first[slot], second[slot])
        let stillMatchesFirst = matchesFirst && isSame(combined, first[slot])
        let stillMatchesSecond = matchesSecond && isSame(combined, second[slot])
        guard stillMatchesFirst || stillMatchesSecond else {
            // The slots before this one match the node still matched, so the new slots start as a copy of it.
            let matched = matchesFirst ? first : second
            var merged = Slots<Slot> { matched[$0] }
            var mergedSlots = merged.mutableSpan
            mergedSlots[slot] = combined
            for later in slot + 1..<count where !isSame(first[later], second[later]) {
                mergedSlots[later] = combine(first[later], second[later])
            }
            return .new(merged)
        }
        matchesFirst = stillMatchesFirst
        matchesSecond = stillMatchesSecond
    }
    return matchesFirst ? .first : .second
}

/// Whether the first `count` slots of two nodes match in turn by `match`.
private func slotsMatch<Slot>(
    _ first: Span<Slot>, _ second: Span<Slot>, count: Int, by match: (Slot, Slot) -> Bool,
) -> Bool {
    for slot in 0..<count where !match(first[slot], second[slot]) {
        return false
    }
    return true
}
