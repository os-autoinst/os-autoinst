#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "tinycv.h"

#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>

typedef Image *tinycv__Image;
typedef VNCInfo *tinycv__VNCInfo;
typedef PerlIO* InOutStream;
typedef int SysRet;

/* send_with_fd(unix_socket, message, file_descriptor_to_send)
 *
 * Send a message (buf) with a control section containing a file
 * descriptor. This allows you to transfer the 'rights' to a file descriptor
 * between processes as well as the actual FD number.
 *
 * This function does not take Perl's buffering into account. So if you plan
 * to use it on a socket then only write to that socket with syswrite,
 * POSIX::write or similar.
 *
 * See the unix(7), sendmsg(2) and cmsg(3) man pages.
 */
static SysRet clib_send_with_fd(int sk, char *buf, size_t len, int fd)
{
	struct msghdr msg = { 0 };
	struct cmsghdr *cmsg;
	struct iovec iov = {
		.iov_base = buf,
		.iov_len = len
	};
	char cmsg_buf[CMSG_ALIGN(CMSG_SPACE(sizeof(fd)))];

	msg.msg_iov = &iov;
	msg.msg_iovlen = 1;
	msg.msg_control = cmsg_buf;
	msg.msg_controllen = sizeof(cmsg_buf);

	cmsg = CMSG_FIRSTHDR(&msg);
	cmsg->cmsg_level = SOL_SOCKET;
	cmsg->cmsg_type = SCM_RIGHTS;
	cmsg->cmsg_len = CMSG_LEN(sizeof(fd));
	*((int *)CMSG_DATA(cmsg)) = fd;

	return sendmsg(sk, &msg, 0);
}

static SysRet clib_set_socket_timeout(int sockfd, time_t seconds, suseconds_t microseconds)
{
    struct timeval tv;
    tv.tv_sec = seconds;
    tv.tv_usec = microseconds;
    const auto error1 = setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, static_cast<const void *>(&tv), sizeof(tv));
    const auto error2 = setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, static_cast<const void *>(&tv), sizeof(tv));
    return error1 ? error1 : error2;
}

MODULE = tinycv     PACKAGE = tinycv

PROTOTYPES: ENABLE

SysRet
send_with_fd(InOutStream sk, char *buf, int fd);
CODE:
       RETVAL = clib_send_with_fd(PerlIO_fileno(sk), buf, strlen(buf), fd);
OUTPUT:
       RETVAL

SysRet
set_socket_timeout(int sockfd, time_t seconds)
CODE:
        RETVAL = clib_set_socket_timeout(sockfd, seconds, 0);
OUTPUT:
        RETVAL

int
default_thread_count()
CODE:
        RETVAL = opencv_default_thread_count();
OUTPUT:
        RETVAL

void
create_threads(int thread_count = -1)
CODE:
       create_opencv_threads(thread_count);

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

tinycv::Image from_ppm(SV *data)
  CODE:
    STRLEN len;
    unsigned char *buf = (unsigned char*)SvPV(data, len);
    RETVAL = image_from_ppm(buf, len);

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

void get_colour(tinycv::VNCInfo info, unsigned int index)
  PPCODE:
    const auto color = image_get_vnc_color(info, index);
    EXTEND(SP, 3);
    PUSHs(sv_2mortal(newSVnv(std::get<0>(color))));
    PUSHs(sv_2mortal(newSVnv(std::get<1>(color))));
    PUSHs(sv_2mortal(newSVnv(std::get<2>(color))));

void set_colour(tinycv::VNCInfo info, unsigned int index, unsigned red, unsigned green, unsigned blue)
   CODE:
     image_set_vnc_color(info, index, red, green, blue);

MODULE = tinycv     PACKAGE = tinycv::Image  PREFIX = Image

bool write(tinycv::Image self, const char *file)
  CODE:
    RETVAL = image_write(self, file);

  OUTPUT:
    RETVAL

SV *ppm_data(tinycv::Image self)
  CODE:
    std::vector<unsigned char> *buf = image_ppm(self);
    RETVAL = newSVpv(reinterpret_cast<const char*>(buf->data()), buf->size());

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

void map_raw_data_ast2100(tinycv::Image self, unsigned char *data, size_t len)
  CODE:
    image_map_raw_data_ast2100(self, data, len);

long map_raw_data_zrle(tinycv::Image self, long x, long y, long w, long h, tinycv::VNCInfo info, unsigned char *data, size_t len)
  CODE:
   RETVAL = image_map_raw_data_zrle(self, x, y, w, h, info, data, len);

  OUTPUT:
   RETVAL

void blend(tinycv::Image self, tinycv::Image source, long x, long y)
  CODE:
    image_blend_image(self, source, x, y);

void threshold(tinycv::Image self, int level)
  CODE:
    image_threshold(self, level);

void get_pixel(tinycv::Image self, long x, long y)
  PPCODE:
    const auto pixel = image_get_pixel(self, x, y);
    EXTEND(SP, 3);
    PUSHs(sv_2mortal(newSVnv(std::get<0>(pixel))));
    PUSHs(sv_2mortal(newSVnv(std::get<1>(pixel))));
    PUSHs(sv_2mortal(newSVnv(std::get<2>(pixel))));

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
    EXTEND(SP, SSize_t(ret.size() + 1));

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

