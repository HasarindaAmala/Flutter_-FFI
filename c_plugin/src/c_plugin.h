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

//typedef struct {
//    int isOn;
//    int isGreen;
//} DetectionResult;
//
//DetectionResult* process_frame(unsigned char* yuv_data, int width, int height, int centerX, int centerY, int radius);

#ifdef __cplusplus
}
#endif
