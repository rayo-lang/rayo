; The C entry point, which readies the host, runs the program and exits with 0.

declare void @rayo.host.start()
declare void @rayo.main()

define i32 @main() {
  call void @rayo.host.start()
  call void @rayo.main()
  ret i32 0
}
