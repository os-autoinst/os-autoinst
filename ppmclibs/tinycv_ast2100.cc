// Copyright 2012-2016 SUSE LLC
// SPDX-License-Identifier: GPL-2.0-or-later

#include "opencv2/core/core.hpp"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define DECBITS 10

struct dec_hufftbl {
    int maxcode[17];
    int valptr[16];
    unsigned char vals[256];
    unsigned int llvals[1 << DECBITS];
};

static void dec_makehuff(struct dec_hufftbl* hu, unsigned char* hufflen)
{
    unsigned char* huffvals = hufflen + 16;
    int code, k, i, j, d, x, c, v;
    for (i = 0; i < (1 << DECBITS); i++)
        hu->llvals[i] = 0;
    code = 0;
    k = 0;
    for (i = 0; i < 16; i++, code <<= 1) /* sizes */
    {
        hu->valptr[i] = k;
        for (j = 0; j < hufflen[i]; j++) {
            hu->vals[k] = *huffvals++;
            if (i < DECBITS) {
                c = code << (DECBITS - 1 - i);
                v = hu->vals[k] & 0x0f; /* size */
                for (d = 1 << (DECBITS - 1 - i); --d >= 0;) {
                    if (v + i < DECBITS) /* both fit in table */
                    {
                        x = d >> (DECBITS - 1 - v - i);
                        if (v && x < (1 << (v - 1)))
                            x += (-1 << v) + 1;
                        x = x << 16 | (hu->vals[k] & 0xf0) << 4 | (DECBITS - (i + 1 + v)) | 128;
                    } else
                        x = v << 16 | (hu->vals[k] & 0xf0) << 4 | (DECBITS - (i + 1));
                    hu->llvals[c | d] = x;
                }
            }
            code++;
            k++;
        }
        hu->maxcode[i] = code;
    }
    hu->maxcode[16] = 0x20000; /* always terminate decode */
}

#define LEBI_DCL int le, bi
#define LEBI_GET(in) (le = in->left, bi = in->bits)
#define LEBI_PUT(in) (in->left = le, in->bits = bi)

#define GETBITS(in, n)                                                       \
    ((le < (n) ? le = fillbits(in, le, bi), bi = in->bits : 0), (le -= (n)), \
        bi >> le & ((1 << (n)) - 1))

#define UNGETBITS(in, n) (le += (n))

struct in {
    const unsigned char* p;
    unsigned int bits;
    int left;
    unsigned int po;
};

static int fillbits(struct in* in, int le, unsigned int bi)
{
    while (le <= 24) {
        bi = bi << 8 | in->p[in->po++ ^ 3];
        le += 8;
    }
    in->bits = bi; /* tmp... 2 return values needed */
    return le;
}

static int dec_rec2(struct in* in, struct dec_hufftbl* hu, int* runp, int c,
    int i)
{
    LEBI_DCL;

    LEBI_GET(in);
    if (i) {
        UNGETBITS(in, i & 127);
        *runp = i >> 8 & 15;
        i >>= 16;
    } else {
        for (i = DECBITS; (c = c << 1 | GETBITS(in, 1)) >= hu->maxcode[i]; i++)
            ;
        if (i >= 16)
            return 0;
        i = hu->vals[hu->valptr[i] + c - hu->maxcode[i - 1] * 2];
        *runp = i >> 4;
        i &= 15;
    }
    if (i == 0) /* sigh, 0xf0 is 11 bit */
    {
        LEBI_PUT(in);
        return 0;
    }
    /* receive part */
    c = GETBITS(in, i);
    if (c < (1 << (i - 1)))
        c += (-1 << i) + 1;
    LEBI_PUT(in);
    return c;
}

#define DEC_REC(in, hu, r, i)                                        \
    (r = GETBITS(in, DECBITS), i = hu->llvals[r],                    \
        i & 128 ? (UNGETBITS(in, i & 127), r = i >> 8 & 15, i >> 16) \
                : (LEBI_PUT(in), i = dec_rec2(in, hu, &r, r, i), LEBI_GET(in), i))

#define PREC float

#define ONE ((PREC)1.)
#define S2 ((PREC)0.382683432)
#define C2 ((PREC)0.923879532)
#define C4 ((PREC)0.707106781)

#define S22 ((PREC)(2 * S2))
#define C22 ((PREC)(2 * C2))
#define IC4 ((PREC)(1 / C4))

