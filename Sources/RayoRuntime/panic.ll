; rayoc defines the exit code of a program that panics, which it also reports a panicking run with.
@rayo.panic_exit_code = external constant i32

declare i32 @fflush(ptr)
; `write`'s size_t and ssize_t are 64 bits wide on the LP64 targets rayoc supports.
declare i64 @write(i32, ptr, i64)
declare void @exit(i32) noreturn

; Reports a panic, given its message and the message's length, and exits with the panic exit code. It writes what
; the program printed before it reports the panic, so the report comes last.
define void @rayo.panic(ptr %message, i64 %length) noreturn {
  call i32 @fflush(ptr null)
  call i64 @write(i32 2, ptr %message, i64 %length)
  %exit_code = load i32, ptr @rayo.panic_exit_code
  call void @exit(i32 %exit_code)
  unreachable
}
