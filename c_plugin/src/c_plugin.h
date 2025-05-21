// c_plugin.h

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#if _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// A very short-lived native function.
FFI_PLUGIN_EXPORT int sum(int a, int b);

/// A longer-lived native function.
FFI_PLUGIN_EXPORT int sum_long_running(int a, int b);

/// Returns the OpenCV compile-time version string, e.g. "4.5.2"
FFI_PLUGIN_EXPORT const char* get_opencv_version();

void detect_bright_regions(
        const uint8_t* nv21_data,
        int width,
        int height,
        uint8_t threshold,
        int max_regions,
        int* bbox_out,
        int* count_out
);

/**
 * Detect ON/OFF state of LED inside ROI.
 * @returns 1 if LED is ON, 0 if OFF.
 */
uint8_t detect_led_on(
        const uint8_t* nv21_data,
        int width,
        int height,
        uint8_t threshold,
        int x,
        int y,
        int w,
        int h
);
void process_frame(
        const uint8_t* y_plane,
        int32_t width,
        int32_t height,
        int32_t row_stride,
        int32_t x0,
        int32_t y0,
        int32_t w,
        int32_t h,
        double* out_values
);

void process_frame_color(
        const uint8_t* y_plane,
        const uint8_t* u_plane,
        const uint8_t* v_plane,
        int32_t width,
        int32_t height,
        int32_t y_row_stride,
        int32_t uv_row_stride,
        int32_t uv_pixel_stride,
        int32_t x0,
        int32_t y0,
        int32_t w,
        int32_t h,
        double* out_values   // length = 5: [Ycurr, Ymin, Ymax, hue, sat]
);

//typedef struct {
//    int isOn;
//    int isGreen;
//} DetectionResult;
//
//DetectionResult* process_frame(unsigned char* yuv_data, int width, int height, int centerX, int centerY, int radius);

#ifdef __cplusplus
}
#endif
