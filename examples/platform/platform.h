/* A stand-in for a platform SDK's C header, such as a console's.
   Rayo imports it with `import c "platform.h"`; see bindings.rayo. */
#ifndef PLATFORM_H
#define PLATFORM_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#define PLATFORM_MAX_PADS 4

typedef struct platform_window platform_window;   /* opaque */

typedef enum platform_button : uint32_t {    /* C23: a fixed underlying type */
    PLATFORM_BUTTON_A     = 1 << 0,
    PLATFORM_BUTTON_B     = 1 << 1,
    PLATFORM_BUTTON_START = 1 << 2,
} __attribute__((flag_enum)) platform_button;

typedef struct platform_pad {
    float    left_stick[2];
    float    right_stick[2];
    uint32_t buttons;             /* platform_button bits */
    bool     connected;
} platform_pad;

typedef void (*platform_file_cb)(void* user, const uint8_t* data, size_t len, int32_t error);
typedef void (*platform_audio_cb)(void* user, int event);

double           platform_time_seconds(void);
void             platform_log(int32_t level, const char* msg, size_t len);
platform_window* platform_window_create(int32_t width, int32_t height, const char* title);
bool             platform_poll_pad(int32_t index, platform_pad* out);
int64_t          platform_read(uint8_t* dst, size_t len);       /* synchronous read from the open stream */
int32_t          platform_read_file_async(const char* path, platform_file_cb cb, void* user);
void             platform_set_audio_callback(platform_audio_cb cb, void* user);
void             platform_upload(const float* data, size_t count);
void             platform_gpu_free(uint32_t id);

/* A function-like macro: not imported by Rayo; see the extern c block in bindings.rayo. */
#define PLATFORM_PAD_DEADZONE(v) ((v) > -0.15f && (v) < 0.15f ? 0.0f : (v))

#endif
