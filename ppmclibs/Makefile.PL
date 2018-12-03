use strict;
use warnings;

use ExtUtils::MakeMaker;

my $opencv_libs = '-lopencv_core -lopencv_imgcodecs';
$opencv_libs =~ s,/usr/lib64/lib(\S+)\.so,-l\1,g;

WriteMakefile(
  NAME => 'tinycv',
  VERSION_FROM => 'tinycv.pm',
  LIBS => [$opencv_libs],
  DEFINE => '-Wall',
  INC => `pkg-config --cflags opencv`,
  CC => 'g++',
  LD => 'g++',
  XSOPT => '-C++',
  OBJECT => '$(O_FILES)',
);
