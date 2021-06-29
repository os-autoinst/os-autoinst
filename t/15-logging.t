#!/usr/bin/perl

# Copyright (C) 2017-2020 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.


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
