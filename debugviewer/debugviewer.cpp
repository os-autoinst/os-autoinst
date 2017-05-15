/*
   this is from the opencv documentation - just extended with a loop
*/

#include <iostream>
#include <opencv2/core/core.hpp>
#include <opencv2/highgui/highgui.hpp>

using namespace cv;
using namespace std;

int main(int argc, char** argv)
{
    if (argc != 2) {
        cout << " Usage: debugviewer qemuscreenshot/last.png" << endl;
        return -1;
    }

    Mat image(768, 1024, CV_8UC3, Scalar(0, 0, 0));
    while (1) {
        Mat last = imread(argv[1], CV_LOAD_IMAGE_COLOR); // Read the file
        if (last.data)
            image = last;

        namedWindow("Display window",
            WINDOW_AUTOSIZE); // Create a window for display.
        imshow("Display window", image); // Show our image inside it.

        if (waitKey(300) >= 0) // Wait for a keystroke in the window
            break;
    }
    return 0;
}
