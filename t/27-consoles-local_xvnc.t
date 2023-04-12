#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::MockObject;
use Test::MockModule;
use Test::Output qw(stderr_like);
use Mojo::File qw(tempdir);
use Mojo::Util qw(scope_guard);
use POSIX qw(_exit);
use Socket;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

BEGIN { *consoles::localXvnc::system = sub { 1 } }
BEGIN { *CORE::GLOBAL::sleep = sub { 1 } }

# mock external tool for testing
$ENV{OS_AUTOINST_XDOTOOL} = 'true';

use consoles::localXvnc;

plan skip_all => 'No network support found' unless getprotobyname('tcp');

my $c = consoles::localXvnc->new('sut', {});
like $c->sshCommand('user', 'localhost'), qr/^ssh/, 'can call sshCommand';
my $socket_mock = Test::MockModule->new('Socket');
my $vnc_base_mock = Test::MockModule->new('consoles::vnc_base');
my $vnc_mock = Test::MockObject->new->set_true('check_vnc_stalls');
$vnc_base_mock->redefine(connect_remote => $vnc_mock);
$bmwqemu::scriptdir = "$Bin/..";
my $local_xvnc_mock = Test::MockModule->new('consoles::localXvnc');
# uncoverable statement count:2
$local_xvnc_mock->redefine(start_xvnc => sub { _exit(0) });
stderr_like { $c->activate } qr/Connected to Xvnc/, 'can call activate';
is $c->callxterm('true', 'window1'), '', 'can call callxterm';
$vnc_mock->called_pos_ok(0, 'check_vnc_stalls', 'VNC stall detection configured');
$vnc_mock->called_args_pos_is(0, 2, 0, 'VNC stall detection disabled');
$c->{args}->{log} = 1;
is $c->callxterm('true', 'window1'), '', 'can call callxterm';
is $c->fullscreen({window_name => 'foo'}), 1, 'can call fullscreen';
is $c->disable, undef, 'can call disable';

done_testing;
