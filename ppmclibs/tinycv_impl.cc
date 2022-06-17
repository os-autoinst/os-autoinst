// Copyright 2012-2020 SUSE LLC
// SPDX-License-Identifier: GPL-2.0-or-later

#include <cerrno>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <exception>
#include <iostream>
#include <cstdint>
#include <cstdio>
#include <sys/time.h>
#include <byteswap.h>

#include <algorithm> // std::min
#include <vector>
#include <cmath> // std::isnan

#include "opencv2/calib3d/calib3d.hpp"
#include "opencv2/core/core.hpp"
#include "opencv2/highgui/highgui.hpp"
#include <opencv2/imgproc/imgproc.hpp>

#include "tinycv.h"

#define DEBUG 0
#define DEBUG2 0

#define VERY_DIFF 0.0
#define VERY_SIM 1000000.0

using namespace cv;

struct Image {
    Mat img;
    mutable Mat _preped;
    mutable Rect _prep_roi;

    Mat prep(const Rect& roi) const
    {
        if (!_preped.empty()) {
            // Check if ROI is contained in the current ROI
            if ((_prep_roi & roi) == roi)
                return _preped;
        }
        // Union of earlier requests and current
        _prep_roi |= roi;

        cvtColor(img, _preped, cv::COLOR_BGR2GRAY);

        if (img.total() * 0.5 <= _prep_roi.area())
            _prep_roi = Rect(Point(0, 0), img.size());

        // blur the image to avoid differences depending on where the object is
        Mat img_roi(_preped, _prep_roi);
        GaussianBlur(img_roi, img_roi, Size(3, 3), 0, 0);

        return _preped;
    }
};

/* the purpose of this function is to calculate the error between two images
  (scene area and object) ignoring slight colour changes */
double enhancedMSE(const Mat& _I1, const Mat& _I2)
{
    Mat I1 = _I1;
    I1.convertTo(I1, CV_8UC1);
    Mat I2 = _I2;
    I2.convertTo(I2, CV_8UC1);

    assert(I1.channels() == 1);
    assert(I2.channels() == 1);

    double sse = 0;

    for (int j = 0; j < I1.rows; j++) {
        // get the address of row j
        const uchar* I1_data = I1.ptr<const uchar>(j);
        const uchar* I2_data = I2.ptr<const uchar>(j);

        for (int i = 0; i < I1.cols; i++) {
            double diff = I1_data[i] - I2_data[i];
            sse += diff * diff;
        }
    }

    double total = I1.total();
    double mse = sse / total;

#if DEBUG2
    char f[200];
    sprintf(f, "debug-%lf-scene.png", mse);
    imwrite(f, I1);
    sprintf(f, "debug-%lf-object.png", mse);
    imwrite(f, I2);

    Mat s1;
    absdiff(I1, I2, s1);
    sprintf(f, "debug-%lf-diff.png", mse);
    imwrite(f, s1);
#endif

    return mse;
}

int MyErrorHandler(int status, const char* func_name, const char* err_msg,
    const char* file_name, int line, void*)
{
    // suppress error msg's
    return 0;
}

std::vector<char> str2vec(std::string str_in)
{
    std::vector<char> out(str_in.data(), str_in.data() + str_in.length());
    return out;
}

/* we try to the find the best locations - possibly more and will
   weight in later */
std::vector<Point> minVec(const Mat& m, float min)
{
    std::vector<Point> res;
    min += 10;

    assert(m.depth() == CV_32F);

    for (int y = 0; y < m.rows; y++) {
        const float* sptr = m.ptr<float>(y);

        for (int x = 0; x < m.cols; x++) {
            if (sptr[x] > min)
                continue;

            if (sptr[x] + 10 < min) {
                min = sptr[x] + 10;
                res.clear(); // reset
                res.push_back(Point(x, y));
            } else {
                res.push_back(Point(x, y));
            }
        }
    }
    return res;
}

