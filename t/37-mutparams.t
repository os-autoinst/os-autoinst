#!/usr/bin/perl
#
# Copyright 2022 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later


use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Fatal;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Warnings qw(warnings :report_warnings);
use OpenQA::Qemu::MutParams;

my $mutparams = OpenQA::Qemu::MutParams->new;

my @methods = qw(gen_cmdline to_map from_map has_state);
for my $method (@methods) {
    like(exception { $mutparams->$method }, qr{has not implemented $method}, "Exception for not implemented $method");
}

done_testing;
