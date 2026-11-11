; What the runtime needs from Windows: to ready a run, and to write to standard error.

; The C runtime's headers define printf inline, so its library exports none; legacy_stdio_definitions.lib holds the
; printf a program that calls it links. The object asks for that library itself, as MSVC's own objects do.
!llvm.linker.options = !{!0}
!0 = !{!"/DEFAULTLIB:legacy_stdio_definitions.lib"}

declare i32 @_setmode(i32, i32)
; The C runtime's `_write` takes its count as an `unsigned int`, and returns an `int`.
declare i32 @_write(i32, ptr, i32)

; Readies the process to run the program: standard output and error go into binary mode, `_O_BINARY`, so that a
; newline is written as itself, not as "\r\n".
define void @rayo.host.start() {
  call i32 @_setmode(i32 1, i32 32768)
  call i32 @_setmode(i32 2, i32 32768)
  ret void
}

; Writes the `length` bytes at `bytes` to standard error. A message the runtime writes is far shorter than the
; 4 GiB a 32-bit count holds.
define void @rayo.host.write_error(ptr %bytes, i64 %length) {
  %count = trunc i64 %length to i32
  call i32 @_write(i32 2, ptr %bytes, i32 %count)
  ret void
}