// Used to sort a list of points to find the closest to the original
struct SortByClose {
    SortByClose(int _x, int _y) { orig.x = _x, orig.y = _y; }
    bool operator()(const Point& a, const Point& b) const
    {
        return norm(orig - a) < norm(orig - b);
    }
    Point orig;
};

/* we find the object in the scene and return the x,y and the error of the match
 */
std::vector<int> search_TEMPLATE(const Image* scene, const Image* object,
    long x, long y, long width, long height,
    long margin, double& similarity)
{
// cvSetErrMode(CV_ErrModeParent);
// cvRedirectError(MyErrorHandler);

#if DEBUG
    struct timeval tv1, tv2;
    gettimeofday(&tv1, 0);
#endif

    std::vector<int> outvec(2);
    outvec[0] = 0;
    outvec[1] = 0;
    similarity = 0;

    if (scene->img.empty() || object->img.empty()) {
        std::cerr << "Error reading images. Scene or object is empty." << std::endl;
        throw(std::exception());
    }

    // avoid an exception
    if (x < 0 || y < 0 || y + height > scene->img.rows || x + width > scene->img.cols) {
        std::cerr << "ERROR - search: out of range " << y + height << " "
                  << scene->img.rows << " " << x + width << " " << scene->img.cols
                  << std::endl;
        return outvec;
    }

    // Optimization -- Search close to the original area working with ROI
    int scene_x = std::max(0, int(x - margin));
    int scene_y = std::max(0, int(y - margin));
    int scene_bottom_x = std::min(scene->img.cols, int(x + width + margin));
    int scene_bottom_y = std::min(scene->img.rows, int(y + height + margin));
    int scene_width = scene_bottom_x - scene_x;
    int scene_height = scene_bottom_y - scene_y;

    Mat scene_copy = scene->prep(Rect(scene_x, scene_y, scene_width, scene_height));
    Mat object_copy = object->prep(Rect(x, y, width, height));

    Mat scene_roi(scene_copy, Rect(scene_x, scene_y, scene_width, scene_height));
    Mat object_roi(object_copy, Rect(x, y, width, height));

    // Calculate size of result matrix and create it. If scene is W x H
    // and object is w x h, res is (W - w + 1) x ( H - h + 1)
    int result_width = scene_roi.cols - width + 1; // object->img.cols + 1;
    int result_height = scene_roi.rows - height + 1; // object->img.rows + 1;
    if (result_width <= 0 || result_height <= 0) {
        std::cerr << "ERROR2 - search: out of range\n"
                  << std::endl;
        return outvec;
    }

    Mat result = Mat::zeros(result_height, result_width, CV_32FC1);

    // Perform the matching. Info about algorithm:
    // http://docs.opencv.org/trunk/doc/tutorials/imgproc/histograms/template_matching/template_matching.html
    // http://docs.opencv.org/modules/imgproc/doc/object_detection.html
    // Used metric is (sum of) squared differences
    matchTemplate(scene_roi, object_roi, result, cv::TM_SQDIFF);

    // Use error at original location as upper bound
    Point center = Point(x - scene_x, y - scene_y);
    double sse = result.at<float>(center);
    if (sse == 0) {
        similarity = 1;
        return { (int)(x), (int)(y) };
    }

    // Localizing the points that are "good" - not necessarly the absolute min
    std::vector<Point> mins = minVec(result, sse);

    if (mins.empty())
        return outvec;
    // sort it by distance to the original - and take the closest
    SortByClose s(x, y);
    sort(mins.begin(), mins.end(), s);
    Point minloc = mins[0];
    outvec[0] = int(minloc.x + scene_x);
    outvec[1] = int(minloc.y + scene_y);

    double mse = 10000;

    // detect the MSE at the given location
    Mat scene_best(scene_copy, Rect(outvec[0], outvec[1], width, height));

    mse = enhancedMSE(scene_best, object_roi);

    /* our callers expect a "how well does it match between 0-1", where 0.96 is
   defined as
   good enough. So we need to map this a bit to avoid breaking all the rest */
    // mse = 2 => 1
    // mse = 40 => .9
    similarity = .9 + (40 - mse) / 380;
    if (similarity < 0)
        similarity = 0;
    if (similarity > 1)
        similarity = 1;

#if DEBUG
    gettimeofday(&tv2, 0);
    long tdiff = (tv2.tv_sec - tv1.tv_sec) * 1000 + (tv2.tv_usec - tv1.tv_usec) / 1000;
    std::cerr << "search_template " << tdiff << " ms "
              << " MSE " << mse << " sim:" << similarity << std::endl;
#endif
    return outvec;
}

