#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Warnings;
use Pod::Coverage;
use File::Basename;

# an alternative to checking Pod::Coverage might be Test::Pod::Coverage but as
# os-autoinst does not really feature full perl modules better just check
# explicitly what we care about right now.

my $dirname = dirname(__FILE__);
chdir($dirname . '/..');

my $pc = Pod::Coverage->new(
    package  => 'testapi',
    pod_from => 'testapi.pm',
);
is($pc->coverage, 1, 'Everything in testapi covered') || diag('Uncovered: ', join(', ', $pc->uncovered), "\n");
done_testing();
