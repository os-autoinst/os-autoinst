noinst_PROGRAMS = debugviewer

debugviewer_SOURCES = debugviewer.cpp

AM_CPPFLAGS = $(pkg-config --cflags opencv)
debugviewer_LDFLAGS = $(shell pkg-config --libs opencv)

