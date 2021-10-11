#!/usr/bin/perl
#
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use FindBin '$Bin';

use OpenQA::Test::TimeLimit '5';
use Mojo::Base -strict, -signatures;
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json);
use Test::Output qw(stderr_like);
use Test::Warnings ':report_warnings';

# ensure a consistent base for relative paths
# note: Using relative paths here so the paths in the output will always be the same.
chdir "$Bin/..";

my ($data_dir, $imgsearch_dir) = (path('t/data'), path('t/imgsearch'));
my $haystack_image_1 = $data_dir->child('other-desktop-dvd-20140904.png');    # contains KDE and GNOME logo
my $haystack_image_2 = $data_dir->child('xterm-started-20141204.png');        # contains none of the logos
my $kde_logo         = $imgsearch_dir->child('kde-logo.png');                 # KDE logo, exactly like in $haystack_image_1; expected match
my $gnome_logo       = $imgsearch_dir->child('gnome-logo-distorted.png');     # GNOME logo, slightly distorted; candidate with high similarity

my $stdout;
stderr_like { $stdout = qx{"./imgsearch" --verbose --haystack-images $haystack_image_1 $haystack_image_2 --needle-images $kde_logo $gnome_logo} }
qr/Loading needles.*Searching.*png/s, 'log via stderr';

my $actual_output   = decode_json($stdout);
my $expected_output = decode_json($imgsearch_dir->child('expected-output.json')->slurp);
my @output          = ($actual_output, $expected_output);

my ($actual_similarity_gnome, $expected_similarity_gnome)
  = map { delete $_->{'t/data/other-desktop-dvd-20140904.png'}->{candidates}->[0]->{area}->[0]->{similarity} } @output;
my ($actual_similarity_kde, $expected_similarity_kde)
  = map { delete $_->{'t/data/other-desktop-dvd-20140904.png'}->{match}->{area}->[0]->{similarity} } @output;
my ($actual_error_gnome, $expected_error_gnome)
  = map { delete $_->{'t/data/other-desktop-dvd-20140904.png'}->{candidates}->[0]->{error} } @output;
my ($actual_error_kde, $expected_error_kde)
  = map { delete $_->{'t/data/other-desktop-dvd-20140904.png'}->{match}->{error} } @output;

sub is_similar ($actual, $expected, $test) { cmp_ok abs($actual - $expected), '<', '0.05', $test }

is_similar $actual_similarity_gnome, $expected_similarity_gnome, 'slightly distorted GNOME logo is matching candidate with high similarity';
is_similar $actual_similarity_kde,   $expected_similarity_kde,   'exact KDE logo is best match with very high similarity';
is_similar $actual_error_gnome,      $expected_error_gnome,      'snall error for candidate with high similarity';
is_similar $actual_error_kde,        $expected_error_kde,        'very small error for best match';
is_deeply $actual_output, $expected_output, 'other search results are as expected as well';

done_testing();
