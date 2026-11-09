declare i32 @fflush(ptr)
declare i64 @write(i32, ptr, i64)
declare void @exit(i32) noreturn

; Reports a panic, given its message and the message's length, and exits with 101, the exit code of a program that
; panics. It writes what the program printed before it reports the panic, so the report comes last.
define void @rayo.panic(ptr %message, i64 %length) noreturn {
  call i32 @fflush(ptr null)
  call i64 @write(i32 2, ptr %message, i64 %length)
  call void @exit(i32 101)
  unreachable
}