// Use Peak signal-to-noise ratio to check the similarity between two
// images.
//
// This method calculate the mean square error, but returns a measure
// in dB units. If the images are the same, it return 0.0, and if the
// images are the same but with different compression ration (or noise
// when the input is from analog video), the range is between 30 and
// 50. Maybe higher is the quality is bad.
//
// Source (C&P):
// http://docs.opencv.org/doc/tutorials/highgui/video-input-psnr-ssim/video-input-psnr-ssim.html
// (optimized for our needs)

double getPSNR(const Mat& I1, const Mat& I2)
{
    assert(I2.depth() == CV_8U);
    assert(I2.channels() == 3);

    assert(I1.depth() == CV_8U);
    assert(I1.channels() == 3);

    double noise = norm(I1, I2);

    if (std::isnan(noise)) {
        std::cerr << "WARNING: cv::norm() returned NaN (poo#68474)\n";
        return VERY_DIFF;
    }

    if (!noise) {
        return VERY_SIM;
    }

    double signal = 255.0 * 255 * 3 * I1.total();

    return 10.0 * log10(signal / (noise * noise));
}

using OpenCVParallelFunction = std::function<void(const Range &)>;
#if defined(CV_VERSION_MAJOR) && (CV_VERSION_MAJOR >= 4)
using RunFunctionInParallel = OpenCVParallelFunction;
#else
class RunFunctionInParallel : public ParallelLoopBody {
public:
    explicit RunFunctionInParallel(OpenCVParallelFunction &&functor) : functor(std::move(functor)) {}
    void operator() (const Range &range) const override { functor(range); }
private:
    OpenCVParallelFunction functor;
};
#endif

/*!
 * \brief Returns the default thread count for create_opencv_threads().
 *
 * That is the number of threads we can safely spawn without running into limitations.
 *
 * \remarks
 * - This should be generally at least one thread and we generally just use OpenCV's default.
 * - To avoid running into TBB's soft limit which seems to be one thread less than the number
 *   of physical CPU threads (see TBB function `calc_workers_soft_limit`) we also limit ourselves
 *   to that. Otherwise we might run into a deadlock with "The number of workers is currently
 *   limited to 7. The request for 8 workers is ignored.".
 */
int opencv_default_thread_count()
{
    return std::max(1, std::min(cv::getNumThreads(), cv::getNumberOfCPUs() - 1));
}

/*!
 * \brief Creates OpenCV's threads upfront.
 *
 * This allows one to take control over spawning these threads, e.g. to block signals. One can
 * also specify the number of threads to be created (instead of using OpenCV's default).
 *
 * \remarks
 * - This function invokes parallel_for_ because there seems no designated function for explicitly
 *   spawning the threads upfront. This could be done on the level of the underlying parallelisation
 *   framework (e.g. OpenMP or TBB) but that would mean multiple code paths depending on OpenCV's
 *   configuration.
 * - We can not simply invoke `parallel_for_(Range(0, arbitrary_high_number), [&] (const Range &) {}`
 *   because that would not guarantee that actually up to \a thread_count threads are kept busy at the
 *   same time and indeed does not work in practice for high \a thread_count values like 32. Hence we
 *   keep the threads idling until the expected number of threads has been spawned.
 */
