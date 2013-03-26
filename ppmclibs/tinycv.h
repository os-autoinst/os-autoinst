#include <string>
#include <vector>

// opaque type to seperate perl from opencv
struct Image;
void image_destroy(Image *s);
Image *image_read(const char *filename);
bool image_write(Image *s, const char *filename);

std::vector<int> image_search(Image *s, Image *needle, int maxdiff);
std::vector<int> image_search_fuzzy(Image *s, Image *needle);

std::string image_checksum(Image *s);
Image *image_copy(Image *s);

long image_xres(Image *s);
long image_yres(Image *s);

void image_replacerect(Image *s, long x, long y, long width, long height);
Image *image_copyrect(Image *s, long x, long y, long width, long height);
void image_threshold(Image *s, int level);
std::vector<float> image_avgcolor(Image *s);
bool image_differ(Image *a, Image *b, unsigned char maxdiff);
