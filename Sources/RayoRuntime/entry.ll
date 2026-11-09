; The C entry point, which runs the program and exits with 0.

declare void @rayo.main()

define i32 @main() {
  call void @rayo.main()
  ret i32 0
}
