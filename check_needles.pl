#!/usr/bin/perl -w

use strict;

use File::Basename;

use needle;
use cv;

my ($res, $needle, $img);

my $ndir = $ARGV[0] || ".";

my @jsons = <${ndir}/*.json>;
my @pngs = <${ndir}/*.png>;


foreach my $json (@jsons) {
    $needle = needle->new($json);
    foreach my $png (@pngs) {
	$img = tinycv::read($png);
	$res = $img->search($needle);
	if ($res) {
	    if (basename($json) ne basename($png)) {
		print "Needle ambiguity: [Needle] " . basename($json) . " - [Image] " . basename($png) . " [" . $res->{"similarity"} . "]\n";
	    }
	} else {
	    if (basename($json) eq basename($png)) {
		print "Needle do not match himself: [Needle] " . basename($json) . " - [Image] " . basename($png) . "\n";
	    }
	}
    }
}
