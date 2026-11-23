/// An array of a fixed count whose copies share the parts none of them changed, so copying, merging and comparing
/// copies cost only what differs between them.
struct PersistentArray<Element: Equatable>: Equatable {
    /// A leaf of up to `nodeWidth` elements, or a branch of up to `nodeWidth` nodes; a class, since copies share it.
    private final class Node {
        var elements: [Element]
        var children: [Node]

        init(elements: [Element]) {
            self.elements = elements
            children = []
        }

        init(children: [Node]) {
            elements = []
            self.children = children
        }

        init(copying node: Node) {
            elements = node.elements
            children = node.children
        }
    }

    let count: Int
    /// The elements in order, filling the leaves from the first.
    private var root: Node
    /// How far an index shifts right to give the root's child that holds it; zero where the root is a leaf.
    private let rootShift: Int

    init(_ elements: [Element]) {
        count = elements.count

        // Fill the leaves in order, then each level of branches above them, until one node holds the rest.
        var level = stride(from: 0, to: max(elements.count, 1), by: nodeWidth).map { start in
            Node(elements: Array(elements[start..<min(start + nodeWidth, elements.count)]))
        }
        var shift = 0
        while level.count > 1 {
            let below = level
            level = stride(from: 0, to: below.count, by: nodeWidth).map { start in
                Node(children: Array(below[start..<min(start + nodeWidth, below.count)]))
            }
            shift += bitsPerLevel
        }
        root = level[0]
        rootShift = shift
    }

    subscript(index: Int) -> Element {
        get {
            precondition(0 <= index && index < count, "index out of range")
            var node = root
            var shift = rootShift
            while shift > 0 {
                node = node.children[(index >> shift) & indexMask]
                shift -= bitsPerLevel
            }
            return node.elements[index & indexMask]
        }
        set {
            precondition(0 <= index && index < count, "index out of range")
            Self.replace(at: index, with: newValue, in: &root, shift: rootShift)
        }
    }

    /// Combines the elements at each index. Shared parts are kept as they are, so `combine(x, x)` must be `x`.
    func merged(with other: Self, combining combine: (Element, Element) -> Element) -> Self {
        precondition(count == other.count, "merged arrays have one count")
        var merged = self
        merged.root = Self.merged(root, other.root, shift: rootShift, combine)
        return merged
    }

    static func == (first: Self, second: Self) -> Bool {
        first.count == second.count && equal(first.root, second.root, shift: first.rootShift)
    }

    /// Sets the element at `index` under `node`, whose children hold an index shifted right by `shift`.
    private static func replace(at index: Int, with element: Element, in node: inout Node, shift: Int) {
        // A node another copy shares is copied first, so the change reaches this copy alone.
        if !isKnownUniquelyReferenced(&node) { node = Node(copying: node) }
        guard shift > 0 else {
            node.elements[index & indexMask] = element
            return
        }
        replace(at: index, with: element, in: &node.children[(index >> shift) & indexMask], shift: shift - bitsPerLevel)
    }

    /// The node holding the combined elements of `first` and `second`, nodes at the same place in two arrays.
    private static func merged(
        _ first: Node, _ second: Node, shift: Int, _ combine: (Element, Element) -> Element,
    ) -> Node {
        if first === second { return first }

        // A result equal to either node is that node, so later merges and comparisons can skip it.
        guard shift > 0 else {
            let elements = zip(first.elements, second.elements).map(combine)
            if elements == first.elements { return first }
            if elements == second.elements { return second }
            return Node(elements: elements)
        }
        let children = zip(first.children, second.children).map { merged($0, $1, shift: shift - bitsPerLevel, combine) }
        if children.elementsEqual(first.children, by: ===) { return first }
        if children.elementsEqual(second.children, by: ===) { return second }
        return Node(children: children)
    }

    /// Whether `first` and `second`, nodes at the same place in two arrays of one count, hold equal elements.
    private static func equal(_ first: Node, _ second: Node, shift: Int) -> Bool {
        if first === second { return true }
        guard shift > 0 else { return first.elements == second.elements }
        return zip(first.children, second.children).allSatisfy { equal($0, $1, shift: shift - bitsPerLevel) }
    }
}

/// The bits of an index that each level of nodes takes.
private let bitsPerLevel = 5
private let nodeWidth = 1 << bitsPerLevel
private let indexMask = nodeWidth - 1
