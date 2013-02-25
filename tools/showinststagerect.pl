#!/usr/bin/perl

use warnings;
use strict;

if(!@ARGV) { die "need arg";}

my $file;
my @params = qw(convert -fill none -stroke purple -pointsize 10);
my @cmd;

my $files = join(' ', @ARGV);
open(IN, "tools/inststagedetect2.pl $files 2>&1 |");

while( my $line = <IN> ) {
    print $line;

    if( $line =~ /file:\s*(\S*)/ ) {
        $file = $1;
        @cmd = @params;
    }

    if( $line =~ /^stage=(\S*)\s(\S+)\s(\d+,\d+,\d+,\d+)\s(\S+)/) {
        my ($stage, $md5, $rect, $flags) = ($1, $2, $3, $4);
        
        my ($xstart,$ystart,$xsize,$ysize) = split(/,/,$rect);
        push @cmd, '-draw', sprintf('rectangle %d,%d %d,%d', $xstart, $ystart, $xstart+$xsize, $ystart+$ysize);
        push @cmd, '-draw', sprintf("text %d,%d '%s'", $xstart+2, $ystart+10, $rect);
    }

    if( $line =~ /time=\S+/ ) {
        push @cmd, $file;

        my $outfile = substr($file,0,-3).'rect'.substr($file,-4);
        push @cmd, $outfile;

        #print join(' ', @cmd), "\n";
        print "Writing $outfile\n";
        system @cmd;
    }
}
close(IN);
