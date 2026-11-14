@int_format = private unnamed_addr constant [6 x i8] c"%lld\0A\00"
@uint_format = private unnamed_addr constant [6 x i8] c"%llu\0A\00"
@text_format = private unnamed_addr constant [4 x i8] c"%s\0A\00"
@true_text = private unnamed_addr constant [5 x i8] c"true\00"
@false_text = private unnamed_addr constant [6 x i8] c"false\00"

declare i32 @printf(ptr, ...)

; Prints an Int on a line of its own.
define void @rayo.print_int(i64 %value) {
  call i32 (ptr, ...) @printf(ptr @int_format, i64 %value)
  ret void
}

; Prints a UInt, in decimal, on a line of its own.
define void @rayo.print_uint(i64 %value) {
  call i32 (ptr, ...) @printf(ptr @uint_format, i64 %value)
  ret void
}

; Prints a Bool, as `true` or `false`, on a line of its own.
define void @rayo.print_bool(i1 %value) {
  %text = select i1 %value, ptr @true_text, ptr @false_text
  call i32 (ptr, ...) @printf(ptr @text_format, ptr %text)
  ret void
}
