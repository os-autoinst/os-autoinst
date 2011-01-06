#!/usr/bin/perl -w
use strict;
use constant BPP=>3;
use Time::HiRes qw(gettimeofday tv_interval);
use Digest::MD5;
use bmwqemu;

if(!@ARGV) { die "need arg";}
open(bmwqemu::LOG, ">/dev/null");

set_hash_rects(
	[30,30,100,100], # where most applications pop up
	[630,30,100,100], # where some applications pop up
	[0,579,100,10 ], # bottom line (KDE/GNOME bar)
	[412,284,200,200], # center of 1024x768
	);

my %hashmap;
foreach my $in (@ARGV) {
	open(F, "<", $in) or die $!;
	local $/;
	my $data=<F>;
	close F;
	my $md5all=Digest::MD5::md5($data);
	if($hashmap{$md5all}++) {next} # skip identical copies

	my $t=[gettimeofday()];
	print "file: $in\n";
	bmwqemu::inststagedetect(\$data);
	printf("time=%.6f\n",tv_interval($t));
}

