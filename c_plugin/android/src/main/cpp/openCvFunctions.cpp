#include "c_plugin.h"
#include <opencv2/opencv.hpp>
#include <cmath>
#include <vector>
#include <algorithm>


using namespace cv;
extern "C" {

// Returns a pointer to a NUL-terminated const char* of the form "4.5.2"
const char* get_opencv_version() {
    return CV_VERSION;
}

void detect_bright_regions(
        const uint8_t* nv21_data,
        int width,
        int height,
        uint8_t threshold,
        int max_regions,
        int* bbox_out,
        int* count_out
) {
    // Wrap NV21 data
    cv::Mat yuv(height + height/2, width, CV_8UC1, const_cast<uint8_t*>(nv21_data));
    cv::Mat gray;
    cv::cvtColor(yuv, gray, cv::COLOR_YUV2GRAY_NV21);

    // Threshold
    cv::Mat bin;
    cv::threshold(gray, bin, threshold, 255, cv::THRESH_BINARY);
    // Clean
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, {3,3});
    cv::morphologyEx(bin, bin, cv::MORPH_OPEN, kernel);

    // Find contours
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(bin, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    // Sort by area desc
    std::sort(contours.begin(), contours.end(), [](auto &a, auto &b) {
        return cv::contourArea(a) > cv::contourArea(b);
    });

    int found = 0;
    for (auto &cnt : contours) {
        if (found >= max_regions) break;
        cv::Rect r = cv::boundingRect(cnt);
        if (r.area() < 20) continue;  // ignore tiny blobs
        int idx = found * 4;
        bbox_out[idx + 0] = r.x;
        bbox_out[idx + 1] = r.y;
        bbox_out[idx + 2] = r.width;
        bbox_out[idx + 3] = r.height;
        found++;
    }
    *count_out = found;
}

uint8_t detect_led_on(
        const uint8_t* nv21_data,
        int width,
        int height,
        uint8_t threshold,
        int x,
        int y,
        int w,
        int h
) {
    cv::Mat yuv(height + height/2, width, CV_8UC1, const_cast<uint8_t*>(nv21_data));
    cv::Mat gray;
    cv::cvtColor(yuv, gray, cv::COLOR_YUV2GRAY_NV21);

    // Crop ROI, clamp
    x = std::max(0, std::min(x, width-1));
    y = std::max(0, std::min(y, height-1));
    w = std::max(1, std::min(w, width - x));
    h = std::max(1, std::min(h, height - y));
    cv::Mat patch = gray(cv::Rect(x, y, w, h));

    // Threshold and count
    cv::Mat bin;
    cv::threshold(patch, bin, threshold, 255, cv::THRESH_BINARY);
    int bright = cv::countNonZero(bin);
    int total = patch.rows * patch.cols;
    // ON if >5% bright
    return (bright * 100 > total * 5) ? 1 : 0;
}
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
) {
    // Sum up Y values in the ROI
    static double minValue = std::numeric_limits<double>::infinity();
    static double maxValue = -std::numeric_limits<double>::infinity();

    // 1) Centre‐patch size: ¼ of ROI, clamped 8–64 px
    int32_t patchW = w / 4;
    if (patchW < 8)   patchW = 8;
    else if (patchW > 64) patchW = 64;

    int32_t patchH = h / 4;
    if (patchH < 8)   patchH = 8;
    else if (patchH > 64) patchH = 64;

    // 2) Top‐left of that patch, centred in the ROI
    int32_t cx = x0 + (w - patchW) / 2;
    int32_t cy = y0 + (h - patchH) / 2;

    // 3) Sum only the centre patch Y values
    uint64_t sum = 0;
    for (int row = 0; row < patchH; row++) {
        const uint8_t* ptr = y_plane + (cy + row) * row_stride + cx;
        for (int col = 0; col < patchW; col++) {
            sum += ptr[col];
        }
    }
    double currentValue = static_cast<double>(sum) / (patchW * patchH);

    // 4) Update running min/max
    if (currentValue < minValue) minValue = currentValue;
    if (currentValue > maxValue) maxValue = currentValue;

    // 5) Write out: [ current, min, max ]
    out_values[0] = currentValue;
    out_values[1] = minValue;
    out_values[2] = maxValue;
    // 4) Return average over that patch

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