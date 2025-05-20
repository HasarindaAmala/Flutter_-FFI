#include "c_plugin.h"
#include <opencv2/opencv.hpp>
#include <cmath>

using namespace cv;
extern "C" {

// Returns a pointer to a NUL-terminated const char* of the form "4.5.2"
const char* get_opencv_version() {
    return CV_VERSION;
}

//DetectionResult result;
//
//DetectionResult *
//process_frame(unsigned char *yuvData, int width, int height, int centerX, int centerY, int radius) {
//    // Convert YUV420 NV21 to BGR
//    Mat yuvImg(height + height / 2, width, CV_8UC1, yuvData);
//    Mat bgrImg;
//    cvtColor(yuvImg, bgrImg, COLOR_YUV2BGR_NV21);
//
//    // Calculate ROI (Clip it to stay within image bounds)
//    int x = std::max(0, centerX - radius);
//    int y = std::max(0, centerY - radius);
//    int roiWidth = std::min(radius * 2, width - x);
//    int roiHeight = std::min(radius * 2, height - y);
//
//    // Clip the ROI to ensure it stays within the image boundaries
//    if (x + roiWidth > width) {
//        roiWidth = width - x;
//    }
//    if (y + roiHeight > height) {
//        roiHeight = height - y;
//    }
//
//    Rect roi(x, y, roiWidth, roiHeight);
//
//    // Ensure that the ROI is valid
//    if (roi.width <= 0 || roi.height <= 0) {
//        // Invalid ROI, return early
//        result.isOn = 0;
//        result.isGreen = 0;
//        return &result;
//    }
//
//    // Extract the ROI from the image
//    Mat cropped = bgrImg(roi);
//
//    // Calculate mean brightness (grayscale intensity)
//    Mat gray;
//    cvtColor(cropped, gray, COLOR_BGR2GRAY);
//    Scalar meanGray = mean(gray);
//    result.isOn = meanGray[0] > 50 ? 1 : 0;  // Adjust threshold as needed
//
//    // Check if it's green
//    Scalar meanColor = mean(cropped);
//    if (meanColor[1] > 100 && meanColor[1] > meanColor[0] && meanColor[1] > meanColor[2]) {
//        result.isGreen = 1;
//    } else {
//        result.isGreen = 0;
//    }
//
//    return &result;
//}
}