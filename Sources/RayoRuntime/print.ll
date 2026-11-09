@int_format = private unnamed_addr constant [6 x i8] c"%lld\0A\00"

declare i32 @printf(ptr, ...)

; Prints an Int on a line of its own.
define void @rayo.print_int(i64 %value) {
  call i32 (ptr, ...) @printf(ptr @int_format, i64 %value)
  ret void
}
