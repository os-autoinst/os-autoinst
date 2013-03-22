#!/usr/bin/perl -w
use strict;
use constant BPP=>3;
use Time::HiRes qw(gettimeofday tv_interval);
use Digest::MD5;
use cv;

if(!@ARGV) { die "need arg";}

my %hashmap;
my %hashmapnocursor;
my %hashmapstage;
foreach my $in (@ARGV) {

  my $ppm = tinycv::read($in) or die $!;
  my $md5all=$ppm->checksum();

  if($hashmap{$md5all}++) {next} # skip identical copies

  my $t=[gettimeofday()];
  my $ppm2=$ppm->copy();
  $ppm->replacerect($ppm->xres()-9,$ppm->yres()-9,9,9); # mask out animated cursor
  my $md5nocursor=$ppm->checksum();
  #print "nocursor=".($hashmapnocursor{$md5nocursor}++)." ";

  #printf("time=%.6f %i\n",tv_interval($t), $ppm->{xres});

  #print ref($ppm);
  #$ppm2->replacerect(200,200,100,100);
  $ppm2=$ppm->copyrect(27,128,13,200);
  $ppm2->replacerect(0,137,13,15); # mask out text
  # md5_hex($ppm2->{data});
  my @md5;
  my $md5=$ppm2->checksum();
  push(@md5,$md5);
  $ppm2->threshold(0x80); # black/white => drop most background
  push(@md5, $ppm2->checksum());
  $hashmapstage{$md5}++;

  # popup text detector
  $ppm2=$ppm->copyrect(230,230, 300,100);
  $ppm2->threshold(0x80); # black/white => drop most background
  push(@md5, $ppm2->checksum());

  # GNOME part
  $ppm2=$ppm->copyrect(0,0, 250,30);
  $ppm2->threshold(0x80); # black/white => drop most background
  push(@md5, $ppm2->checksum());


  print "@md5 $hashmapstage{$md5} $in\n";
  #print $ppm2->toppm;
}
