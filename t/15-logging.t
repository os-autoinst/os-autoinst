#!/usr/bin/perl

# Copyright 2017-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Output qw(stderr_from);
use bmwqemu;
use Mojo::File 'tempfile';
use Data::Dumper;


sub output_once {
    bmwqemu::diag('Via diag function');
    bmwqemu::fctres('Via fctres function');
    bmwqemu::fctinfo('Via fctinfo function');
    bmwqemu::fctwarn('Via fctwarn function');
    bmwqemu::modstart('Via modstart function');
}

subtest 'Logging to STDERR' => sub {
    my $output = stderr_from(\&output_once);
    note $output;
    my @matches = ($output =~ m/Via .*? function/gm);
    ok(@matches == 5, 'All messages logged to STDERR');
    my $i = 0;
    ok($matches[$i++] =~ /$_/, "Logging $_ match!") for ('diag', 'fctres', 'fctinfo', 'fctwarn', 'modstart');
};

subtest 'Logging to file' => sub {
    my $log_file = tempfile;
    $bmwqemu::logger = Mojo::Log->new(path => $log_file);
    output_once;
    my @matches = (Mojo::File->new($log_file)->slurp =~ m/Via .*? function/gm);
    ok(@matches == 5, 'All messages logged to file');
    my $i = 0;
    ok($matches[$i++] =~ /$_/, "Logging $_ match!") for ('diag', 'fctres', 'fctinfo', 'fctwarn', 'modstart');
};

done_testing;
