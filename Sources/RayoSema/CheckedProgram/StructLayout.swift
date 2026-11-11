/// How a struct's fields lie in its memory: each at a multiple of its alignment, with no padding but at the end.
public struct StructLayout: Hashable, Sendable {
    public var layout: Layout
    /// The fields, by their places in the declaration, in the order they lie in memory.
    public var layoutOrder: [Int]
    /// Each field's offset from the start of the struct, in bytes, indexed by its place in the declaration.
    public var fieldOffsets: [Int]
    /// The bytes after the last field, which pad the struct's size to a multiple of its alignment.
    public var endPadding: Int

    /// Lays out the fields of a struct, whose layouts `fields` gives in declaration order.
    init(fields: [Layout]) {
        // Order the fields by decreasing alignment, and those of one alignment as the declaration does.
        layoutOrder = fields.indices.sorted { first, second in
            (fields[second].alignment, first) < (fields[first].alignment, second)
        }

        // Place each field where the field before it ends.
        var offsets = Array(repeating: 0, count: fields.count)
        var end = 0
        for field in layoutOrder {
            // Each size before is a multiple of an alignment at least this field's, and alignments are powers of
            // two, so the end is already the first multiple of the field's alignment: no padding lies between fields.
            precondition(end % fields[field].alignment == 0, "a field lies at a multiple of its alignment")
            offsets[field] = end
            end += fields[field].size
        }
        fieldOffsets = offsets

        // Align the struct to its most-aligned field, and pad its end to that. An empty struct takes no memory, and
        // lies at any address.
        let alignment = fields.map(\.alignment).max() ?? 1
        layout = Layout(size: (end + alignment - 1) / alignment * alignment, alignment: alignment)
        endPadding = layout.size - end
    }
}
