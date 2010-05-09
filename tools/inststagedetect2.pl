#!/usr/bin/perl -w
use strict;
use constant BPP=>3;
use Time::HiRes qw(gettimeofday tv_interval);
use Digest::MD5;
use bmwqemu;

if(!@ARGV) { die "need arg";}
open(bmwqemu::LOG, ">/dev/null");

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

