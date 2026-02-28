#!/usr/bin/perl
use strict;
use warnings;
use v5.24;
use experimental qw(signatures);
use JSON::PP qw(decode_json encode_json);
use autodie;
use File::Path qw(make_path);
use File::Basename qw(dirname);
use Data::Dumper;

my ($test, $report, $dir) = @ARGV;
$test =~ s{^\./}{};

my $coverage = read_json($report);

my $by_file = $coverage->{coverage};

for my $key (sort keys %$by_file) {
    say "=== $key";
    my $lines = $by_file->{$key};
    my $jsonfile = "$dir/$key.json";
    my $filecoverage = [];
    if (-e $jsonfile) {
        $filecoverage = read_json($jsonfile);
    }
    for my $i (0 .. $#$lines) {
        my $exists = $filecoverage->[$i] ||= {};
        my $new = $lines->[$i];
        if ($new) {
            $exists->{$test} = 1;
        }
    }
    write_json($jsonfile, $filecoverage);
}


sub read_json ($file) {
    open my $fh, '<', $file;
    my $json = do { local $/; <$fh> };
    close $fh;
    return decode_json $json;
}
sub write_json ($file, $data) {
    make_path dirname $file;
    open my $fh, '>', $file;
    print $fh encode_json $data;
    close $fh;
}

