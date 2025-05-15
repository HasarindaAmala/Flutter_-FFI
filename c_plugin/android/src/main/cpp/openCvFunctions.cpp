#include <opencv2/core/version.hpp>
#include "c_plugin.h"

extern "C" {

// Returns a pointer to a NUL-terminated const char* of the form "4.5.2"
const char* get_opencv_version() {
    return CV_VERSION;
}


}
