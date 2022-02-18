#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::MockModule;
use Test::Output qw(stderr_like);
use Mojo::File qw(tempdir);
use Mojo::Util qw(scope_guard);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use backend::pvm;

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

my $mock = Test::MockModule->new('backend::pvm');
$mock->redefine(_masterlpar => '42');
$ENV{PVMCTL} = '/bin/true';
$bmwqemu::vars{"NO_DEPRECATE_BACKEND_PVM"} = 1;
stderr_like { backend::pvm->new } qr/DEPRECATED/, 'backend marked as deprecated';
done_testing;
