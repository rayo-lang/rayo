/// The error line for a change of `temporary` at `position`, which does nothing since the temporary is dropped at the
/// end of its statement.
func changedTemporary(_ temporary: String, at position: String) -> String {
    "\(position): error[E0291]: changing '\(temporary)' does nothing, since it's dropped right after; store it in a "
        + "'var' first"
}
