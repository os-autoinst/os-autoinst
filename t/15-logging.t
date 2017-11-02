#!/usr/bin/env perl -w

# Copyright (C) 2017 SUSE LLC
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


use strict;
use warnings;
use Test::More;
use bmwqemu;
use Mojo::File 'tempfile';
use Data::Dumper;


subtest 'Logging to STDERR' => sub {

    # Capture STDERR:
    # 1- dups the current STDERR to $oldSTDERR. This is used to restore the STDERR later
    # 2- Closes the current STDERR
    # 2- Links the STDERR to the variable
    open(my $oldSTDERR, ">&", STDERR) or die "Can't preserve STDERR\n$!\n";
    close STDERR;
    my $output;
    open STDERR, '>', \$output;
    ### Testing code here ###

    my $re = qr/Via .*? function/;

    bmwqemu::diag('Via diag function');
    bmwqemu::fctres('Via fctres function');
    bmwqemu::fctinfo('Via fctinfo function');
    bmwqemu::fctwarn('Via fctwarn function');
    bmwqemu::modstart('Via modstart function');

    my @matches = ($output =~ m/$re/gm);
    ok(@matches == 5, 'All messages logged to STDERR');
    my $i = 0;
    ok($matches[$i++] =~ /$_/, "Logging $_ match!") for ('diag', 'fctres', 'fctinfo', 'fctwarn', 'modstart');

    ### End of the Testing code ###
    # Close the capture (current stdout) and restore STDOUT (by dupping the old STDOUT);
    close STDERR;
    open(STDERR, '>&', $oldSTDERR) or die "Can't dup \$oldSTDERR: $!";


};

subtest 'Logging to file' => sub {

    my $log_file = tempfile;
    $bmwqemu::logger = Mojo::Log->new(path => $log_file);
    my $re = qr/Via .*? function/;

    bmwqemu::diag('Via diag function');
    bmwqemu::fctres('Via fctres function');
    bmwqemu::fctinfo('Via fctinfo function');
    bmwqemu::fctwarn('Via fctwarn function');
    bmwqemu::modstart('Via modstart function');

    my @matches = (Mojo::File->new($log_file)->slurp =~ m/$re/gm);
    ok(@matches == 5, 'All messages logged to file');
    my $i = 0;
    ok($matches[$i++] =~ /$_/, "Logging $_ match!") for ('diag', 'fctres', 'fctinfo', 'fctwarn', 'modstart');
};




done_testing;
