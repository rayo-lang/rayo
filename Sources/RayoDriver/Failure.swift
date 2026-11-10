/// A reason `rayoc` stops, which it reports as an error of its own.
struct Failure: Error {
    var message: String

    init(_ message: String) {
        self.message = message
    }
}
