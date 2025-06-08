#ifndef C_PLUGIN_API_H
#define C_PLUGIN_API_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// very short-lived
int   sum(int a, int b);

/// longer-lived
int   sum_long_running(int a, int b);

/// compile-time OpenCV version
const char* get_opencv_version(void);

/// find up to max_regions bright blobs in an NV21 frame
void  detect_bright_regions(
        const uint8_t* nv21_data,
        int width,
        int height,
        uint8_t threshold,
        int max_regions,
        int* bbox_out,
        int* count_out
);

/// returns 1 if LED is on in ROI, else 0
uint8_t detect_led_on(
        const uint8_t* nv21_data,
        int width,
        int height,
        uint8_t threshold,
        int x, int y, int w, int h
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
        double* out_values   // length = 7: [Ycurr, Ymin, Ymax, hue, sat]
);

void yuvpixel_to_hsv_c(
        uint8_t y_val,
        uint8_t u_val,
        uint8_t v_val,
        double* out_hue,
        double* out_sat,
        double* out_val
);

void detect_frame_color_precise(
        const uint8_t* y_plane,
        const uint8_t* u_plane,
        const uint8_t* v_plane,
        int32_t        width,
        int32_t        height,
        int32_t        y_row_stride,
        int32_t        uv_row_stride,
        int32_t        uv_pixel_stride,
        int32_t        x0,
        int32_t        y0,
        int32_t        w,
        int32_t        h,
        double*        out_color_values  // length = 3: [hue, sat, val]
);

int classify_hsv_color(double hue, double sat, double val);

#ifdef __cplusplus
}
#endif
#endif // C_PLUGIN_API_H
