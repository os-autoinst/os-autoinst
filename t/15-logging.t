#!/usr/bin/perl

# Copyright 2017-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Test::Warnings ':report_warnings';
use Mojo::Base -strict, -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Term::ANSIColor qw(colorstrip);
use Test::Output qw(stderr_from);
use Mojo::File qw(path tempfile);
use Data::Dumper;
use log;
use bmwqemu ();


sub output_once () {
    log::diag('Via diag function');
    log::fctres('Via fctres function');
    log::fctinfo('Via fctinfo function');
    log::fctwarn('Via fctwarn function');
    log::modstate('Via modstate function');
}

subtest 'Logging to STDERR' => sub {
    my $output = stderr_from(\&output_once);
    $output .= stderr_from { bmwqemu::diag('Via diag function') };
    $output .= stderr_from { bmwqemu::fctres('Via fctres function') };
    $output .= stderr_from { bmwqemu::fctinfo('Via fctinfo function') };
    $output .= stderr_from { bmwqemu::fctwarn('Via fctwarn function') };
    $output .= stderr_from { bmwqemu::modstate('Via modstate function') };
    note $output;
    my @matches = ($output =~ m/Via .*? function/gm);
    ok(@matches == 10, 'All messages logged to STDERR');
    my $i = 0;
    ok($matches[$i++] =~ /$_/, "Logging $_ match!") for ('diag', 'fctres', 'fctinfo', 'fctwarn', 'modstate');
};

subtest 'Color output can be disabled' => sub {
    delete $ENV{ANSI_COLORS_DISABLED};
    my $out = stderr_from { bmwqemu::fctwarn('with color') };
    isnt($out, colorstrip($out), 'logs use colors');
    $ENV{ANSI_COLORS_DISABLED} = 1;
    $out = stderr_from { bmwqemu::fctwarn('no colors') };
    is($out, colorstrip($out), 'no colors in logs');
};

subtest 'Logging to file' => sub {
    my $log_file = tempfile;
    $log::logger = Mojo::Log->new(path => $log_file);
    output_once;
    my @matches = (path($log_file)->slurp =~ m/Via .*? function/gm);
    ok(@matches == 5, 'All messages logged to file');
    my $i = 0;
    ok($matches[$i++] =~ /$_/, "Logging $_ match!") for ('diag', 'fctres', 'fctinfo', 'fctwarn', 'modstate');
};

done_testing;
