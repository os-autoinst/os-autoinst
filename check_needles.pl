#!/usr/bin/perl -w

use Mojo::Base -strict;

use File::Basename;

use needle;
use cv;

cv::init();
require tinycv;

my ($res, $needle, $img);

my $ndir = $ARGV[0] || ".";

my @jsons = glob "${ndir}/*.json";
my @pngs  = glob "${ndir}/*.png";

foreach my $json (@jsons) {
    my $bnjson = basename($json, ".json");
    $needle = needle->new($json);
    foreach my $png (@pngs) {
        my $bnpng = basename($png, ".png");
        $img = tinycv::read($png);
        $res = $img->search($needle);
        if ($res) {
            if ($bnjson ne $bnpng) {
                print "Needle ambiguity: [Needle] " . $bnjson . " - [Image] " . $bnpng . " [" . $res->{similarity} . "]\n";
            }
        }
        else {
            if ($bnjson eq $bnpng) {
                print "Needle do not match himself: [Needle] " . $bnjson . " - [Image] " . $bnpng . "\n";
            }
        }
    }
}
