
#include <stdio.h>
#include <iostream>
#include <exception>
#include <cerrno>
#include <sys/time.h>

#include <algorithm>    // std::min

#include "opencv2/core/core.hpp"
#include "opencv2/highgui/highgui.hpp"
#include "opencv2/calib3d/calib3d.hpp"
#include <opencv2/imgproc/imgproc.hpp>

#include "tinycv.h"

#define DEBUG 0

#define VERY_DIFF 0.0
#define VERY_SIM 1000000.0


using namespace cv;


struct Image {
  cv::Mat img;
};

// make box lines eq 0° or 90°
inline Point2f normalize_aspect(Point2f in, Point2f x, Point2f y) {
	Point2f out(in);
	out.y += y.y;
	out.y /= 2;
	out.x += x.x;
	out.x /= 2;
	return out;
}

/* the purpose of this function is to calculate the error between two images
  (scene area and object) ignoring slight colour changes */
double enhancedMSE(const Mat& _I1, const Mat& _I2) {
  Mat I1 = _I1;
  I1.convertTo(I1, CV_8UC1);
  Mat I2 = _I2;
  I2.convertTo(I2, CV_8UC1);

  assert(I1.channels() == 1);
  assert(I2.channels() == 1);

  double sse = 0;
  
  for (int j = 0; j < I1.rows; j++)
    {
      // get the address of row j
      const uchar* I1_data = I1.ptr<const uchar>(j);
      const uchar* I2_data = I2.ptr<const uchar>(j);
       
      for (int i = 0; i < I1.cols; i++)
        {
	  // reduce the colours to 16 before checking the diff
	  if (abs(I1_data[i] - I2_data[i]) < 16)
	    continue; // += 0
	  double t1 = round(I1_data[i] / 16.);
	  double t2 = round(I2_data[i] / 16.);
	  double diff = (t1 - t2) * 16;
	  sse += diff * diff;
        }
    }
  
  double total = I1.total();
  double mse = sse / total;

#if DEBUG
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

int MyErrorHandler(int status, const char* func_name, const char* err_msg, const char* file_name, int line, void*) {
	// suppress error msg's
	return 0;
}

std::vector<char> str2vec(std::string str_in) {
	std::vector<char> out(str_in.data(), str_in.data() + str_in.length());
	return out;
}

/* we find the object in the scene and return the x,y and the error of the match */
std::vector<int> search_TEMPLATE(const Image *scene, const Image *object, long x, long y, long width, long height, long margin, double &similarity) {
  // cvSetErrMode(CV_ErrModeParent);
  // cvRedirectError(MyErrorHandler);

#if DEBUG
  struct timeval tv1, tv2;
  gettimeofday(&tv1, 0);
#endif

  std::vector<int> outvec(2);

  if (scene->img.empty() || object->img.empty() ) {
    std::cerr << "Error reading images. Scene or object is empty." << std::endl;
    throw(std::exception());
  }

  // avoid an exception
  if ( x < 0 || y < 0 || y+height > scene->img.rows || x+width > scene->img.cols ) {
    std::cerr << "ERROR - search: out of range\n" << std::endl;
    return outvec;
  }
  
  // Optimization -- Search close to the original area working with ROI
  int scene_x = std::max(0, int(x-margin));
  int scene_y = std::max(0, int(y-margin));
  int scene_bottom_x = std::min(scene->img.cols, int(x+width+margin));
  int scene_bottom_y = std::min(scene->img.rows, int(y+height+margin));
  int scene_width = scene_bottom_x - scene_x;
  int scene_height = scene_bottom_y - scene_y;

  Mat scene_copy = scene->img.clone();
  Mat object_copy = object->img.clone();

  // blur the whole image to avoid differences depending on where the object is
  GaussianBlur(scene_copy, scene_copy, Size(3, 3), 0, 0);
  GaussianBlur(object_copy, object_copy, Size(3, 3), 0, 0);
  
  cvtColor(scene_copy, scene_copy, CV_BGR2GRAY );
  cvtColor(object_copy, object_copy, CV_BGR2GRAY );
  
  // Mat scene_roi = scene->img(Rect(scene_x, scene_y, scene_width, scene_height));
  // Mat object_roi = object->img(Rect(x, y, width, height));
  Mat scene_roi(scene_copy, Rect(scene_x, scene_y, scene_width, scene_height));
  Mat object_roi(object_copy, Rect(x, y, width, height));

  // Calculate size of result matrix and create it. If scene is W x H
  // and object is w x h, res is (W - w + 1) x ( H - h + 1)
  int result_width  = scene_roi.cols - width + 1; // object->img.cols + 1;
  int result_height = scene_roi.rows - height + 1; // object->img.rows + 1;
  if (result_width <= 0 || result_height <= 0) {
    similarity = 0;
    outvec[0] = 0;
    outvec[1] = 0;
    std::cerr << "ERROR2 - search: out of range\n" << std::endl;
    return outvec;
 }

  Mat result = Mat::zeros(result_height, result_width, CV_32FC1);

  // Perform the matching. Info about algorithm:
  // http://docs.opencv.org/trunk/doc/tutorials/imgproc/histograms/template_matching/template_matching.html
  // http://docs.opencv.org/modules/imgproc/doc/object_detection.html
  matchTemplate(scene_roi, object_roi, result, CV_TM_SQDIFF_NORMED);
    
  // Localizing the best match with minMaxLoc
  double minval, maxval;
  Point  minloc, maxloc;
  minMaxLoc(result, &minval, &maxval, &minloc, &maxloc, Mat());
  
  outvec[0] = int(minloc.x + scene_x);
  outvec[1] = int(minloc.y + scene_y);

  double mse = 10000;

  // detect the MSE at the given location
  Mat scene_best(scene_copy, Rect(outvec[0], outvec[1], width, height));

  mse = enhancedMSE(scene_best, object_roi);
  
  /* our callers expect a "how well does it match between 0-1", where 0.96 is defined as 
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
  std::cerr << "search_template "
	    <<  tdiff << " ms"
	    << " MSE " << mse
	    << " sim:" << similarity
	    << " minval:" << int(minval * 1000 + 0.5) << std::endl;
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

double getPSNR(const Mat& I1, const Mat& I2)
{
  Mat s1;
  absdiff(I1, I2, s1);       // |I1 - I2|
  s1.convertTo(s1, CV_32F);  // cannot make a square on 8 bits
  s1 = s1.mul(s1);           // |I1 - I2|^2

  Scalar s = sum(s1);        // sum elements per channel

  double sse = s.val[0] + s.val[1] + s.val[2]; // sum channels

  double mse = sse / (double)(I1.channels() * I1.total());
  if (!mse) {
    return VERY_SIM;
  }
  return 10.0 * log10((255 * 255) / mse);
}

void image_destroy(Image *s)
{
  delete(s);
}

Image *image_new(long width, long height)
{
  Image *image = new Image;
  image->img = Mat::zeros(height, width, CV_8UC3);
  return image;
}

Image *image_read(const char *filename)
{
  Image *image = new Image;
  image->img = imread(filename, CV_LOAD_IMAGE_COLOR);
  if (!image->img.data) {
    std::cerr << "Could not open image " << filename << std::endl;
    return 0L;
  }
  return image;
}

bool image_write(Image *s, const char *filename)
{
  vector<uchar> buf;
  vector<int> compression_params;
  compression_params.push_back(CV_IMWRITE_PNG_COMPRESSION);
  // compression level from 0-9, default is 3 but we go lower/faster
  // and let openQA run optipng on those we want to save
  compression_params.push_back(1);

  if (!imencode(".png", s->img, buf, compression_params)) {
    std::cerr << "Could not encode image " << filename << std::endl;
    return false;
  }
  string path = filename;
  string tpath = path + ".tmp";
  FILE *f = fopen(tpath.c_str(), "wx");
  if (!f) {
    std::cerr << "Could not write image " << tpath << std::endl;
    return false;
  }
  if (fwrite(buf.data(), 1, buf.size(), f) != buf.size()) {
    std::cerr << "Could not write to image " << tpath << std::endl;
    return false;
  }
  fclose(f);
  if (rename(tpath.c_str(), path.c_str())) {
    std::cerr << "Could not rename " << tpath << errno << std::endl;
    return false;
  }
  return true;
}

static std::vector<uchar> convert_to_ppm(const Mat &s, int &header_length)
{
  vector<uchar> buf;
  if (!imencode(".ppm", s, buf)) {
    fprintf(stderr, "convert_to_ppm failed\n");
    header_length = 0;
    return buf;
  }
  
  const char *cbuf = reinterpret_cast<const char*> (&buf[0]);
  const char *cbuf_start = cbuf;
  // the perl code removed the header before md5, 
  // so we need to do the same
  cbuf = strchr(cbuf, '\n') + 1; // "P6\n";
  cbuf = strchr(cbuf, '\n') + 1; // "800 600\n";
  cbuf = strchr(cbuf, '\n') + 1; // "255\n";

  header_length = cbuf - cbuf_start;
  return buf;
}

Image *image_copy(Image *s)
{
  Image *ni = new Image();
  s->img.copyTo(ni->img);
  return ni;
}

long image_xres(Image *s)
{
  return s->img.cols;
}

long image_yres(Image *s)
{
  return s->img.rows;
}

/* 
 * in the image s replace all pixels in the given range with 0 - in place
 */
void image_replacerect(Image *s, long x, long y, long width, long height)
{
  // avoid an exception
  if ( x < 0 || y < 0 || y+height > s->img.rows || x+width > s->img.cols ) {
    std::cerr << "ERROR - replacerect: out of range\n" << std::endl;
    return;
  }

  rectangle(s->img, Rect(x, y, width, height), CV_RGB(0, 255, 0), CV_FILLED);
}

/* copies the given range into a new image */
Image *image_copyrect(Image *s, long x, long y, long width, long height)
{
  // avoid an exception
  if ( x < 0 || y < 0 || y+height > s->img.rows || x+width > s->img.cols ) {
    std::cerr << "ERROR - copyrect: out of range\n" << std::endl;
    return 0;
  }

  Image *n = new Image;
  Mat tmp = Mat(s->img, Range(y, y+height), Range(x,x+width));
  n->img = tmp.clone();
  return n;
}

// in-place op: change all values to 0 (if below threshold) or 255 otherwise
void image_threshold(Image *s, int level)
{
  int header_length;
  vector<uchar> buf = convert_to_ppm(s->img, header_length);

  vector<uchar>::iterator it = buf.begin() + header_length;
  for (; it != buf.end(); ++it) {
    *it = (*it < level) ? 0 : 0xff;
  }
  s->img = imdecode(buf, 1);
}

std::vector<float> image_avgcolor(Image *s)
{
  Scalar t = mean(s->img);

  vector<float> f;
  f.push_back(t[2] / 255.0); // Red
  f.push_back(t[1] / 255.0); // Green
  f.push_back(t[0] / 255.0); // Blue

  return f;
}

std::vector<int> image_search(Image *s, Image *needle, long x, long y, long width, long height, long margin, double &similarity)
{
  return search_TEMPLATE(s, needle, x, y, width, height, margin, similarity);
}


Image *image_scale(Image *a, int width, int height)
{
  Image *n = new Image;

  /* first scale down in case */
  if (a->img.rows > height || a->img.cols > width) {
    n->img = Mat(height, width, a->img.type());
    resize(a->img, n->img, n->img.size());
  } else if (n->img.rows < height || n->img.cols < width) {
    n->img = Mat::zeros(height, width, a->img.type());
    n->img = cv::Scalar(120,120,120);
    a->img.copyTo(n->img(Rect(0, 0, a->img.cols, a->img.rows)));
  } else 
    n->img = a->img;

  return n;
}

double image_similarity(Image *a, Image*b)
{
  if (a->img.rows != b->img.rows)
    return VERY_DIFF;

  if (a->img.cols != b->img.cols)
    return VERY_DIFF;

  return getPSNR(a->img, b->img);
}


Image *image_absdiff(Image *a, Image *b)
{
  Image *n = new Image;

  Mat t;
  absdiff(a->img, b->img, t);
  n->img = t;

  return n;
}

void image_map_raw_data(Image *a, const unsigned char *data)
{
  for (int y = 0; y < a->img.rows; y++) {
    for (int x = 0; x < a->img.cols; x++) {
      unsigned char red = *data++;
      unsigned char blue = *data++;
      unsigned char green = *data++;
      data++; // 4th ignored
      a->img.at<cv::Vec3b>(y, x)[0] = red;
      a->img.at<cv::Vec3b>(y, x)[1] = blue;      
      a->img.at<cv::Vec3b>(y, x)[2] = green;
    }
  }
}


void image_map_raw_data_rgb555(Image *a, const unsigned char *data)
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
      a->img.at<cv::Vec3b>(y, x)[0] = blue;
      a->img.at<cv::Vec3b>(y, x)[1] = green;
      a->img.at<cv::Vec3b>(y, x)[2] = red;
    }
  }
}