#define C3IC1 ((PREC)0.847759065) /* c3/c1 */
#define C5IC1 ((PREC)0.566454497) /* c5/c1 */
#define C7IC1 ((PREC)0.198912367) /* c7/c1 */

#define XPP(a, b) (t = a + b, b = a - b, a = t)
#define XMP(a, b) (t = a - b, b = a + b, a = t)
#define XPM(a, b) (t = a + b, b = b - a, a = t)

#define ROT(a, b, s, c) \
    (t = (a + b) * s, a = (c - s) * a + t, b = (c + s) * b - t)

#define IDCT                                                                 \
    (XPP(t0, t1), XMP(t2, t3), t2 = t2 * IC4 - t3, XPP(t0, t3), XPP(t1, t2), \
        XMP(t4, t7), XPP(t5, t6), XMP(t5, t7), t5 = t5 * IC4,                \
        ROT(t4, t6, S22, C22), t6 -= t7, t5 -= t6, t4 -= t5, XPP(t0, t7),    \
        XPP(t1, t6), XPP(t2, t5), XPP(t3, t4))

static unsigned char zig2[64] = {
    0, 2, 3, 9, 10, 20, 21, 35, 14, 16, 25, 31, 39, 46, 50, 57,
    5, 7, 12, 18, 23, 33, 37, 48, 27, 29, 41, 44, 52, 55, 59, 62,
    15, 26, 30, 40, 45, 51, 56, 58, 1, 4, 8, 11, 19, 22, 34, 36,
    28, 42, 43, 53, 54, 60, 61, 63, 6, 13, 17, 24, 32, 38, 47, 49
};

static void idct(int* in, int* out, PREC* quant, int max)
{
    PREC t0, t1, t2, t3, t4, t5, t6, t7, t;
    PREC tmp[64], *tmpp;
    int i, j;
    unsigned char* zig2p;

    if (max == 1) {
        t0 = in[0] * quant[0];
        for (i = 0; i < 64; i++)
            out[i] = t0;
        return;
    }
    zig2p = zig2;
    tmpp = tmp;
    for (i = 0; i < 8; i++) {
        j = *zig2p++;
        t0 = in[j] * quant[j];
        j = *zig2p++;
        t5 = in[j] * quant[j];
        j = *zig2p++;
        t2 = in[j] * quant[j];
        j = *zig2p++;
        t7 = in[j] * quant[j];
        j = *zig2p++;
        t1 = in[j] * quant[j];
        j = *zig2p++;
        t4 = in[j] * quant[j];
        j = *zig2p++;
        t3 = in[j] * quant[j];
        j = *zig2p++;
        t6 = in[j] * quant[j];
        IDCT;
        tmpp[0 * 8] = t0;
        tmpp[1 * 8] = t1;
        tmpp[2 * 8] = t2;
        tmpp[3 * 8] = t3;
        tmpp[4 * 8] = t4;
        tmpp[5 * 8] = t5;
        tmpp[6 * 8] = t6;
        tmpp[7 * 8] = t7;
        tmpp++;
    }
    for (i = 0; i < 8; i++) {
        t0 = tmp[8 * i + 0];
        t1 = tmp[8 * i + 1];
        t2 = tmp[8 * i + 2];
        t3 = tmp[8 * i + 3];
        t4 = tmp[8 * i + 4];
        t5 = tmp[8 * i + 5];
        t6 = tmp[8 * i + 6];
        t7 = tmp[8 * i + 7];
        IDCT;
        out[8 * i + 0] = t0;
        out[8 * i + 1] = t1;
        out[8 * i + 2] = t2;
        out[8 * i + 3] = t3;
        out[8 * i + 4] = t4;
        out[8 * i + 5] = t5;
        out[8 * i + 6] = t6;
        out[8 * i + 7] = t7;
    }
}

static unsigned char zig[64] = {
    0, 1, 5, 6, 14, 15, 27, 28, 2, 4, 7, 13, 16, 26, 29, 42,
    3, 8, 12, 17, 25, 30, 41, 43, 9, 11, 18, 24, 31, 40, 44, 53,
    10, 19, 23, 32, 39, 45, 52, 54, 20, 22, 33, 38, 46, 51, 55, 60,
    21, 34, 37, 47, 50, 56, 59, 61, 35, 36, 48, 49, 57, 58, 62, 63
};

static PREC aaidct[8] = { 0.3535533906, 0.4903926402, 0.4619397663,
    0.4157348062, 0.3535533906, 0.2777851165,
    0.1913417162, 0.0975451610 };