void create_opencv_threads(int thread_count)
{
    // ensure \a thread_count is initialized and set it explicitly in any case so the number of
    // expected threads is fix
    if (thread_count < 0) {
        thread_count = opencv_default_thread_count();
    }
    cv::setNumThreads(thread_count);

    // execute a parallel algorithm which ensures that \a thread_count are busy at the same time
    std::mutex m;
    std::condition_variable cv;
    int threads_spawned = 0;
    parallel_for_(Range(0, thread_count), RunFunctionInParallel([&] (const Range &) {
        // keep the thread idling until the expected number of threads has been spawned
        std::unique_lock<std::mutex> lock(m);
        if (++threads_spawned >= thread_count) {
            cv.notify_all(); // note: The last thread releases all previously spawned threads.
        } else {
            cv.wait(lock);
        }
    }));
}

void image_destroy(Image* s) { delete (s); }

Image* image_new(long width, long height)
{
    Image* image = new Image;
    image->img = Mat::zeros(height, width, CV_8UC3);
    return image;
}

Image* image_read(const char* filename)
{
    Image* image = new Image;
    image->img = imread(filename, cv::IMREAD_COLOR);
    if (!image->img.data) {
        std::cerr << "Could not open image " << filename << std::endl;
        delete image;
        return nullptr;
    }
    return image;
}

Image* image_from_ppm(const unsigned char* data, size_t len)
{
    std::vector<uchar> buf(data, data + len);
    Image* image = new Image;
    image->img = imdecode(buf, cv::IMREAD_COLOR);
    return image;
}

bool image_write(const Image* const s, const char* filename)
{
    if (s->img.empty()) {
        std::cerr << "Could not write image " << filename << ": image is empty\n";
        return false;
    }
    return imwrite(filename, s->img);
}

std::vector<uchar>* image_ppm(Image* s)
{
    // reuse memory
    static std::vector<uchar> buf;
    imencode(".ppm", s->img, buf);
    return &buf;
}

Image* image_copy(Image* s)
{
    Image* ni = new Image();
    s->img.copyTo(ni->img);
    return ni;
}

long image_xres(Image* s) { return s->img.cols; }

long image_yres(Image* s) { return s->img.rows; }

/*
 * in the image s replace all pixels in the given range with 0 - in place
 */
void image_replacerect(Image* s, long x, long y, long width, long height)
{
    // avoid an exception
    if (x < 0 || y < 0 || y + height > s->img.rows || x + width > s->img.cols) {
        std::cerr << "ERROR - replacerect: out of range\n"
                  << std::endl;
        return;
    }

    rectangle(s->img, Rect(x, y, width, height), CV_RGB(0, 255, 0), cv::FILLED);
}

/* copies the given range into a new image */
Image* image_copyrect(Image* s, long x, long y, long width, long height)
{
    // avoid an exception
    if (x < 0 || y < 0 || y + height > s->img.rows || x + width > s->img.cols) {
        std::cerr << "ERROR - copyrect: out of range\n"
                  << std::endl;
        return 0;
    }

    Image* n = new Image;
    Mat tmp = Mat(s->img, Range(y, y + height), Range(x, x + width));
    n->img = tmp.clone();
    return n;
}

// in-place op: change all values to 0 (if below threshold) or 255 otherwise
void image_threshold(Image* a, int level)
{
    for (int y = 0; y < a->img.rows; y++) {
        for (int x = 0; x < a->img.cols; x++) {
            Vec3b farbe = a->img.at<Vec3b>(y, x);
            if ((farbe[0] + farbe[1] + farbe[2]) / 3 > level)
                farbe = Vec3b(255, 255, 255);
            else
                farbe = Vec3b(0, 0, 0);
            a->img.at<Vec3b>(y, x) = farbe;
        }
    }
}

std::tuple<long, long, long> image_get_pixel(Image* a, long x, long y)
{
    const auto pixel = a->img.at<Vec3b>(y, x);
    return std::make_tuple(pixel[0], pixel[1], pixel[2]);
}

