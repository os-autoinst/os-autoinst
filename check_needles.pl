#!/usr/bin/perl -w

use Mojo::Base -strict, -signatures;
use File::Basename;
use Getopt::Long;
use needle;
use cv;

cv::init();
require tinycv;

Getopt::Long::Configure("no_ignore_case");

my %options;

sub usage ($r) {
    eval { require Pod::Usage; Pod::Usage::pod2usage($r) };
    die "cannot display help, install perl(Pod::Usage)\n" if $@;    # uncoverable statement
}

GetOptions(\%options, 'help|h|?') or usage(1);
usage(0) if $options{help};

my ($res, $needle, $img);
my $ndir = $ARGV[0] || ".";
my @jsons = glob "${ndir}/*.json";
my @pngs = glob "${ndir}/*.png";

foreach my $json (@jsons) {
    my $bnjson = basename($json, ".json");
    $needle = needle->new($json);
    foreach my $png (@pngs) {
        my $bnpng = basename($png, ".png");
        $img = tinycv::read($png);
        $res = $img->search($needle);
        if ($res) {
            print "Needle ambiguity: [Needle] " . $bnjson . " - [Image] " . $bnpng . " [" . $res->{similarity} . "]\n" if $bnjson ne $bnpng;
        }
        else {
            print "Needle does not match itself: [Needle] " . $bnjson . " - [Image] " . $bnpng . "\n" if $bnjson eq $bnpng;
        }
    }
}
