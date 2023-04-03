#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Test::Warnings ':report_warnings';

use FindBin '$Bin';
use lib "$FindBin::Bin/lib", "$Bin/../external/os-autoinst-common/lib";

my %allowed_types = (
    'text/x-perl' => 1,
    'text/x-python' => 1,
    'text/x-shellscript' => 1,
);

# Could also use MIME::Types, would be new dependency
chomp(my @types = qx{cd $Bin/..; for i in *; do echo \$i; file --mime-type --brief \$i; done});

my %types = @types;
for my $key (keys %types) {
    delete $types{$key} unless $allowed_types{$types{$key}};
}

for my $script ("isotovideo") {
    my $out = qx{timeout 8 $Bin/../$script --help 2>&1};
    my $rc = $? >> 8;
    is $rc, 0, "Calling '$script --help' returns exit code 0" or diag "Output($script): $out";
}

done_testing;
