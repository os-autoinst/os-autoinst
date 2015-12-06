noinst_PROGRAMS = snd2png

snd2png_SOURCES = snd2png.cpp

AM_CPPFLAGS = $(shell pkg-config --cflags opencv)
snd2png_LDFLAGS = $(shell pkg-config --libs opencv) -lfftw3 -lm -lsndfile 

