#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::MockObject;
use Test::MockModule;
use Test::Output qw(stderr_like);
use Mojo::File qw(tempdir path);
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

plan skip_all => 'No network support found' unless getprotobyname 'tcp';

my $c = consoles::localXvnc->new('sut', {});
like $c->sshCommand('user', 'localhost'), qr/^ssh/, 'can call sshCommand';
my $socket_mock = Test::MockModule->new('Socket');
my $vnc_base_mock = Test::MockModule->new('consoles::vnc_base');
my $vnc_mock = Test::MockObject->new->set_true('check_vnc_stalls');
$vnc_base_mock->redefine(connect_remote => $vnc_mock);
$bmwqemu::topdir = "$Bin/..";
my $local_xvnc_mock = Test::MockModule->new('consoles::localXvnc');
$local_xvnc_mock->redefine(start_xvnc => sub {
        _exit(0);    # uncoverable statement
});
stderr_like { $c->activate } qr/Connected to Xvnc/, 'can call activate';
stderr_like { ok $c->callxterm('true', 'window1'), 'can call callxterm'; } qr/Xterm PID: \d+/, 'PID is logged';
$vnc_mock->called_pos_ok(0, 'check_vnc_stalls', 'VNC stall detection configured');
$vnc_mock->called_args_pos_is(0, 2, 0, 'VNC stall detection disabled');
$c->{args}->{log} = 1;
stderr_like { ok $c->callxterm('true', 'window1'), 'can call callxterm'; } qr/Xterm PID: \d+/, 'PID is logged';
is $c->fullscreen({window_name => 'foo'}), 1, 'can call fullscreen';
is $c->disable, undef, 'can call disable';

subtest '_ensure_font_dir populates a writable, unindexed font dir' => sub {
    my $fontdir = tempdir '/tmp/fontdir-XXXX';
    consoles::localXvnc::_ensure_font_dir($fontdir);
    is path("$fontdir/fonts.dir")->slurp,
      "3\n6x13.pcf.gz fixed\n6x13.pcf.gz -misc-fixed-medium-r-normal--13-120-75-75-c-70-iso8859-1\neurlatgr.pcf.gz eurlatgr\n",
      'fonts.dir written verbatim';
};

subtest '_ensure_font_dir skips a missing dir' => sub {
    my $missing = "$dir/no-such-font-dir";
    consoles::localXvnc::_ensure_font_dir($missing);
    ok !-e "$missing/fonts.dir", 'nothing written for a missing dir';
};

subtest '_ensure_font_dir leaves a populated fonts.dir untouched' => sub {
    my $fontdir = tempdir '/tmp/fontdir-XXXX';
    path("$fontdir/fonts.dir")->spew("already indexed content\n");
    consoles::localXvnc::_ensure_font_dir($fontdir);
    is path("$fontdir/fonts.dir")->slurp, "already indexed content\n", 'existing fonts.dir preserved';
};

done_testing;
