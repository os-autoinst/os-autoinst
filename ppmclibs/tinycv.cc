
#include <stdio.h>
#include <iostream>
#include <exception>

#include "opencv2/core/core.hpp"
#include "opencv2/features2d/features2d.hpp"
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

std::vector<int> search_SURF(std::string str_scene, std::string str_object) {
	cvSetErrMode(CV_ErrModeParent);
	cvRedirectError(MyErrorHandler);

	std::vector<char> data_scene = str2vec(str_scene);
	std::vector<char> data_object = str2vec(str_object);

	Mat img_object = imdecode(Mat(data_object), CV_LOAD_IMAGE_COLOR );
	Mat img_scene =  imdecode(Mat(data_scene),  CV_LOAD_IMAGE_COLOR );

	if( !img_object.data || !img_scene.data ) {
		std::cerr<< "Error reading images" << std::endl;
		throw(std::exception());
	}

	//-- Step 1: Detect the keypoints using SURF Detector
	int minHessian = 400;

	SurfFeatureDetector detector( minHessian );

	std::vector<KeyPoint> keypoints_object, keypoints_scene;

	detector.detect( img_object, keypoints_object );
	detector.detect( img_scene, keypoints_scene );

	//-- Step 2: Calculate descriptors (feature vectors)
	SurfDescriptorExtractor extractor;

	Mat descriptors_object, descriptors_scene;

	extractor.compute( img_object, keypoints_object, descriptors_object );
	extractor.compute( img_scene, keypoints_scene, descriptors_scene );

	//-- Step 3: Matching descriptor vectors using FLANN matcher
	FlannBasedMatcher matcher;
	std::vector< DMatch > matches;
	matcher.match( descriptors_object, descriptors_scene, matches );

	double max_dist = 0; double min_dist = 100;

	//-- Quick calculation of max and min distances between keypoints
	for( int i = 0; i < descriptors_object.rows; i++ ) {
		double dist = matches[i].distance;
		if( dist < min_dist ) min_dist = dist;
		if( dist > max_dist ) max_dist = dist;
	}

	//printf("-- Max dist : %f \n", max_dist );
	//printf("-- Min dist : %f \n", min_dist );

	//-- Draw only "good" matches (i.e. whose distance is less than 3*min_dist )
	std::vector< DMatch > good_matches;

	for( int i = 0; i < descriptors_object.rows; i++ ) {
		if( matches[i].distance < 3*min_dist ) {
			good_matches.push_back( matches[i]);
		}
	}

	Mat img_matches;
	drawMatches( img_object, keypoints_object, img_scene, keypoints_scene,
			   good_matches, img_matches, Scalar::all(-1), Scalar::all(-1),
			   vector<char>(), DrawMatchesFlags::NOT_DRAW_SINGLE_POINTS );


	//-- Localize the object from img_1 in img_2
	std::vector<Point2f> obj;
	std::vector<Point2f> scene;

	for( size_t i = 0; i < good_matches.size(); i++ ) {
		//-- Get the keypoints from the good matches
		obj.push_back( keypoints_object[ good_matches[i].queryIdx ].pt );
		scene.push_back( keypoints_scene[ good_matches[i].trainIdx ].pt );
	}

	try {
		Mat H = findHomography( obj, scene, CV_RANSAC );

		//-- Get the corners from the image_1 ( the object to be "detected" )
		std::vector<Point2f> obj_corners(4);
		obj_corners[0] = cvPoint(0,0); obj_corners[1] = cvPoint( img_object.cols, 0 );
		obj_corners[2] = cvPoint( img_object.cols, img_object.rows ); obj_corners[3] = cvPoint( 0, img_object.rows );
		std::vector<Point2f> scene_corners(4);

		perspectiveTransform( obj_corners, scene_corners, H);

		#if DEBUG
		//-- Draw lines between the corners (the mapped object in the scene - image_2 )
		Point2f offset( (float)img_object.cols, 0);
		line( img_matches, scene_corners[0] + offset, scene_corners[1] + offset, Scalar( 0, 255, 0), 4 );
		line( img_matches, scene_corners[1] + offset, scene_corners[2] + offset, Scalar( 0, 255, 0), 4 );
		line( img_matches, scene_corners[2] + offset, scene_corners[3] + offset, Scalar( 0, 255, 0), 4 );
		line( img_matches, scene_corners[3] + offset, scene_corners[0] + offset, Scalar( 0, 255, 0), 4 );
		#endif

		// normalize aspect
		std::vector<Point2f> match_box(4);
		match_box[0] = normalize_aspect(scene_corners[0], scene_corners[3], scene_corners[1]);
		match_box[2] = normalize_aspect(scene_corners[2], scene_corners[1], scene_corners[3]);
		match_box[1] = Point2f(match_box[0].x, match_box[2].y);
		match_box[3] = Point2f(match_box[2].x, match_box[0].y);

		#if DEBUG
		line( img_matches, match_box[0] + offset, match_box[1] + offset, Scalar( 255, 0, 0), 4 );
		line( img_matches, match_box[1] + offset, match_box[2] + offset, Scalar( 255, 0, 0), 4 );
		line( img_matches, match_box[2] + offset, match_box[3] + offset, Scalar( 255, 0, 0), 4 );
		line( img_matches, match_box[3] + offset, match_box[0] + offset, Scalar( 255, 0, 0), 4 );
		#endif

		//-- Show detected matches
		//printf("match at %ix%i\n", int(match_box[0].x), int(match_box[0].y));
		std::vector<int> outvec(4);
		outvec[0] = int(match_box[0].x);
		outvec[1] = int(match_box[0].y);
		outvec[2] = int(match_box[2].x);
		outvec[3] = int(match_box[2].y);

		#if DEBUG
		imwrite("debug.ppm", img_matches);
		#endif
		return outvec;
	}
	catch(const cv::Exception& e) {
		if(e.code == -215) {
			std::vector<int> vec_out(0);
			return vec_out;
			//printf("did not match\n");
		}
		else {
			throw(e);
		}
	}

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
