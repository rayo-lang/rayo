; What the runtime needs from a POSIX host, such as macOS or Linux: to ready a run, and to write to standard error.

; `write`'s size_t and ssize_t are 64 bits wide on the LP64 targets rayoc supports.
declare i64 @write(i32, ptr, i64)

; Readies the process to run the program, which a POSIX host needs nothing for.
define void @rayo.host.start() {
  ret void
}

; Writes the `length` bytes at `bytes` to standard error.
define void @rayo.host.write_error(ptr %bytes, i64 %length) {
  call i64 @write(i32 2, ptr %bytes, i64 %length)
  ret void
}
