/* Modified by Stephan Kulow <coolo@suse.de> 2014 to take the PNGs
   from stdin and use opencv directly */
/* Modified by Stephan Kulow <coolo@suse.de> 2016 to take the PNGs
   from external file and back */

/********************************************************************
 *                                                                  *
 * THIS FILE IS PART OF THE OggTheora SOFTWARE CODEC SOURCE CODE.   *
 * USE, DISTRIBUTION AND REPRODUCTION OF THIS LIBRARY SOURCE IS     *
 * GOVERNED BY A BSD-STYLE SOURCE LICENSE INCLUDED WITH THIS SOURCE *
 * IN 'COPYING'. PLEASE READ THESE TERMS BEFORE DISTRIBUTING.       *
 *                                                                  *
 * THE Theora SOURCE CODE IS COPYRIGHT (C) 2002-2009,2009           *
 * by the Xiph.Org Foundation and contributors http://www.xiph.org/ *
 *                                                                  *
 ********************************************************************

  function: example encoder application; makes an Ogg Theora
            file from a sequence of png images
  last mod: $Id$
             based on code from Vegard Nossum

Commands can be: E src_image or R:
  * E src_image will add src_image to the video as a new frame
  * R will wait until a new command is recieved

This program will wait until it recieves a TERM signal to complete the
video.

 ********************************************************************/

#define _FILE_OFFSET_BITS 64

#include "theora/theoraenc.h"
#include <cassert>
#include <cstdio>
#include <getopt.h>
#include <ogg/ogg.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

using namespace std;

const char* option_output;

static FILE* ogg_fp = NULL;
static ogg_stream_state ogg_os;
static ogg_packet op;
static ogg_page og;

static th_enc_ctx* td;
static th_info ti;

int loop = 1;

static int theora_write_frame(th_ycbcr_buffer ycbcr, int last)
{
    ogg_packet op;
    ogg_page og;
    assert(ogg_fp);

    /* Theora is a one-frame-in,one-frame-out system; submit a frame
   for compression and pull out the packet */
    if (th_encode_ycbcr_in(td, ycbcr)) {
        fprintf(stderr, "%s: error: could not encode frame\n", option_output);
        return 1;
    }

    if (!th_encode_packetout(td, last, &op)) {
        fprintf(stderr, "%s: error: could not read packets\n", option_output);
        return 1;
    }

    ogg_stream_packetin(&ogg_os, &op);
    while (ogg_stream_pageout(&ogg_os, &og)) {
        fwrite(og.header, og.header_len, 1, ogg_fp);
        fwrite(og.body, og.body_len, 1, ogg_fp);
    }
    return 0;
}

static unsigned char clamp(int d)
{
    if (d < 0)
        return 0;

    if (d > 255)
        return 255;

    return d;
}

#include <opencv2/core/core.hpp>
#include <opencv2/opencv.hpp>
#include <stdio.h>

using namespace cv;

void rgb_to_yuv(Mat* image, th_ycbcr_buffer ycbcr)
{
    unsigned int x;
    unsigned int y;

    unsigned long yuv_w;

    unsigned char* yuv_y;
    unsigned char* yuv_u;
    unsigned char* yuv_v;

    unsigned long w, h;
    w = yuv_w = 1024;
    /* Must hold: yuv_h >= h */
    h = 768;

    yuv_w = ycbcr[0].width;

    yuv_y = ycbcr[0].data;
    yuv_u = ycbcr[1].data;
    yuv_v = ycbcr[2].data;

    /*This ignores gamma and RGB primary/whitepoint differences.
   It also isn't terribly fast (though a decent compiler will
   strength-reduce the division to a multiplication). */

    for (y = 0; y < h; y++) {
        for (x = 0; x < w; x++) {
            unsigned char b = image->data[image->channels() * (image->cols * y + x) + 0];
            unsigned char g = image->data[image->channels() * (image->cols * y + x) + 1];
            unsigned char r = image->data[image->channels() * (image->cols * y + x) + 2];

            yuv_y[x + y * yuv_w] = clamp((65481 * r + 128553 * g + 24966 * b + 4207500) / 255000);
            yuv_u[x + y * yuv_w] = clamp((-33488 * r - 65744 * g + 99232 * b + 29032005) / 225930);
            yuv_v[x + y * yuv_w] = clamp((157024 * r - 131488 * g - 25536 * b + 45940035) / 357510);
        }
    }
}

