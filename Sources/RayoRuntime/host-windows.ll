; What the runtime needs from Windows: to ready a run, and to write to standard error.

; The C runtime's headers define printf inline, so its library exports none. legacy_stdio_definitions.lib holds the
; printf that a program calling it links against, so the object names that library itself. It names kernel32.lib,
; which holds `SetThreadStackGuarantee`, too, so that a program links it whatever libraries its linker adds.
!llvm.linker.options = !{!0, !1}
!0 = !{!"/DEFAULTLIB:legacy_stdio_definitions.lib"}
!1 = !{!"/DEFAULTLIB:kernel32.lib"}

declare i32 @_setmode(i32, i32)
; The C runtime's `_write` takes its count as an `unsigned int`, and returns an `int`.
declare i32 @_write(i32, ptr, i32)

; Takes the size, in bytes, of the stack the calling thread keeps for handling a stack overflow, and returns, through
; the same `ULONG`, the size it kept before.
declare i32 @SetThreadStackGuarantee(ptr)

; Readies the process to run the program: standard output and error go into binary mode, `_O_BINARY`, so that a
; newline is written as itself, not as "\r\n", and the main thread keeps 64 KiB of its stack for a stack overflow.
define void @rayo.host.start() {
  call i32 @_setmode(i32 1, i32 32768)
  call i32 @_setmode(i32 2, i32 32768)

  ; Windows raises a stack overflow on the stack the thread has left, and first writes the thread's CPU state there,
  ; which grows with each set of extended registers the CPU has: past 11 KiB with AMX's tile registers. That is more
  ; than the stack a thread has left by default, and a write past it ends the process with an access violation
  ; instead. 64 KiB holds the largest such state several times over.
  %guarantee = alloca i32
  store i32 65536, ptr %guarantee
  call i32 @SetThreadStackGuarantee(ptr %guarantee)
  ret void
}

; Writes the `length` bytes at `bytes` to standard error. A message the runtime writes is far shorter than the
; 4 GiB a 32-bit count holds.
define void @rayo.host.write_error(ptr %bytes, i64 %length) {
  %count = trunc i64 %length to i32
  call i32 @_write(i32 2, ptr %bytes, i32 %count)
  ret void
}
