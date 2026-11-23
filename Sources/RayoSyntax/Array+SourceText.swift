internal import RayoSource

extension [UInt8] {
    /// The source text that `range` covers, in this source held as UTF-8.
    func text(of range: SourceRange) -> String {
        String(decoding: self[range.start.offset..<range.end.offset], as: UTF8.self)
    }
}
