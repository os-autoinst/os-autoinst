bin_PROGRAMS = snd2png

snd2png_SOURCES = snd2png.cpp

AM_CXXFLAGS = -g3 -Wall -W
AM_CPPFLAGS = $(OPENCV_CFLAGS) $(FFTW_CFLAGS) $(SNDFILE_CFLAGS)
snd2png_LDFLAGS = $(OPENCV_LIBS) $(FFTW_LIBS) $(SNDFILE_LIBS) -lm

check-local:
	-rm -f test.pnm
	./snd2png $(srcdir)/aplay-captured.wav test.pnm
	md5sum test.pnm > test.pnm.md5
	diff -u test.pnm.md5 $(srcdir)/test.pnm.md5.original
