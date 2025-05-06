# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(c_plugin_library VERSION 0.0.1 LANGUAGES C CXX)
# OpenCV
set(OpenCV_DIR "${CMAKE_SOURCE_DIR}/openCv/OpenCV/sdk/native/jni")
find_package(OpenCV REQUIRED)

add_library(c_plugin SHARED
  "c_plugin.cpp"
)

target_include_directories(c_plugin PRIVATE
        ${OpenCV_INCLUDE_DIRS}
)

target_link_libraries(c_plugin
        ${OpenCV_LIBS}
)

set_target_properties(c_plugin PROPERTIES
  PUBLIC_HEADER c_plugin.h
  OUTPUT_NAME "c_plugin"
)

target_compile_definitions(c_plugin PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(c_plugin PRIVATE "-Wl,-z,max-page-size=16384")
endif()
