
#include <stdio.h>
#include <iostream>
#include <exception>

#include "opencv2/core/core.hpp"
#include "opencv2/highgui/highgui.hpp"
#include "opencv2/calib3d/calib3d.hpp"
#include <opencv2/imgproc/imgproc.hpp>

#include "tinycv.h"

#define DEBUG 0

using namespace cv;

// make box lines eq 0° or 90°
inline Point2f normalize_aspect(Point2f in, Point2f x, Point2f y) {
	Point2f out(in);
	out.y += y.y;
	out.y /= 2;
	out.x += x.x;
	out.x /= 2;
	return out;
}

int MyErrorHandler(int status, const char* func_name, const char* err_msg, const char* file_name, int line, void*) {
	// suppress error msg's
	return 0;
}

std::vector<char> str2vec(std::string str_in) {
	std::vector<char> out(str_in.data(), str_in.data() + str_in.length());
	return out;
}

std::vector<int> search_TEMPLATE(std::string str_scene, std::string str_object) {
	cvSetErrMode(CV_ErrModeParent);
	cvRedirectError(MyErrorHandler);

	std::vector<char> data_scene = str2vec(str_scene);
	std::vector<char> data_object = str2vec(str_object);

	Mat img_scene =  imdecode(Mat(data_scene),  CV_LOAD_IMAGE_COLOR );
	Mat img_object = imdecode(Mat(data_object), CV_LOAD_IMAGE_COLOR );

	if( !img_object.data || !img_scene.data ) {
		std::cerr<< "Error reading images" << std::endl;
		throw(std::exception());
	}

	// Calculate size of result matrix and create it
	int res_width  = img_scene.cols - img_object.cols + 1;
	int res_height = img_scene.rows - img_object.rows + 1;
	Mat res = Mat::zeros(res_height, res_width, CV_32FC1);

	// Perform the matching
	// infos about algorythms: http://docs.opencv.org/trunk/doc/tutorials/imgproc/histograms/template_matching/template_matching.html
	matchTemplate(img_scene, img_object, res, CV_TM_CCOEFF_NORMED);

	// Get minimum and maximum values from result matrix
	double minval, maxval;
	Point  minloc, maxloc;
	minMaxLoc(res, &minval, &maxval, &minloc, &maxloc, Mat());

	#if DEBUG
	Mat res_out;
	normalize( res, res_out, 0, 255, NORM_MINMAX, -1, Mat() );
	if(res.cols == 1 && res.rows == 1) {
		float dataval = res.at<float>(0,0);
		res_out.at<float>(0,0) = dataval * 255;
	}
	res_out.convertTo(res_out, CV_8UC1);
	imwrite("result.ppm", res_out);
	#endif

	// Check if we have a match
	if(maxval > 0.9) {
		#if DEBUG
		rectangle(img_scene, Point(maxloc.x, maxloc.y), Point(maxloc.x + img_object.cols, maxloc.y + img_object.rows), CV_RGB(255,0,0), 3);
		imwrite("debug.ppm", img_scene);
		#endif
		std::vector<int> outvec(4);
		outvec[0] = int(maxloc.x);
		outvec[1] = int(maxloc.y);
		outvec[2] = int(maxloc.x + img_object.cols);
		outvec[3] = int(maxloc.y + img_object.rows);
		return outvec;
	}
	else {
		std::vector<int> outvec(0);
		return outvec;
	}
}
