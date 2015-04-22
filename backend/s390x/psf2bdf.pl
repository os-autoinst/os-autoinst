#!/usr/bin/env perl
# Convert PC Screen Font (PSF) font to Glyph Bitmap Distribution Format (BDF).
# klg, Mar 2015
use strict;

use constant {
  PSF1_MODE512 => 0x01,
  PSF1_MODEHASTAB => 0x02,
  PSF2_HAS_UNICODE_TABLE => 0x01,
};

push @ARGV, '-' unless scalar @ARGV;

for (@ARGV) {
  my $fn = /^-$/ ? 'stdin' : $_;
  eval {

    my ($length, $width, $height);
    my (@glyphs, @unicode);

    open my $fh, $_ or die $!;
    binmode $fh;
    read $fh, $_, 4 or die $!;

    if (0x0436 == unpack 'v') { # psf1
      my ($mode, $size) = unpack 'x2CC';
      $length = $mode & PSF1_MODE512 ? 512 : 256;
      $height = $size;
      $width = 8;
      read $fh, $_, $length * $size;
      @glyphs = unpack "(a$size)$length";
      if ($mode & PSF1_MODEHASTAB) {
        for my $i (0 .. $length-1) {
          my ($u, @u) = 0;
          do {
            read $fh, $_, 2;
            $u = unpack 'v';
            push @u, $u if $u < 0xFFFE;
          } while $u < 0xFFFE;
          while ($u != 0xFFFF) {
            read $fh, $_, 2;
            $u = unpack 'v';
            warn 'Unicode sequence ignored' if $u == 0xFFFE;
          }
          $unicode[$i] = [@u];
        }
      }
    } elsif (0x864ab572 == unpack 'V') { # psf2
      read $fh, $_, 28 or die $!;
      (my ($ver, $hlen, $flg), $length,
        my $size, $height, $width) = unpack 'V7';
      die "Unknown version $ver\n" unless $ver == 0;
      warn "Unexpected glyph size $size bytes for ${width}×$height px\n"
        unless $size == $height * int(($width + 7) / 8);
      read $fh, $_, $hlen - 32; # skip to data
      read $fh, $_, $length * $size;
      @glyphs = unpack "(a$size)$length";
      if ($flg & PSF2_HAS_UNICODE_TABLE) {
        my $buf = do { local $/; <$fh>; };
        for my $i (0 .. $length-1) {
          $buf =~ m/\G([^\xfe\xff]*+)(?:\xfe[^\xfe\xff]++)*\xff/sg;
          utf8::decode(my $str = $1);
          $unicode[$i] = [map ord, split //, $str];
        }
      }
    } else {
      die "Bad format\n";
    }


    print "STARTFONT 2.1\n";
    printf "FONT %s\n", '-psf-';
    printf "SIZE %u 72 72\n", $height;
    printf "FONTBOUNDINGBOX %u %u 0 0\n", $width, $height;

    printf "STARTPROPERTIES %u\n", 6 + 2 * !!@unicode;
    printf "PIXEL_SIZE %u\n", $height;
    printf "POINT_SIZE %u\n", 10 * $height;
    printf "FONT_ASCENT %u\n", $height;
    print "FONT_DESCENT 0\n";
    print "RESOLUTION_X 72\n";
    print "RESOLUTION_Y 72\n";
    if (@unicode) {
      print "CHARSET_REGISTRY \"ISO10646\"\n";
      print "CHARSET_ENCODING \"1\"\n";
    }
    print "ENDPROPERTIES\n";

    printf "CHARS %u\n", $length;

    for my $i (0 .. $length-1) {
      printf "STARTCHAR psf%03x\n", $i;
      if (@unicode && @{$unicode[$i]}) {
        printf "ENCODING %u\n", $unicode[$i][0];
      } else {
        printf "ENCODING -1 %u\n", $i;
      }
      printf "SWIDTH %u 0\n", $width * 1000 / $height;
      printf "DWIDTH %u 0\n", $width;
      printf "BBX %u %u 0 0\n", $width, $height;
      my $bw = (($width + 7) & ~7) >> 3;
      printf "BITMAP\n%s\n", join "\n", map unpack('H*', $_), unpack "(a$bw)*", $glyphs[$i];
      printf "ENDCHAR\n";
    }

    print "ENDFONT\n";

  };
  warn "$fn: $@" if $@;
  last;
}
