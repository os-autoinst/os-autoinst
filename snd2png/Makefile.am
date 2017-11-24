bin_PROGRAMS = snd2png

snd2png_SOURCES = snd2png.cpp

AM_CXXFLAGS = -g3 -Wall -W
AM_CPPFLAGS = $(OPENCV_CFLAGS) $(FFTW_CFLAGS) $(SNDFILE_CFLAGS)
snd2png_LDFLAGS = $(OPENCV_LIBS) $(FFTW_LIBS) $(SNDFILE_LIBS) -lm

check-local:
	-rm -f test.png
	./snd2png $(srcdir)/aplay-captured.wav test.png
	md5sum test.png > test.png.md5
	diff -u test.png.md5 $(srcdir)/test.png.md5.original