/* huffman tables from the jpeg standard*/
static unsigned char hufftbl_dc_y[] = {
    0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03,
    0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b
};
static unsigned char hufftbl_dc_uv[] = {
    0x00, 0x03, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
    0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03,
    0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b
};

static unsigned char hufftbl_ac_y[] = {
    0x00, 0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04,
    0x00, 0x00, 0x01, 0x7d, 0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12,
    0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32,
    0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0,
    0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a,
    0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
    0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54, 0x55,
    0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
    0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85,
    0x86, 0x87, 0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98,
    0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2,
    0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5,
    0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8,
    0xd9, 0xda, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea,
    0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa
};

static unsigned char hufftbl_ac_uv[] = {
    0x00, 0x02, 0x01, 0x02, 0x04, 0x04, 0x03, 0x04, 0x07, 0x05, 0x04, 0x04,
    0x00, 0x01, 0x02, 0x77, 0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21,
    0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32, 0x81,
    0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0,
    0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34, 0xe1, 0x25, 0xf1, 0x17,
    0x18, 0x19, 0x1a, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38,
    0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54,
    0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
    0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82, 0x83,
    0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96,
    0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9,
    0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3,
    0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6,
    0xd7, 0xd8, 0xd9, 0xda, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9,
    0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa
};

/* quantisation table for high quality */
static unsigned char quant_y[64] = {
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
    0x02, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x02, 0x02, 0x01, 0x01,
    0x01, 0x01, 0x01, 0x02, 0x03, 0x03, 0x02, 0x01, 0x01, 0x01, 0x02,
    0x02, 0x03, 0x03, 0x02, 0x01, 0x02, 0x02, 0x02, 0x03, 0x03, 0x03,
    0x03, 0x02, 0x02, 0x02, 0x03, 0x03, 0x03, 0x03, 0x03
};

/* quantisation table for high quality */
static unsigned char quant_uv[64] = {
    0x01, 0x01, 0x01, 0x02, 0x06, 0x06, 0x06, 0x06, 0x01, 0x01, 0x01,
    0x04, 0x06, 0x06, 0x06, 0x06, 0x01, 0x01, 0x03, 0x06, 0x06, 0x06,
    0x06, 0x06, 0x02, 0x04, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06,
    0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06,
    0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06,
    0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06
};

static void idctqtab(unsigned char* qin, PREC* qout, double scale)
{
    int i, j;

    for (i = 0; i < 8; i++)
        for (j = 0; j < 8; j++)
            qout[zig[i * 8 + j]] = qin[i * 8 + j] * aaidct[i] * aaidct[j] * scale;
}

static void setpalette(int* co, int cy, int cb, int cr)
{
    co[0] = cy - 128;
    co[1] = cb - 128;
    co[2] = cr - 128;
}

static inline int clamp(int x) { return x > 255 ? 255 : x < 0 ? 0 : x; }

