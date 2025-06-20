#include "c_plugin.h"
#include <opencv2/opencv.hpp>
#include <cmath>
#include <vector>
#include <limits>
#include <cstdint>
#include <algorithm>


using namespace cv;
extern "C" {

double color_hsv[3];
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
        double* out_values
        // length = 6: [Ycurr, Ymin, Ymax, hue, sat, ledOn]
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
//    double U = double(sumU)/countUV - 128.0;
//    double V = double(sumV)/countUV - 128.0;
//    double hue = std::atan2(V, U) * 180.0 / M_PI;
//    if (hue < 0) hue += 360.0;
//    double sat = std::sqrt(U*U + V*V) / 128.0;

    // 5) Dynamic threshold + hysteresis
    double mid   = (dynMin + dynMax) * 0.5;
    double margin= (dynMax - dynMin) * HYSTFRAC;
    if (!ledOn && Y > mid + margin) {
        ledOn = true;
    } else if (ledOn && Y < mid - margin) {
        ledOn = false;
    }

    detect_frame_color_precise(
            y_plane, u_plane, v_plane,
            width, height,
            y_row_stride, uv_row_stride, uv_pixel_stride,
            x0, y0, w, h,
            color_hsv
    );

    double hue = color_hsv[0];
    double sat = color_hsv[1];
    double val = color_hsv[2];

    double colorCode = (double)classify_hsv_color(hue,sat,val);

    // 6) Write outputs
    out_values[0] = Y;        // current brightness
    out_values[1] = dynMin;   // dynamic minimum
    out_values[2] = dynMax;   // dynamic maximum
    out_values[3] = hue;      // hue
    out_values[4] = sat;
    out_values[5] = colorCode; // saturation
    out_values[6] = ledOn ? 1.0 : 0.0;  // LED on/off flag
}

static void YUVPixel_to_HSV(
        uint8_t y_val,
        uint8_t u_val,
        uint8_t v_val,
        double &out_hue,
        double &out_sat,
        double &out_val
) {
    // First convert from YUV (with U/V biased at 128) to RGB [0..255].
    // Using “studio” conversion (BT.601). U',V' are signed centered at 0.
    double Y = static_cast<double>(y_val);
    double U = static_cast<double>(u_val) - 128.0;
    double V = static_cast<double>(v_val) - 128.0;

    // Standard formulas (BT.601 full-range→RGB):
    //   R = Y + 1.402  V
    //   G = Y - 0.344136  U - 0.714136  V
    //   B = Y + 1.772  U
    double Rf = Y + 1.402   * V;
    double Gf = Y - 0.344136 * U - 0.714136 * V;
    double Bf = Y + 1.772   * U;

    // Clamp to [0..255]:
    Rf = (Rf < 0.0) ? 0.0 : (Rf > 255.0 ? 255.0 : Rf);
    Gf = (Gf < 0.0) ? 0.0 : (Gf > 255.0 ? 255.0 : Gf);
    Bf = (Bf < 0.0) ? 0.0 : (Bf > 255.0 ? 255.0 : Bf);

    // Convert Rf, Gf, Bf to [0..1] range for HSV:
    double R = Rf * (1.0/255.0);
    double G = Gf * (1.0/255.0);
    double B = Bf * (1.0/255.0);

    // Compute Value and Saturation:
    double mx = std::max(R, std::max(G,B));
    double mn = std::min(R, std::min(G,B));
    double delta = mx - mn;

    out_val = mx;                       // V = max(R,G,B)
    out_sat = (mx < 1e-8) ? 0.0 : (delta / mx);

    // Compute Hue (in degrees [0..360)):
    if (delta < 1e-8) {
        out_hue = 0.0;                  // undefined, treat as 0
    } else {
        if (mx == R) {
            out_hue = 60.0 * (fmod(((G - B) / delta), 6.0));
        } else if (mx == G) {
            out_hue = 60.0 * (((B - R) / delta) + 2.0);
        } else { // mx == B
            out_hue = 60.0 * (((R - G) / delta) + 4.0);
        }
        if (out_hue < 0.0) {
            out_hue += 360.0;
        }
    }
}
void yuvpixel_to_hsv_c(
        uint8_t y_val,
        uint8_t u_val,
        uint8_t v_val,
        double* out_hue,
        double* out_sat,
        double* out_val
) {
    if (!out_hue || !out_sat || !out_val) return;
    double h, s, v;
    YUVPixel_to_HSV(y_val, u_val, v_val, h, s, v);
    *out_hue = h;
    *out_sat = s;
    *out_val = v;
}

