#!/usr/bin/perl

use Test::Most;
use Feature::Compat::Try;
use FindBin '$Bin';

use Test::Warnings ':report_warnings';
use Pod::Coverage;
use File::Basename;
use lib "$Bin/..";

# an alternative to checking Pod::Coverage might be Test::Pod::Coverage but as
# os-autoinst does not really feature full perl modules better just check
# explicitly what we care about right now.

chdir $Bin . '/..';

# Pod::Coverage does not reveal the actual error message
try { require testapi }
catch ($e) { diag "Error requiring testapi: $e" }

my $pc = Pod::Coverage->new(
    package => 'testapi',
    pod_from => 'testapi.pm',
);
is($pc->coverage, 1, 'Everything in testapi covered') or diag('Uncovered: ', join(', ', $pc->uncovered), "\n");
diag $pc->why_unrated unless defined $pc->coverage;
done_testing();
