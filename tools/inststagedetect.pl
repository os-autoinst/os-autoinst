#!/usr/bin/perl -w
use strict;
use constant BPP=>3;
use Time::HiRes qw(gettimeofday tv_interval);
use Digest::MD5;
use ppm;

if(!@ARGV) { die "need arg";}

my %hashmap;
my %hashmapnocursor;
my %hashmapstage;
foreach my $in (@ARGV) {
open(F, "<", $in) or die $!;
local $/;
my $data=<F>;
close F;
my $md5all=Digest::MD5::md5($data);
if($hashmap{$md5all}++) {next} # skip identical copies

my $t=[gettimeofday()];
my $ppm=ppm->new($data);
my $ppm2=ppm->new($ppm);
$ppm->replacerect($ppm->{xres}-9,$ppm->{yres}-9,9,9); # mask out animated cursor
my $md5nocursor=Digest::MD5::md5_hex($ppm->{data});
#print "nocursor=".($hashmapnocursor{$md5nocursor}++)." ";

#printf("time=%.6f %i\n",tv_interval($t), $ppm->{xres});

#print ref($ppm);
#$ppm2->replacerect(200,200,100,100);
$ppm2=$ppm->copyrect(27,128,13,250);
$ppm2->replacerect(0,137,13,13); # mask out text
$ppm2->replacerect(0,215,13,13); # mask out text
# md5_hex($ppm2->{data});
my @md5;
my $md5=Digest::MD5::md5_hex($ppm2->{data});
push(@md5,$md5);
$ppm2->threshold(0x80); # black/white => drop most background
push(@md5, Digest::MD5::md5_hex($ppm2->{data}));
$hashmapstage{$md5}++;

# popup text detector
$ppm2=$ppm->copyrect(230,230, 300,100);
$ppm2->threshold(0x80); # black/white => drop most background
push(@md5, Digest::MD5::md5_hex($ppm2->{data}));

# GNOME part
$ppm2=$ppm->copyrect(0,0, 250,30);
$ppm2->threshold(0x80); # black/white => drop most background
push(@md5, Digest::MD5::md5_hex($ppm2->{data}));


print "@md5 $hashmapstage{$md5} $in\n";
#print $ppm2->toppm;
}