std::vector<float> image_avgcolor(Image* s)
{
    Scalar t = mean(s->img);

    std::vector<float> f;
    f.push_back(t[2] / 255.0); // Red
    f.push_back(t[1] / 255.0); // Green
    f.push_back(t[0] / 255.0); // Blue

    return f;
}

std::vector<int> image_search(Image* s, Image* needle, long x, long y,
    long width, long height, long margin,
    double& similarity)
{
    return search_TEMPLATE(s, needle, x, y, width, height, margin, similarity);
}

Image* image_scale(Image* a, int width, int height)
{
    Image* n = new Image;

    /* first scale down in case */
    if (a->img.rows > height || a->img.cols > width) {
        n->img = Mat(height, width, a->img.type());
        resize(a->img, n->img, n->img.size());
    } else if (n->img.rows < height || n->img.cols < width) {
        n->img = Mat::zeros(height, width, a->img.type());
        n->img = Scalar(120, 120, 120);
        a->img.copyTo(n->img(Rect(0, 0, a->img.cols, a->img.rows)));
    } else
        n->img = a->img;

    return n;
}

double image_similarity(Image* a, Image* b)
{
    if (a->img.rows != b->img.rows)
        return VERY_DIFF;

    if (a->img.cols != b->img.cols)
        return VERY_DIFF;

    return getPSNR(a->img, b->img);
}

Image* image_absdiff(Image* a, Image* b)
{
    Image* n = new Image;

    Mat t;
    absdiff(a->img, b->img, t);
    n->img = t;

    return n;
}

class VNCInfo {
    bool do_endian_conversion;
    bool true_colour;
    unsigned int bytes_per_pixel;
    unsigned int red_mask;
    unsigned int red_shift;
    unsigned int green_mask;
    unsigned int green_shift;
    unsigned int blue_mask;
    unsigned int blue_shift;

    // calculated
    unsigned char blue_skale;
    unsigned char green_skale;
    unsigned char red_skale;

    // in case !true_color
    Vec3b colourMap[256];

public:
    VNCInfo(bool do_endian_conversion, bool true_colour,
        unsigned int bytes_per_pixel, unsigned int red_mask,
        unsigned int red_shift, unsigned int green_mask,
        unsigned int green_shift, unsigned int blue_mask,
        unsigned int blue_shift)
    {
        this->do_endian_conversion = do_endian_conversion;
        this->true_colour = true_colour;
        this->bytes_per_pixel = bytes_per_pixel;
        this->red_mask = red_mask;
        this->red_shift = red_shift;
        this->green_mask = green_mask;
        this->green_shift = green_shift;
        this->blue_mask = blue_mask;
        this->blue_shift = blue_shift;
        this->blue_skale = 256 / (blue_mask + 1);
        this->green_skale = 256 / (green_mask + 1);
        this->red_skale = 256 / (red_mask + 1);
    }

    Vec3b read_cpixel(const unsigned char* data, size_t& offset);
    Vec3b read_pixel(const unsigned char* data, size_t& offset);
    const Vec3b &get_colour(unsigned int index) const {
        assert(index < 256);
        return colourMap[index];
    }
    void set_colour(unsigned int index, unsigned int red, unsigned int green,
        unsigned int blue)
    {
        assert(index < 256);
        colourMap[index] = Vec3b(blue, green, red);
    }
};

std::tuple<long, long, long> image_get_vnc_color(VNCInfo* info, unsigned int index)
{
    const auto &color = info->get_colour(index);
    return std::make_tuple(color[0], color[1], color[2]);
}

void image_set_vnc_color(VNCInfo* info, unsigned int index, unsigned int red,
    unsigned int green, unsigned int blue)
{
    info->set_colour(index, red, green, blue);
}

VNCInfo* image_vncinfo(bool do_endian_conversion, bool true_colour,
    unsigned int bytes_per_pixel, unsigned int red_mask,
    unsigned int red_shift, unsigned int green_mask,
    unsigned int green_shift, unsigned int blue_mask,
    unsigned int blue_shift)
{
    return new VNCInfo(do_endian_conversion, true_colour, bytes_per_pixel,
        red_mask, red_shift, green_mask, green_shift, blue_mask,
        blue_shift);
}

