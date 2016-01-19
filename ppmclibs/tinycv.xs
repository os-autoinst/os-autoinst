#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "tinycv.h"

typedef Image *tinycv__Image;
typedef VNCInfo *tinycv__VNCInfo;

MODULE = tinycv     PACKAGE = tinycv

PROTOTYPES: ENABLE

tinycv::Image new(long width, long height)
  CODE:
    RETVAL = image_new(width, height);

  OUTPUT:
    RETVAL

tinycv::Image read(const char *file)
  CODE:
    RETVAL = image_read(file);

  OUTPUT:
    RETVAL

tinycv::VNCInfo new_vncinfo(bool do_endian_conversion, bool true_color, unsigned int bytes_per_pixel, unsigned int red_mask, unsigned int red_shift, unsigned int green_mask, unsigned int green_shift, unsigned int blue_mask, unsigned int blue_shift)
   CODE:
     RETVAL = image_vncinfo(do_endian_conversion,
			    true_color,
			    bytes_per_pixel,
			    red_mask, red_shift,
			    green_mask, green_shift,
			    blue_mask, blue_shift);

   OUTPUT:
     RETVAL

void set_colour(tinycv::VNCInfo info, unsigned int index, unsigned red, unsigned green, unsigned blue)
   CODE:
     image_set_vnc_color(info, index, red, green, blue);
     
MODULE = tinycv     PACKAGE = tinycv::Image  PREFIX = Image

bool write(tinycv::Image self, const char *file)
  CODE:
    RETVAL = image_write(self, file);

  OUTPUT:
    RETVAL

tinycv::Image copy(tinycv::Image self)
  CODE:
    RETVAL = image_copy(self);

  OUTPUT:
    RETVAL

long xres(tinycv::Image self)
  CODE:
    RETVAL = image_xres(self);

  OUTPUT:
    RETVAL

long yres(tinycv::Image self)
  CODE:
    RETVAL = image_yres(self);

  OUTPUT:
    RETVAL

void replacerect(tinycv::Image self, long x, long y, long width, long height)
  CODE:
    image_replacerect(self, x, y, width, height);

tinycv::Image copyrect(tinycv::Image self, long x, long y, long width, long height)
  CODE:
    RETVAL = image_copyrect(self, x, y, width, height);

  OUTPUT:
    RETVAL

void map_raw_data(tinycv::Image self, unsigned char *data, unsigned int x, unsigned int y, unsigned int w, unsigned h, tinycv::VNCInfo info)
  CODE:
    image_map_raw_data(self, data, x, y, w, h, info);

void map_raw_data_rgb555(tinycv::Image self, unsigned char *data)
  CODE:
    image_map_raw_data_rgb555(self, data);

long map_raw_data_zrle(tinycv::Image self, long x, long y, long w, long h, tinycv::VNCInfo info, unsigned char *data, size_t len)
  CODE:
   RETVAL = image_map_raw_data_zlre(self, x, y, w, h, info, data, len);

  OUTPUT:
   RETVAL
   
void blend(tinycv::Image self, tinycv::Image source, long x, long y)
  CODE:
    image_blend_image(self, source, x, y);

void threshold(tinycv::Image self, int level)
  CODE:
    image_threshold(self, level);

void avgcolor(tinycv::Image self)
  PPCODE:
    std::vector<float> res = image_avgcolor(self);
    EXTEND(SP, 3);
    PUSHs(sv_2mortal(newSVnv(res[0])));
    PUSHs(sv_2mortal(newSVnv(res[1])));
    PUSHs(sv_2mortal(newSVnv(res[2])));
 
void search_needle(tinycv::Image self, tinycv::Image needle, long x, long y, long width, long height, long margin)
  PPCODE:
    double similarity = 0;
    std::vector<int> ret = image_search(self, needle, x, y, width, height, margin, similarity);
    EXTEND(SP, ret.size() + 1);

    PUSHs(sv_2mortal(newSVnv(similarity)));

    std::vector<int>::const_iterator it = ret.begin();
    for (; it != ret.end(); ++it) { 
      PUSHs(sv_2mortal(newSViv(*it)));
    }


tinycv::Image scale(tinycv::Image self, long width, long height)
  CODE:
    RETVAL = image_scale(self, width, height);

  OUTPUT:
    RETVAL

double similarity(tinycv::Image self, tinycv::Image other)
  CODE:
    RETVAL = image_similarity(self, other);
   
  OUTPUT:
    RETVAL

tinycv::Image absdiff(tinycv::Image self, tinycv::Image other)
  CODE:
    RETVAL = image_absdiff(self, other);

  OUTPUT:
    RETVAL

void DESTROY(tinycv::Image self)
  CODE:
    image_destroy(self);

