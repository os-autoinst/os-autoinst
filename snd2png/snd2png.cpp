/*
  snd2png.cpp - idea is from http://snd2fftw.sourceforge.net/, but the code doesn't
  have more similiarity to its grandfather than to a random fftw example
*/

#include <stdio.h>
#include <stdlib.h>
#include <locale.h>
#include <memory.h>
#include <math.h>
#include <sndfile.h>
#include <fftw3.h>
#include <cv.h>
#include <highgui.h>

using namespace cv;

// error descriptions
static const char *ERR_NOT_ENOUGH_MEMORY = "Unable to allocate memory.\n";

static double
imabs (fftw_complex cpx)
{
  return sqrt ((cpx[0] * cpx[0]) + (cpx[1] * cpx[1]));
}

// boring linear interpolation
double
valueForFreq (double *points, int count, double freq)
{
  for (int i = 0; i < count; ++i)
    {

      if (points[i * 2] > freq)
	{
	  double next_freq = points[i * 2];
	  double next_value = points[i * 2 + 1];

	  double prev_freq = points[i * 2 - 2];
	  double prev_value = points[i * 2 - 1];

	  double value =
	    prev_value + (next_value - prev_value) * (freq -
						      prev_freq) /
	    (next_freq - prev_freq);
	  return value;
	}
    }
  // who knows
  return 0;
}

double
max_row_value (double *points, int count, int index)
{
  double max_value = 0;
  for (sf_count_t i = 0; i < count; i++)
    {
      double value = points[(index * count * 2 + i) * 2 + 1];
      if (value > max_value)
	max_value = value;
    }
  return max_value;
}

int
main (int argc, char *argv[])
{
  char *pszInputFile = argv[1];
  char *pszOutputFile = argv[2];

  SF_INFO info_in;
  SNDFILE *fIn = sf_open (pszInputFile, SFM_READ, &info_in);
  if (!fIn)
    {
      fprintf (stderr, "Unable to open input file \"%s\".\n", pszInputFile);
      sf_error (NULL);
      return 1;
    }

  float *infile_data =
    (float *) fftw_malloc (sizeof (float) * info_in.frames *
			   info_in.channels);
  if (!infile_data)
    {
      fprintf (stderr, ERR_NOT_ENOUGH_MEMORY);
      sf_close (fIn);
      return 2;
    }
  // read the full file
  sf_readf_float (fIn, infile_data, info_in.frames);
  sf_close (fIn);

  // average channels
  if (info_in.channels != 1)
    {
      for (sf_count_t n = 0; n < info_in.frames; n++)
	{
	  infile_data[n] = infile_data[n * info_in.channels];
	  for (int ch = 1; ch < info_in.channels; ch++)
	    infile_data[n] += infile_data[n * info_in.channels + ch];
	  infile_data[n] /= info_in.channels;
	}
    }

  // 10ms per chunk
  int window_size = info_in.samplerate / 100;
  // we take two variables to implement a possible overlap
  // it only makes sense for low sample rates
  sf_count_t nDftSamples = window_size;

  double *fftw_in = (double *) fftw_malloc (sizeof (double) * nDftSamples);
  if (!fftw_in)
    {
      fprintf (stderr, ERR_NOT_ENOUGH_MEMORY);
      return 2;
    }

  // output - complex data
  fftw_complex *fftw_out =
    (fftw_complex *) fftw_malloc (sizeof (fftw_complex) * nDftSamples);
  if (!fftw_out)
    {
      fprintf (stderr, ERR_NOT_ENOUGH_MEMORY);
      sf_close (fIn);
      return 2;
    }

  fftw_plan snd_plan = fftw_plan_dft_r2c_1d (nDftSamples,
					     fftw_in, fftw_out,
					     0);

  if (!snd_plan)
    {
      fprintf (stderr, "Fail to initialize FFTW plan.\n");
      fftw_free (fftw_in);
      fftw_free (fftw_out);
      return 2;
    }

  int times = info_in.frames / window_size + 1;
  double *points =
    (double *) malloc (sizeof (double) * nDftSamples * times * 2);
  memset (points, 0, sizeof (double) * nDftSamples * times * 2);
  double max_value = 0;

  for (int TimePos = 0; TimePos * window_size + nDftSamples < info_in.frames;
       TimePos++)
    {
      for (int i = 0; i < nDftSamples; i++)
	fftw_in[i] = infile_data[TimePos * window_size + i];

      fftw_execute (snd_plan);

      for (sf_count_t i = 0; i < nDftSamples / 2; i++)
	{
	  double freq =
	    (double) i * info_in.samplerate / (double) nDftSamples;
	  double value = imabs (fftw_out[i]) / 2.0;
	  points[(TimePos * nDftSamples + i) * 2] = freq;
	  points[(TimePos * nDftSamples + i) * 2 + 1] = value;
	  if (max_value < value)
	    max_value = value;
	}
    }

  int first_non_silence = 0;
  for (; first_non_silence < times; first_non_silence++)
    {
      if (max_row_value (points, nDftSamples / 2, first_non_silence) >
	  max_value * .1)
	break;
    }
  int last_non_silence = times;
  for (; last_non_silence > 0; last_non_silence--)
    {
      if (max_row_value (points, nDftSamples / 2, last_non_silence) >
	  max_value * .1)
	break;
    }


  int scale_factor = 3;
  int height = 768;		// make sure it can be devided by the scale_factor

  // we have to cover 3000 hz and 18 hz is the sitance between D4 and E4, so don't
  // go too low with the number of frequences to cover
  int freqs = height / scale_factor;
  Mat grayscaleMat (height, 1024, CV_8U, Scalar(255));

  for (int TimePos = first_non_silence; TimePos < last_non_silence; TimePos++)
    {
      for (int i = 0; i < freqs; ++i)
	{
	  // https://en.wikipedia.org/wiki/Voice_frequency
	  double max_freq = 3200.;
	  double freq = i * max_freq / freqs;
	  double value =
	    valueForFreq (points + (TimePos * nDftSamples) * 2,
			  nDftSamples / 2, freq);
	  int scaled = 255 - uchar (255 * value / max_value);
	  for (int j = 0; j < scale_factor; j++)
	    grayscaleMat.at < uchar > (height - i * scale_factor + j,
				       TimePos - first_non_silence) = scaled;
	}
    }

  imwrite (pszOutputFile, grayscaleMat);

  fftw_destroy_plan (snd_plan);
  fftw_free (fftw_in);
  fftw_free (fftw_out);
  return 0;
}