// implemented in tinycv_ast2100
void decode_ast2100(Mat* img, const unsigned char* data, size_t len);

void image_map_raw_data_ast2100(Image* a, const unsigned char* data,
    size_t len)
{
    decode_ast2100(&a->img, data, len);
}

void image_map_raw_data_rgb555(Image* a, const unsigned char* data)
{
    for (int y = 0; y < a->img.rows; y++) {
        for (int x = 0; x < a->img.cols; x++) {
            long pixel = *data++;
            pixel += *data++ * 256;
            unsigned char blue = pixel % 32 * 8;
            pixel = pixel >> 5;
            unsigned char green = pixel % 32 * 8;
            pixel = pixel >> 5;
            unsigned char red = pixel % 32 * 8;
            // MSB ignored
            a->img.at<Vec3b>(y, x)[0] = blue;
            a->img.at<Vec3b>(y, x)[1] = green;
            a->img.at<Vec3b>(y, x)[2] = red;
        }
    }
}

static uint16_t read_u16(const unsigned char* data, size_t& offset,
    bool do_endian_conversion)
{
    uint16_t pixel = *(uint16_t*)(data + offset);
    offset += 2;
    if (do_endian_conversion) {
        pixel = bswap_16(pixel);
    }
    return pixel;
}

Vec3b VNCInfo::read_pixel(const unsigned char* data, size_t& offset)
{
    unsigned char blue_skale = 256 / (blue_mask + 1);
    unsigned char green_skale = 256 / (green_mask + 1);
    unsigned char red_skale = 256 / (red_mask + 1);

    long pixel;
    if (bytes_per_pixel == 2) {
        pixel = read_u16(data, offset, do_endian_conversion);
    } else if (bytes_per_pixel == 4) {
        pixel = *(uint32_t*)(data + offset);
        offset += 4;
        if (do_endian_conversion) {
            pixel = bswap_32(pixel);
        }
    } else if (bytes_per_pixel == 1) {
        pixel = data[offset++];
        if (!true_colour)
            return colourMap[pixel];
    } else {
        // just fail miserably for unsupported bytes per pixel
        abort();
    };

    unsigned char blue = (pixel >> blue_shift & blue_mask) * blue_skale;
    unsigned char green = (pixel >> green_shift & green_mask) * green_skale;
    unsigned char red = (pixel >> red_shift & red_mask) * red_skale;
    return Vec3b(blue, green, red);
}

void image_map_raw_data(Image* a, const unsigned char* data, unsigned int ox,
    unsigned int oy, unsigned int width,
    unsigned int height, VNCInfo* info)
{
    size_t offset = 0;
    for (unsigned int y = 0; y < height; y++) {
        for (unsigned int x = 0; x < width; x++) {
            Vec3b pixel = info->read_pixel(data, offset);
            a->img.at<Vec3b>(y + oy, x + ox) = pixel;
        }
    }
}

// copy the s image into a at x,y
void image_blend_image(Image* a, Image* s, long x, long y)
{
    Rect roi(Point(x, y), s->img.size());
    if (s->img.rows == 0 || s->img.cols == 0)
        return;
    s->img.copyTo(a->img(roi));
}

Vec3b VNCInfo::read_cpixel(const unsigned char* data, size_t& offset)
{
    unsigned char red, green, blue;

    if (bytes_per_pixel == 1) {
        return colourMap[data[offset++]];
    } else if (bytes_per_pixel == 2) {
        long pixel = read_u16(data, offset, do_endian_conversion);
        red = (pixel >> red_shift & red_mask) * red_skale;
        green = (pixel >> green_shift & green_mask) * green_skale;
        blue = (pixel >> blue_shift & blue_mask) * blue_skale;
    } else {
        if (do_endian_conversion) {
            red = data[offset++];
            green = data[offset++];
            blue = data[offset++];
        } else {
            blue = data[offset++];
            green = data[offset++];
            red = data[offset++];
        }
    }
    return Vec3b(blue, green, red);
}

