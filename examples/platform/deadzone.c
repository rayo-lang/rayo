/* The game's own C: a function that wraps a function-like macro from platform.h, which
   Rayo doesn't import. The build compiles this file with a C compiler and links it;
   bindings.rayo declares the function with `extern(c) func`. */
#include "platform.h"

float pad_deadzone(float v) { return PLATFORM_PAD_DEADZONE(v); }
