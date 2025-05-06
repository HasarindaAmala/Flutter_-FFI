cmake_minimum_required(VERSION 3.22.1)
# tell CMake where your include files are:
include_directories(
        ${CMAKE_SOURCE_DIR}/include            # if you have local includes
        ${CMAKE_SOURCE_DIR}/../../../../src     # <-- adds root/src
)

# find prebuilt OpenCV libs from jniLibs:
set(OpenCV_LIBS
        ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libopencv_java4.so
)
add_library(opencv_java4 SHARED IMPORTED)
set_target_properties(opencv_java4 PROPERTIES IMPORTED_LOCATION ${OpenCV_LIBS})

# your own native wrapper:
add_library(c_plugin SHARED
        openCvFunctions.cpp
)

# link against OpenCV:
target_link_libraries(c_plugin
        opencv_java4
        log        # Android log library
)
