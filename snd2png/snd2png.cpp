
/*
  snd2png.cpp - idea is from http://snd2fftw.sourceforge.net/, but the code
  doesn't
  have more similiarity to its grandfather than to a random fftw example
*/

#include <fftw3.h>
#include <highgui.h>
#include <locale.h>
#include <math.h>
#include <memory.h>
#include <opencv2/opencv.hpp>
#include <sndfile.h>
#include <stdio.h>
#include <stdlib.h>

using namespace cv;

// error descriptions
static const char* ERR_NOT_ENOUGH_MEMORY = "Unable to allocate memory.\n";

static double imabs(fftw_complex cpx)
{
    return sqrt((cpx[0] * cpx[0]) + (cpx[1] * cpx[1]));
}

// boring linear interpolation
double valueForFreq(double* points, int bin, double ratio)
{
   if (bin == 0)
        return points[0];

    double next_value = points[bin];
    double prev_value = points[bin - 1];

    double value = ratio * prev_value + (1.0 - ratio) * next_value;
    return value;
}

double max_row_value(double* points, int count)
{
    double max_value = 0;
    for (sf_count_t i = 0; i < count; i++) {
        double value = points[i];
        if (value > max_value)
            max_value = value;
    }
    return max_value;
}

int main(int argc, char* argv[])
{
    if (argc < 3) {
        fprintf(stderr, "Usage: snd2png soundfile imagefile\n");
        return 1;
    }

    char* pszInputFile = argv[1];
    char* pszOutputFile = argv[2];

    SF_INFO info_in;
    memset(&info_in, 0, sizeof(SF_INFO));
    SNDFILE* fIn = sf_open(pszInputFile, SFM_READ, &info_in);
    if (!fIn) {
        fprintf(stderr, "Unable to open input file \"%s\".\n", pszInputFile);
        sf_error(NULL);
        return 1;
    }

    fprintf(stderr, "snd2png: %d channels, samplerate %d Hz, %ld frames (%.2f seconds)\n", info_in.channels,
            info_in.samplerate, info_in.frames, (float)(info_in.frames)/info_in.samplerate);

    float* infile_data = (float*)fftw_malloc(sizeof(float) * info_in.frames * info_in.channels);
    if (!infile_data) {
        fputs(ERR_NOT_ENOUGH_MEMORY, stderr);
        sf_close(fIn);
        return 2;
    }

    // read the full file
    sf_readf_float(fIn, infile_data, info_in.frames);
    sf_close(fIn);

    // average channels
    if (info_in.channels != 1) {
        for (sf_count_t n = 0; n < info_in.frames; n++) {
            infile_data[n] = infile_data[n * info_in.channels];
            for (int ch = 1; ch < info_in.channels; ch++)
                infile_data[n] += infile_data[n * info_in.channels + ch];
            infile_data[n] /= info_in.channels;
        }
    }

    // 10ms per chunk
    int window_size = info_in.samplerate / (1000 / 10);
    sf_count_t overlap = window_size / 2;
    sf_count_t nDftSamples = window_size + overlap * 2;

    fprintf(stderr, "snd2png: %ld frequency bins\n", nDftSamples);

    double* fftw_in = (double*)fftw_malloc(sizeof(double) * nDftSamples);
    if (!fftw_in) {
        fputs(ERR_NOT_ENOUGH_MEMORY, stderr);
        return 2;
    }

    // output - complex data
    fftw_complex* fftw_out = (fftw_complex*)fftw_malloc(sizeof(fftw_complex) * nDftSamples);
    if (!fftw_out) {
        fputs(ERR_NOT_ENOUGH_MEMORY, stderr);
        sf_close(fIn);
        return 2;
    }

    fftw_plan snd_plan = fftw_plan_dft_r2c_1d(nDftSamples, fftw_in, fftw_out, FFTW_ESTIMATE);

    if (!snd_plan) {
        fprintf(stderr, "Fail to initialize FFTW plan.\n");
        fftw_free(fftw_in);
        fftw_free(fftw_out);
        return 2;
    }

    int times = info_in.frames / window_size - 1;
    if (times * window_size + overlap > info_in.frames)
        times--;

    fprintf(stderr, "spectogram samples: %d\n", times);

    // https://en.wikipedia.org/wiki/Voice_frequency
    double max_freq = 3200.;
    double fft_max_freq = info_in.samplerate / 2.0;
    int last_bin = std::min(int(1 + ceil(max_freq / fft_max_freq * (nDftSamples/2.0))), int(1 + nDftSamples/2.0));
    double fft_bw = fft_max_freq / (nDftSamples / 2.0);

    double** points = (double**)malloc(sizeof(double*) * times);
    double max_value = 0;

    for (int TimePos = 0; TimePos < times; TimePos++) {
        for (int i = 0; i < nDftSamples; i++) {
            fftw_in[i] = infile_data[TimePos * window_size + i];
        }

        fftw_execute(snd_plan);

        points[TimePos] = (double*)malloc(sizeof(double) * last_bin);
        memset(points[TimePos], 0, sizeof(double) * last_bin);
        for (sf_count_t i = 0; i < last_bin; i++) {
            double value = imabs(fftw_out[i]);
            points[TimePos][i] = value;
            if (max_value < value)
                max_value = value;
        }
    }

    fprintf(stderr, "max amplitude: %lf\n", max_value / 2.0);

    // SILENCE, I'll kill you!
    int first_non_silence = 0;
    for (; first_non_silence < times; first_non_silence++) {
        if (max_row_value(points[first_non_silence], last_bin) > max_value * .1)
            break;
    }
    int last_non_silence = times - 1;
    for (; last_non_silence > 0; last_non_silence--) {
        if (max_row_value(points[last_non_silence], last_bin) > max_value * .1)
            break;
    }

    int scale_factor = 3;
    int height = 768; // make sure it can be devided by the scale_factor

    // we have to cover 3000 hz and 18 hz is the sitance between D4 and E4, so
    // don't
    // go too low with the number of frequences to cover
    int freqs = height / scale_factor;
    Mat grayscaleMat(height, 1024, CV_8U, Scalar(255));

    if (last_non_silence - first_non_silence >= grayscaleMat.cols)
        last_non_silence = grayscaleMat.cols - first_non_silence - 1;

    fprintf(stderr, "silences: %d %d\n", first_non_silence, last_non_silence);
    for (int i = 1; i < freqs; ++i) {
        double freq = i * max_freq / freqs;
        int bin = ceil(freq/fft_bw);
        double ratio = bin - (freq/fft_bw);

        for (int TimePos = first_non_silence; TimePos < last_non_silence; TimePos++) {
            double value = valueForFreq(points[TimePos], bin, ratio);

            int scaled = 255 - uchar(255 * value / max_value);
            for (int j = 0; j < scale_factor; j++) {
                grayscaleMat.at<uchar>(height - 1 - i * scale_factor + j,
                    TimePos - first_non_silence)
                    = scaled;
            }
        }
    }

    imwrite(pszOutputFile, grayscaleMat);

    for (int TimePos = 0; TimePos < times; TimePos++) {
        free(points[TimePos]);
    }
    free(points);

    fftw_destroy_plan(snd_plan);
    fftw_free(fftw_in);
    fftw_free(fftw_out);
    fftw_free(infile_data);
    return 0;
}