long image_map_raw_data_zrle(Image* a, long x, long y, long w, long h,
    VNCInfo* info, unsigned char* data, size_t bytes)
{
    /* ZRLE implementation is described pretty straight forward in the RFB 3.8
   * protocol */

    size_t offset = 0;
    int orig_w = w;
    int orig_x = x;
    while (h > 0) {
        w = orig_w;
        x = orig_x;
        while (w > 0) {
            if (offset >= bytes) {
                fprintf(stderr, "not enough bytes for zrle\n");
                abort();
            }
            unsigned char sub_encoding = data[offset++];
            int tile_width = w > 64 ? 64 : w;
            int tile_height = h > 64 ? 64 : h;

            if (sub_encoding == 1) {
                Vec3b farbe = info->read_cpixel(data, offset);
                for (int j = 0; j < tile_height; j++) {
                    for (int i = 0; i < tile_width; i++) {
                        a->img.at<Vec3b>(y + j, x + i) = farbe;
                    }
                }
            } else if (sub_encoding == 0) {
                for (int j = 0; j < tile_height; j++) {
                    for (int i = 0; i < tile_width; i++) {
                        Vec3b farbe = info->read_cpixel(data, offset);
                        a->img.at<Vec3b>(y + j, x + i) = farbe;
                    }
                }
            } else if (sub_encoding == 128) {
                int j = 0, i = 0;
                while (j < tile_height) {
                    Vec3b farbe = info->read_cpixel(data, offset);
                    int length = 1;
                    /* run length */
                    while (data[offset] == 0xff) {
                        length += data[offset++];
                    }
                    length += data[offset++];
                    while (j < tile_height && length > 0) {
                        a->img.at<Vec3b>(y + j, x + i) = farbe;
                        length--;
                        if (++i >= tile_width) {
                            i = 0;
                            j++;
                        }
                    }
                }
            } else {
                int palette_size = sub_encoding;
                int palette_bpp = 8;
                if (sub_encoding >= 130) {
                    palette_size = sub_encoding - 128;
                } else {
                    palette_bpp = (sub_encoding > 4 ? 4 : (sub_encoding > 2 ? 2 : 1));
                }

                Vec3b palette[128]; // max size
                for (int i = 0; i < palette_size; ++i) {
                    palette[i] = info->read_cpixel(data, offset);
                }
                if (palette_bpp == 8) { // unpacked palette
                    int j = 0, i = 0;
                    while (j < tile_height) {
                        int palette_index = data[offset] & 0x7f;
                        Vec3b farbe = palette[palette_index];
                        int length = 1;
                        if (data[offset] & 0x80) { // run
                            offset++;
                            /* run length */
                            while (data[offset] == 0xff) {
                                length += data[offset++];
                            }
                            length += data[offset];
                        }
                        offset++;
                        while (j < tile_height && length > 0) {
                            a->img.at<Vec3b>(y + j, x + i) = farbe;
                            length--;
                            if (++i >= tile_width) {
                                i = 0;
                                j++;
                            }
                        }
                    }
                } else {
                    int mask = (1 << palette_bpp) - 1;
                    for (int j = 0; j < tile_height; j++) {
                        int shift = 8 - palette_bpp;
                        for (int i = 0; i < tile_width; i++) {
                            Vec3b farbe = palette[((data[offset]) >> shift) & mask];
                            a->img.at<Vec3b>(y + j, x + i) = farbe;

                            shift -= palette_bpp;
                            if (shift < 0) {
                                shift = 8 - palette_bpp;
                                offset++;
                            }
                        }
                        if (shift < 8 - palette_bpp)
                            offset++;
                    }
                }
            }
            w -= 64;
            x += 64;
        }
        h -= 64;
        y += 64;
    }

    return offset;
}
