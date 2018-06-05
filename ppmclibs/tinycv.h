// Copyright © 2012-2016 SUSE LLC
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, see <http://www.gnu.org/licenses/>.

#include <string>
#include <vector>

// opaque type to seperate perl from opencv
struct Image;
void image_destroy(Image *s);
Image *image_new(long width, long height);
Image *image_read(const char *filename);
bool image_write(const Image* const s, const char* filename);
// returns copy to static buffer
std::vector<unsigned char> *image_ppm(Image *s);
Image *image_from_ppm(const unsigned char *data, size_t len);

std::vector<int> image_search(Image *s, Image *needle, long x, long y, long width, long height, long margin, double &similarity);
// std::vector<int> image_search_fuzzy(Image *s, Image *needle);

Image *image_copy(Image *s);

long image_xres(Image *s);
long image_yres(Image *s);

void image_replacerect(Image *s, long x, long y, long width, long height);
Image *image_copyrect(Image *s, long x, long y, long width, long height);
void image_threshold(Image *s, int level);
std::vector<float> image_avgcolor(Image *s);
bool image_differ(Image *a, Image *b, unsigned char maxdiff);

Image *image_scale(Image *a, int width, int height);
double image_similarity(Image *a, Image *b);

Image *image_absdiff(Image *a, Image*b);

class VNCInfo;

VNCInfo *image_vncinfo(bool do_endian_conversion,
		       bool true_color,
		       unsigned int bytes_per_pixel,
		       unsigned int red_mask,   unsigned int red_shift,
		       unsigned int green_mask, unsigned int green_shift,
		       unsigned int blue_mask,  unsigned int blue_shift);
void image_set_vnc_color(VNCInfo *info, unsigned int index, unsigned int red, unsigned int green, unsigned int blue);

// this is for VNC support - RAW encoding
void image_map_raw_data(Image *a, const unsigned char *data, unsigned int x, unsigned int y, unsigned int width, unsigned int height, VNCInfo *info);

// this is for IPMI Supermicro X9 support - RGB555 is 16bits, the rest is like above
void image_map_raw_data_rgb555(Image *a, const unsigned char *data);
// this is for IPMI Supermicro X10 support - ast2100 (don't ask)
void image_map_raw_data_ast2100(Image *a, const unsigned char *data, size_t len);

// ZRLE encoding for VNC
long image_map_raw_data_zrle(Image* a, long x, long y, long w, long h,
			     VNCInfo *info,
			     unsigned char *data,
			     size_t len);

// copy the s image into a at x,y
void image_blend_image(Image *a, Image *s, long x, long y);
