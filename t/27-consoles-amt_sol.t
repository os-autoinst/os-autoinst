#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::MockModule;
use Test::MockObject;
use Test::Output qw(stderr_like);
 use Mojo::File qw(tempfile);
# use Mojo::Util qw(scope_guard);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';

#my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
#chdir $dir;
#my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

my $amt_console_mock = Test::MockObject->new;

BEGIN {
    *consoles::amtSol::open = sub (@args) {
        @_[0] = $amt_console_mock;
        $_[0]->set_true('blocking');
    };
    *consoles::amtSol::kill = sub {};
}

use consoles::amtSol;

my $c = consoles::amtSol->new('sut', {});
my $io_select_mock_object = Test::MockObject->new;
$io_select_mock_object->set_true('add');
$io_select_mock_object->set_always('can_read', $amt_console_mock);
my $io_select_mock = Test::MockModule->new('IO::Select');
$io_select_mock->redefine(new => $io_select_mock_object);
my @warnings = warnings { stderr_like { $c->activate } qr/started amtterm/, 'can call activate' };
is $c->screen, undef, 'can call screen';
stderr_like { $c->disable } qr/waiting for termination/, 'can call disable';

done_testing;
