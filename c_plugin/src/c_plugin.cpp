// c_plugin.cpp
#include "c_plugin.h"
#include <opencv2/core/version.hpp>  // for CV_VERSION

FFI_PLUGIN_EXPORT int sum(int a, int b) {
    return a + b;
}

FFI_PLUGIN_EXPORT int sum_long_running(int a, int b) {
#if _WIN32
    Sleep(5000);
#else
    sleep(5);
#endif
    return a + b;
}

