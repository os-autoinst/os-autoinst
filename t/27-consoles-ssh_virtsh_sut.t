#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(:all :report_warnings);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use consoles::sshVirtshSUT;

my $c = consoles::sshVirtshSUT->new('sut', {});
is $c->screen, undef, 'no screen defined';
is $c->is_serial_terminal, 1, 'is a serial terminal';

done_testing;
