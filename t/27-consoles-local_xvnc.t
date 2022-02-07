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
$vnc_base_mock->noop('connect_remote');
$bmwqemu::scriptdir = "$Bin/..";
my $local_xvnc_mock = Test::MockModule->new('consoles::localXvnc');
$local_xvnc_mock->redefine(start_xvnc => sub { _exit(0) });
stderr_like { $c->activate } qr/Connected to Xvnc/, 'can call activate';
is $c->callxterm('true', 'window1'), '', 'can call callxterm';
$c->{args}->{log} = 1;
is $c->callxterm('true', 'window1'), '', 'can call callxterm';
is $c->fullscreen({window_name => 'foo'}), 1, 'can call fullscreen';
is $c->disable, undef, 'can call disable';

my $base_screen_update_called;
$vnc_base_mock->redefine(request_screen_update => sub { ++$base_screen_update_called });
is $c->request_screen_update({incremental => 0}), 0, 'non-incremental screen updated prevented';
is $base_screen_update_called, undef, 'non-incremental screen update not passed to vnc_base';
is $c->request_screen_update(), 1, 'incremental screen updated done as usual';
is $c->request_screen_update({incremental => 1}), 2, 'explicit incremental screen updated done as usual';

done_testing;
