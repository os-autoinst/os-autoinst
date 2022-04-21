#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(:all :report_warnings);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use consoles::network_console;

my $c = consoles::network_console->new('sut', {});
is $c->activate, undef, 'can call activate';
is $c->connect_remote(undef), undef, 'connect_remote can be called, to be overwritten';

done_testing;