void image_map_raw_data_full(Image* a, unsigned char *data,
			     bool do_endian_conversion,
			     unsigned int bytes_per_pixel,
			     unsigned int red_mask,   unsigned int red_shift,
			     unsigned int green_mask, unsigned int green_shift,
			     unsigned int blue_mask,  unsigned int blue_shift)
{
  unsigned char blue_skale  = 256 / (blue_mask  + 1);
  unsigned char green_skale = 256 / (green_mask + 1);
  unsigned char red_skale   = 256 / (red_mask   + 1);
  for (int y = 0; y < a->img.rows; y++) {
    for (int x = 0; x < a->img.cols; x++) {
      long pixel;
      if (bytes_per_pixel == 2) {
	if (do_endian_conversion) {
	  pixel = *data++ * 256;
	  pixel += *data++;
	}
	else {
	  pixel = *data++;
	  pixel += *data++ * 256;
	};
      }
      else if (bytes_per_pixel == 4) {
	if (do_endian_conversion) {
	  pixel = *data++;
	  pixel <<=8;
	  pixel |= *data++;
	  pixel <<=8;
	  pixel |= *data++;
	  pixel <<=8;
	  pixel |= *data++;
	}
	else {
	  pixel = *(long*)data;
	  data += 4;
	}
      }
      else {
	// just fail miserably for unsupported bytes per pixel
	abort();
      };
      unsigned char blue  = (pixel >> blue_shift  & blue_mask ) * blue_skale;
      unsigned char green = (pixel >> green_shift & green_mask) * green_skale;
      unsigned char red   = (pixel >> red_shift   & red_mask  ) * red_skale;
      // MSB ignored
      a->img.at<cv::Vec3b>(y, x)[0] = blue;
      a->img.at<cv::Vec3b>(y, x)[1] = green;
      a->img.at<cv::Vec3b>(y, x)[2] = red;
    }
  }
}
// copy the s image into a at x,y
void image_blend_image(Image *a, Image *s, long x, long y)
{
  cv::Rect roi( cv::Point( x, y ), s->img.size() );
  s->img.copyTo( a->img( roi ) );
}