// --------------------------------------------------------------------------------
// Precisely detect the dominant color in a YUV₂₁₀ ROI by building a hue histogram.
//
// Parameters:
//   y_plane, u_plane, v_plane    : pointers to the full image's Y, U, V planes.
//   width, height                : full image dimensions.
//   y_row_stride                 : number of bytes per row in Y plane.
//   uv_row_stride                : number of bytes per row in U/V planes.
//   uv_pixel_stride              : between-column stride in U/V (usually 1 or 2).
//   x0, y0, w, h                 : top-left corner (x0,y0) and size (w,h) of the ROI.
//   out_color_values             : length-3 array where we will write [hue, sat, val]:
//       out_color_values[0] = dominant hue (deg 0..360)
//       out_color_values[1] = average saturation of all pixels in that hue bin (0..1)
//       out_color_values[2] = average value   of all pixels in that hue bin (0..1)
//
// Usage: Allocate out_color_values[3] before calling. After call, you’ll have the
//        single “most frequent hue” plus its mean saturation/value in the ROI.
// --------------------------------------------------------------------------------
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
) {
    // Number of bins (one per degree). Feel free to reduce (e.g. 180 or 90 bins) if speed is critical.
    constexpr int HUE_BINS = 360;

    // Histogram for counting how many pixels fall into each hue bin.
    // We only count pixels whose saturation is above a small threshold (ignore near-gray).
    uint32_t hue_hist[HUE_BINS];
    std::fill_n(hue_hist, HUE_BINS, 0);

    // To compute average sat/value for the dominant hue bin, we need accumulators.
    // We'll keep a running sum of sat+val for each bin as well.
    double sat_accum[HUE_BINS];
    double val_accum[HUE_BINS];
    std::fill_n(sat_accum, HUE_BINS, 0.0);
    std::fill_n(val_accum, HUE_BINS, 0.0);

    // Threshold: ignore pixels with very low saturation (close to gray/no color).
    const double SAT_THRESHOLD = 0.05;

    // Iterate over every pixel in the ROI:
    for (int r = 0; r < h; ++r) {
        // Y pointer at (x0, y0 + r)
        const uint8_t* yp = y_plane + (y0 + r) * y_row_stride + x0;
        // U and V are subsampled by 2 in each dimension (YUV420).
        int uv_row = (y0 + r) >> 1;         // integer division by 2
        const uint8_t* up = u_plane + uv_row * uv_row_stride + (x0 >> 1) * uv_pixel_stride;
        const uint8_t* vp = v_plane + uv_row * uv_row_stride + (x0 >> 1) * uv_pixel_stride;

        int uv_col_stride = uv_pixel_stride; // often 1, but could be 2 in certain formats

        for (int c = 0; c < w; ++c) {
            uint8_t Yval = yp[c];
            // For U/V, use integer division by 2 on column index:
            int u_index = (x0 + c) >> 1;
            int v_index = u_index;
            uint8_t Uval = *(up + (u_index & ~((uv_pixel_stride>1? (uv_pixel_stride-1):0))));
            uint8_t Vval = *(vp + (v_index & ~((uv_pixel_stride>1? (uv_pixel_stride-1):0))));
            // Above bit-trick only matters if uv_pixel_stride>1; otherwise it's just up[u_index], vp[v_index].

            // Convert this single pixel to HSV:
            double hue, sat, val;
            yuvpixel_to_hsv_c(Yval, Uval, Vval, &hue, &sat, &val);

            // Skip very low-saturation pixels:
            if (sat < SAT_THRESHOLD) continue;

            // Bin the hue (0..360) into one of 360 integer bins:
            int bin = static_cast<int>(std::floor(hue)) % HUE_BINS;
            ++hue_hist[bin];
            sat_accum[bin] += sat;
            val_accum[bin] += val;
        }
    }

    // 1) Find which hue bin has the maximum count:
    uint32_t max_count = 0;
    int      best_bin  = 0;
    for (int b = 0; b < HUE_BINS; ++b) {
        if (hue_hist[b] > max_count) {
            max_count = hue_hist[b];
            best_bin  = b;
        }
    }

    // If we never saw any sufficiently saturated pixel, just return hue=0, sat=0, val=average grayscale:
    if (max_count == 0) {
        // Compute a fallback: average Y over ROI and map to V (value), hue/sat = 0.
        uint64_t sumY = 0;
        for (int rr = 0; rr < h; ++rr) {
            const uint8_t* yp_fallback = y_plane + (y0 + rr) * y_row_stride + x0;
            for (int cc = 0; cc < w; ++cc) {
                sumY += yp_fallback[cc];
            }
        }
        double avgY = static_cast<double>(sumY) / (w * h);
        out_color_values[0] = 0.0;            // hue = 0 by convention
        out_color_values[1] = 0.0;            // sat = 0 (gray)
        out_color_values[2] = avgY / 255.0;   // val = normalized brightness
        return;
    }

    // 2) Compute average saturation/value for the winning hue bin:
    double avg_sat = sat_accum[best_bin] / static_cast<double>(max_count);
    double avg_val = val_accum[best_bin] / static_cast<double>(max_count);

    // 3) Write out results: we pick the center of the bin as the “dominant hue angle”
    double dominant_hue = static_cast<double>(best_bin) + 0.5;
    if (dominant_hue >= 360.0) dominant_hue -= 360.0;

    out_color_values[0] = dominant_hue;
    out_color_values[1] = avg_sat;
    out_color_values[2] = avg_val;
}

int classify_hsv_color(double hue, double sat, double val) {
    // 1) If brightness (value) is very low, treat as "black"
    if (val < 0.05) {
        return 0; // black
    }
    // 2) If saturation is very low, treat as "gray" (since hue is unreliable)
    if (sat < 0.15) {
        if (val > 0.85)  return 1;  //white = 1
        else              return 2;  // gray = 2
    }

    // 3) Now hue is meaningful. Wrap into [0, 360).
    hue = fmod(hue, 360.0);
    if (hue < 0) hue += 360.0;

    // 4) Check known hue ranges:
    if ((hue >= 350.0 && hue <= 360.0) || (hue >=   0.0 && hue <=  10.0)) {
        return 3; // red = 3
    }
    if (hue >  10.0 && hue <=  40.0) {
        return 4; //orange = 4
    }
    if (hue >  40.0 && hue <=  70.0) {
        return 5; //yellow = 5
    }
    if (hue >  70.0 && hue <= 160.0) {
        return 6;  //green = 6
    }
    if (hue > 160.0 && hue <= 200.0) {
        return 7;  // cyan = 7
    }
    if (hue > 200.0 && hue <= 260.0) {
        return 8;   //blue = 8
    }
    if (hue > 260.0 && hue <= 330.0) {
        return 9;   // magenda = 9
    }
    if (hue > 330.0 && hue < 350.0) {
        return 10;  // pink = 10
    }
    // Fallback
    return 11;  //unknown = 11
}

}