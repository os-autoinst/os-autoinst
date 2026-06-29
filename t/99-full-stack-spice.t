#!/usr/bin/perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -signatures;
use Test::Most;
use Test::Warnings ':report_warnings';
use Feature::Compat::Try;
use FindBin '$Bin';

if (!-f "$Bin/99-full-stack.t") {
    plan skip_all => 't/99-full-stack.t is not present';
}

# Enable the SPICE backend for the full stack test run
$ENV{OS_AUTOINST_SPICE} = 1;

# Evaluate and execute the original full stack test
try {
    local $SIG{__DIE__} = undef;
    do "$Bin/99-full-stack.t";
}
catch ($e) {
    die $e;
}
