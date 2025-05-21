#include "c_plugin.h"
#include <opencv2/opencv.hpp>
#include <cmath>
#include <vector>
#include <limits>
#include <cstdint>
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

    // 1) Decide ROI vs centre patch

    int32_t roiX = x0,    roiY = y0;
    int32_t roiW = w,     roiH = h;


    // 2) Build 256-bin histogram
    std::array<int,256> hist = {};
    int total = 0;
    for (int r = 0; r < roiH; ++r) {
        const uint8_t* rowPtr = y_plane + (roiY + r)*row_stride + roiX;
        for (int c = 0; c < roiW; ++c) {
            ++hist[rowPtr[c]];
            ++total;
        }
    }

    // 3) Compute mean
    double sumVal = 0.0;
    for (int v = 0; v < 256; ++v) {
        sumVal += double(v) * hist[v];
    }
    double mean = sumVal / total;

    // 4) Compute median
    int cum=0, mid = total/2;
    double median = 0;
    for (int v = 0; v < 256; ++v) {
        cum += hist[v];
        if (cum >= mid) { median = v; break; }
    }

    // 5) Compute trimmed‐mean (drop 10% low/high)
    int trim = total / 10;
    int lowCut=trim, highCut=total-trim;
    int running=0;
    double trimSum=0;
    for (int v=0; v<256; ++v) {
        int count = hist[v];
        if (running + count <= lowCut) {
            running += count;
            continue;
        }
        if (running >= highCut) break;
        // some or all of this bin
        int start = std::max(0, lowCut - running);
        int   end = std::min(count, highCut - running);
        int used = end - start;
        trimSum += double(v) * used;
        running += count;
    }
    double trimmed = trimSum / double(highCut - lowCut);

    // 6) Blend for a robust current value
    double currentValue = (mean + median + trimmed) / 3.0;

    // 7) Update running min/max
    if      (currentValue < minValue) minValue = currentValue;
    else if (currentValue > maxValue) maxValue = currentValue;

    // 8) Output
    out_values[0] = currentValue;
    out_values[1] = minValue;
    out_values[2] = maxValue;
}
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
        double* out_values   // length = 6: [Ycurr, Ymin, Ymax, hue, sat, ledOn]
) {
    // --- sliding window state for dynamic threshold ---
    constexpr int WINDOW = 30;
    static double history[WINDOW];
    static int    idx     = 0;
    static bool   full    = false;
    static bool   ledOn   = false;
    const double  HYSTFRAC = 0.1;  // hysteresis as fraction of span (10%)

    // 1) Compute average Y over the ROI
    uint64_t sumY = 0;
    for (int r = 0; r < h; ++r) {
        const uint8_t* yp = y_plane + (y0 + r) * y_row_stride + x0;
        for (int c = 0; c < w; ++c) {
            sumY += yp[c];
        }
    }
    double Y = double(sumY) / (w * h);

    // 2) Push into circular history buffer
    history[idx] = Y;
    idx = (idx + 1) % WINDOW;
    if (idx == 0) full = true;

    // 3) Compute dynamic min/max over valid samples
    int count = full ? WINDOW : idx;
    double dynMin = history[0], dynMax = history[0];
    for (int i = 1; i < count; ++i) {
        if (history[i] < dynMin) dynMin = history[i];
        if (history[i] > dynMax) dynMax = history[i];
    }

    // 4) Compute hue & saturation as before
    uint64_t sumU = 0, sumV = 0;
    int      countUV = 0;
    for (int r = 0; r < h; r += 2) {
        const uint8_t* up = u_plane + ((y0 + r)/2) * uv_row_stride + (x0/2)*uv_pixel_stride;
        const uint8_t* vp = v_plane + ((y0 + r)/2) * uv_row_stride + (x0/2)*uv_pixel_stride;
        int blocks = (w + 1) / 2;
        for (int b = 0; b < blocks; ++b) {
            sumU += *up;  sumV += *vp;
            up += uv_pixel_stride;
            vp += uv_pixel_stride;
            ++countUV;
        }
    }
    double U = double(sumU)/countUV - 128.0;
    double V = double(sumV)/countUV - 128.0;
    double hue = std::atan2(V, U) * 180.0 / M_PI;
    if (hue < 0) hue += 360.0;
    double sat = std::sqrt(U*U + V*V) / 128.0;

    // 5) Dynamic threshold + hysteresis
    double mid   = (dynMin + dynMax) * 0.5;
    double margin= (dynMax - dynMin) * HYSTFRAC;
    if (!ledOn && Y < mid - margin) {
        ledOn = true;
    } else if (ledOn && Y > mid + margin) {
        ledOn = false;
    }

    // 6) Write outputs
    out_values[0] = Y;        // current brightness
    out_values[1] = dynMin;   // dynamic minimum
    out_values[2] = dynMax;   // dynamic maximum
    out_values[3] = hue;      // hue
    out_values[4] = sat;      // saturation
    out_values[5] = ledOn ? 1.0 : 0.0;  // LED on/off flag
}
//DetectionR90esult result;
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