void decode_ast2100(cv::Mat* pic, const unsigned char* data, size_t datal)
{
    struct in ins, *in;
    int mcux = 0, mcuy = 0;
    int odc[3];
    int out[64 * 3];
    LEBI_DCL;
    int m, x, y;
    int i, r, t;
    PREC qt[3][64];
    struct dec_hufftbl hu_dc_y;
    struct dec_hufftbl hu_ac_y;
    struct dec_hufftbl hu_dc_uv;
    struct dec_hufftbl hu_ac_uv;
    struct dec_hufftbl* hu;
    unsigned char lookup[4];
    int palette[4 * 3];

    int width = pic->cols;
    int height = pic->rows;

    lookup[0] = 0;
    lookup[1] = 1;
    lookup[2] = 2;
    lookup[3] = 3;
    setpalette(palette + 0 * 3, 0x00, 0x80, 0x80);
    setpalette(palette + 1 * 3, 0xff, 0x80, 0x80);
    setpalette(palette + 2 * 3, 0x80, 0x80, 0x80);
    setpalette(palette + 3 * 3, 0xc0, 0x80, 0x80);

    if (datal & 3) {
        fprintf(stderr, "bad data len (not divisible by 4): %zu\n", datal);
        exit(1);
    }
    memset(&ins, 0, sizeof(ins));
    in = &ins;

    dec_makehuff(&hu_dc_y, hufftbl_dc_y);
    dec_makehuff(&hu_ac_y, hufftbl_ac_y);
    dec_makehuff(&hu_dc_uv, hufftbl_dc_uv);
    dec_makehuff(&hu_ac_uv, hufftbl_ac_uv);

    idctqtab(quant_y, qt[0], 1.);
    idctqtab(quant_uv, qt[1], 1.);
    idctqtab(quant_uv, qt[2], 1.);

    int subsamp = data[2] << 8 | data[3];
    if (subsamp != 444 || data[0] != 11 || data[1] != 11) {
        fprintf(stderr, "unsupported quality settings: subsamp %d quant:%d+%d\n",
            subsamp, data[0], data[1]);
        return;
    }

    in->p = data + 4;
    odc[0] = odc[1] = odc[2] = 0;
    LEBI_GET(in);
    for (;;) {
        int ctrl = GETBITS(in, 4);
        if (ctrl == 9)
            break;
        if (ctrl == 1 || ctrl == 2 || ctrl == 3 || ctrl == 10 || ctrl == 11) {
            fprintf(stderr, "unknown ctrl %d\n", ctrl);
            exit(0);
        }
        if (ctrl >= 8) {
            mcux = GETBITS(in, 8);
            mcuy = GETBITS(in, 8);
        }
        ctrl &= 7;
        if (ctrl == 0 || ctrl == 4) {
            if (ctrl == 4) {
                fprintf(stderr, "advanced quant table not supported\n");
                exit(0);
            }
            for (m = 0; m < 3; m++) {
                int *dct, mydct[64];

                memset(mydct, 0, sizeof(mydct));
                dct = mydct;

                hu = m == 0 ? &hu_dc_y : &hu_dc_uv;
                t = DEC_REC(in, hu, r, t);
                odc[m] += t;
                *dct++ = odc[m];

                hu = m == 0 ? &hu_ac_y : &hu_ac_uv;
                for (i = 63; i > 0;) {
                    t = DEC_REC(in, hu, r, t);
                    if (t == 0 && r == 0)
                        break;
                    dct += r;
                    *dct++ = t;
                    i -= r + 1;
                }
                idct(mydct, out + 64 * m, qt[m], 64 - i);
            }
        } else {
            ctrl -= 5;
            for (i = 0; i < (1 << ctrl); i++) {
                int set = GETBITS(in, 1);
                int idx = GETBITS(in, 2);
                if (set) {
                    int cy = GETBITS(in, 8);
                    int cb = GETBITS(in, 8);
                    int cr = GETBITS(in, 8);
                    setpalette(palette + 3 * idx, cy, cb, cr);
                }
                lookup[i] = idx;
            }
            if (ctrl == 0) {
                int idx = lookup[0];
                for (i = 0; i < 64; i++) {
                    out[i + 0 * 64] = palette[3 * idx + 0];
                    out[i + 1 * 64] = palette[3 * idx + 1];
                    out[i + 2 * 64] = palette[3 * idx + 2];
                }
            } else {
                for (i = 0; i < 64; i++) {
                    int idx = lookup[GETBITS(in, ctrl)];
                    out[i + 0 * 64] = palette[3 * idx + 0];
                    out[i + 1 * 64] = palette[3 * idx + 1];
                    out[i + 2 * 64] = palette[3 * idx + 2];
                }
            }
        }
        for (y = 0; y < 8; y++)
            for (x = 0; x < 8; x++) {
                int cy, cb, cr, cg;
                cy = out[0 * 64 + y * 8 + x];
                cb = out[1 * 64 + y * 8 + x];
                cr = out[2 * 64 + y * 8 + x];
                cy += 128;
                /* ITU-R BT.601 YCbCr -> RGB conversion */
                cy = 255. / 219. * (cy - 16);
                cg = cy - (255. / 112. * 0.886 * 0.114 / .587) * cb - (255. / 112. * 0.701 * 0.299 / 0.587) * cr;
                cr = cy + (255. / 112. * 0.701) * cr;
                cb = cy + (255. / 112. * 0.886) * cb;
                if (mcux * 8 + x < width && mcuy * 8 + y < height) {
                    int ty = mcuy * 8 + y;
                    int tx = mcux * 8 + x;
                    pic->at<cv::Vec3b>(ty, tx)[0] = clamp(cb);
                    pic->at<cv::Vec3b>(ty, tx)[1] = clamp(cg);
                    pic->at<cv::Vec3b>(ty, tx)[2] = clamp(cr);
                }
            }
        mcux++;
        if (mcux * 8 >= width) {
            mcux = 0;
            mcuy++;
        }
        if (mcuy * 8 >= height)
            mcuy = 0;
    }
}