static int ilog(unsigned _v)
{
    int ret;
    for (ret = 0; _v; ret++)
        _v >>= 1;
    return ret;
}

bool need_last_png() { return !access("live_log", R_OK); }

int main(int argc, char* argv[])
{
    th_comment tc;
    int ret;

    bool output_video = true;
    int opt;
    while ((opt = getopt(argc, argv, "n")) != -1) {
        switch (opt) {
        case 'n':
            output_video = false;
            break;
        default: /* '?' */
            fprintf(stderr,
                "%s: [-n] CMDS OUTPUT - reads commands from CMDS until TERMed\n",
                argv[0]);
            exit(EXIT_FAILURE);
        }
    }

    if (optind != argc - 1) {
        fprintf(stderr, "Expected CMDS and OUTPUT\n");
        exit(EXIT_FAILURE);
    }

    option_output = argv[optind];

    if (output_video) {
        ogg_fp = fopen(option_output, "wb");
        if (!ogg_fp) {
            fprintf(stderr, "%s: error: %s\n", option_output,
                    "couldn't open output file");
            return 1;
        }
    }

    srand(time(NULL));
    if (ogg_stream_init(&ogg_os, rand())) {
        fprintf(stderr, "%s: error: %s\n", option_output,
            "couldn't create ogg stream state");
        return 1;
    }

    unsigned int w = 1024;
    unsigned int h = 768;
    th_ycbcr_buffer ycbcr;

    ycbcr[0].width = w;
    ycbcr[0].height = h;
    ycbcr[0].stride = w;
    ycbcr[1].width = w;
    ycbcr[1].stride = ycbcr[1].width;
    ycbcr[1].height = h;
    ycbcr[2].width = ycbcr[1].width;
    ycbcr[2].stride = ycbcr[1].stride;
    ycbcr[2].height = ycbcr[1].height;

    ycbcr[0].data = (unsigned char*)malloc(ycbcr[0].stride * ycbcr[0].height);
    ycbcr[1].data = (unsigned char*)malloc(ycbcr[1].stride * ycbcr[1].height);
    ycbcr[2].data = (unsigned char*)malloc(ycbcr[2].stride * ycbcr[2].height);

    ogg_uint32_t keyframe_frequency = 64;

    th_info_init(&ti);
    ti.frame_width = ((w + 15) >> 4) << 4;
    ti.frame_height = ((h + 15) >> 4) << 4;
    ti.pic_width = w;
    ti.pic_height = h;
    ti.pic_x = 0;
    ti.pic_y = 0;
    ti.fps_numerator = 24;
    ti.fps_denominator = 1;
    ti.aspect_numerator = 0;
    ti.aspect_denominator = 0;
    ti.colorspace = TH_CS_UNSPECIFIED;
    ti.pixel_fmt = TH_PF_444;
    ti.target_bitrate = -1;
    ti.quality = 48; /* 63 is maximum */
    ti.keyframe_granule_shift = ilog(keyframe_frequency - 1);

    td = th_encode_alloc(&ti);
    th_info_clear(&ti);

    /* setting just the granule shift only allows power-of-two keyframe
   spacing.  Set the actual requested spacing. */
    ret = th_encode_ctl(td, TH_ENCCTL_SET_KEYFRAME_FREQUENCY_FORCE,
        &keyframe_frequency, sizeof(keyframe_frequency - 1));
    if (ret < 0) {
        fprintf(stderr, "Could not set keyframe interval to %d.\n",
            (int)keyframe_frequency);
    }
    /* write the bitstream header packets with proper page interleave */
    th_comment_init(&tc);
    /* first packet will get its own page automatically */
    if (th_encode_flushheader(td, &tc, &op) <= 0) {
        fprintf(stderr, "Internal Theora library error.\n");
        exit(1);
    }
    th_comment_clear(&tc);
    ogg_stream_packetin(&ogg_os, &op);
    if (ogg_stream_pageout(&ogg_os, &og) != 1) {
        fprintf(stderr, "Internal Ogg library error.\n");
        exit(1);
    }
    if (ogg_fp) {
        fwrite(og.header, 1, og.header_len, ogg_fp);
        fwrite(og.body, 1, og.body_len, ogg_fp);
    }
    /* create the remaining theora headers */
    for (;;) {
        ret = th_encode_flushheader(td, &tc, &op);
        if (ret < 0) {
            fprintf(stderr, "Internal Theora library error.\n");
            exit(1);
        } else if (!ret)
            break;
        ogg_stream_packetin(&ogg_os, &op);
    }
    /* Flush the rest of our headers. This ensures
   the actual data in each stream will start
   on a new page, as per spec. */
    for (;;) {
        int result = ogg_stream_flush(&ogg_os, &og);
        if (result < 0) {
            /* can't get here */
            fprintf(stderr, "Internal Ogg library error.\n");
            exit(1);
        }
        if (result == 0)
            break;
        if (ogg_fp) {
            fwrite(og.header, 1, og.header_len, ogg_fp);
            fwrite(og.body, 1, og.body_len, ogg_fp);
        }
    }

    char line[PATH_MAX + 10];
    int fsls = 0; // frames since last sync

    Mat last_frame_image;
    bool last_frame_converted = false;

    while (fgets(line, PATH_MAX + 8, stdin)) {
        line[strlen(line) - 1] = 0;

        if (line[0] == 'E') {
            int len = 0;
            if (sscanf(line, "E %d", &len) != 1) {
                fprintf(stderr, "Can't parse %s\n", line);
                exit(1);
            }
            uchar* buffer = new uchar[len];
            size_t r = fread(buffer, len, 1, stdin);
            if (r != 1) {
                fprintf(stderr, "Unexpected end of data %ld\n", r);
                exit(1);
            }
            last_frame_converted = false;

            if (output_video || need_last_png()) {
                vector<uchar> buf(buffer, buffer + len);
                last_frame_image = imdecode(buf, CV_LOAD_IMAGE_COLOR);

                if (!last_frame_image.data) {
                    cout << "Could not open or find the image" << endl;
                    return -1;
                }
            }
            delete[] buffer;

            if (output_video)
                rgb_to_yuv(&last_frame_image, ycbcr);

        } else if (line[0] == 'R') {
            // Just repeat the last frame
        } else {
            fprintf(stderr, "unknown command line: %s\n", line);
        }

        if (!last_frame_converted && need_last_png()) {
            struct timeval tv;
            gettimeofday(&tv, 0);
            char path[PATH_MAX];
            sprintf(path, "qemuscreenshot/%ld.%ld.png", tv.tv_sec, tv.tv_usec);
            imwrite(path, last_frame_image);
            unlink("qemuscreenshot/last.png");
            symlink(basename(path), "qemuscreenshot/last.png");
            last_frame_converted = true;
        }

        if (output_video) {
            if (theora_write_frame(ycbcr, 0)) {
                fprintf(stderr, "Encoding error.\n");
                exit(1);
            }

            if (++fsls > 10) {
                fflush(ogg_fp);
                fsls = 0;
            }
        }
    }

    printf("last frame\n");
    // send last frame
    if (ogg_fp) {
        theora_write_frame(ycbcr, 1);
    }
    th_encode_free(td);
    free(ycbcr[0].data);
    free(ycbcr[1].data);
    free(ycbcr[2].data);

    if (ogg_fp) {
        if (ogg_stream_flush(&ogg_os, &og)) {
            fwrite(og.header, og.header_len, 1, ogg_fp);
            fwrite(og.body, og.body_len, 1, ogg_fp);
        }
        fflush(ogg_fp);
        if (ogg_fp != stdout)
            fclose(ogg_fp);
    }

    ogg_stream_clear(&ogg_os);

    return 0;
}
