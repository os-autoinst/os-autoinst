#!/usr/bin/perl

# Copyright (c) 2020-2021 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

use Test::Most;
use Mojo::Base -strict, -signatures;

# mock sleeps
my @invoked_cmds;
BEGIN { *CORE::GLOBAL::sleep = sub { push @invoked_cmds, [sleep => shift] } }

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::MockModule;
use Test::Warnings qw(:all :report_warnings);
use Test::Fatal;
use Mojo::File qw(tempdir);

use bmwqemu;
use backend::generalhw;
use distribution;
use testapi;

# setup test variables
my $cmd_dir = tempdir;
my $cmd_ctl = "$cmd_dir/ctl";
$bmwqemu::vars{WORKER_HOSTNAME}         = 'worker-hostname';
$bmwqemu::vars{GENERAL_HW_CMD_DIR}      = $cmd_dir;
$bmwqemu::vars{GENERAL_HW_POWERON_CMD}  = 'ctl poweron';
$bmwqemu::vars{GENERAL_HW_POWEROFF_CMD} = 'ctl poweroff';
$bmwqemu::vars{GENERAL_HW_SOL_CMD}      = 'ctl console';
$bmwqemu::vars{GENERAL_HW_SOL_ARGS}     = 'console';
$bmwqemu::vars{GENERAL_HW_FLASH_CMD}    = 'ctl flash';
$bmwqemu::vars{GENERAL_HW_FLASH_ARGS}   = 'light';
$bmwqemu::vars{GENERAL_HW_VNC_IP}       = 'vnc.server';
$bmwqemu::vars{HDD_1}                   = '/hdd';
$bmwqemu::vars{HDDSIZEGB_1}             = 5;

# initialize distribution and backend
my $distri  = $testapi::distri = distribution->new;
my $backend = backend::generalhw->new;

# mock IPC::Run and the VNC console
my $ipc_run_mock = Test::MockModule->new('IPC::Run');
my $fake_ipc_error;
$ipc_run_mock->redefine(run => sub {
        my ($args, $stdin, $stdout, $stderr) = @_;
        die $fake_ipc_error if $fake_ipc_error;
        push @invoked_cmds, $args;
        $$stdin  = 'stdin';
        $$stdout = 'stdout';
        $$stderr = 'stderr';
});
my $serial_mock = Test::MockModule->new('backend::generalhw');
$serial_mock->redefine(start_serial_grab => sub { push @invoked_cmds, 'start_serial_grab' });
my $vnc_mock = Test::MockModule->new('consoles::VNC');
my @vnc_logins;
$vnc_mock->redefine(login => sub { push @vnc_logins, [shift->hostname] });
$vnc_mock->redefine($_    => sub { }) for (qw(_receive_message _send_frame_buffer send_update_request));
my $bmwqemu_mock = Test::MockModule->new('bmwqemu');
# silence some log output for cleaner tests
$bmwqemu_mock->noop('diag');

subtest 'start VM' => sub {
    # start the "VM" which should actually just run a few commands via IPC::Run and start the VNC and serial consoles
    is_deeply($backend->do_start_vm, {}, 'return value');
    is_deeply(\@invoked_cmds, [
            [$cmd_ctl, 'poweroff'], [$cmd_ctl, 'flash', 'light', '/hdd', '5G'], [$cmd_ctl, 'poweroff'],
            ['sleep',  3],          [$cmd_ctl, 'poweron'], 'start_serial_grab'
    ], 'poweroff/on commands invoked') or diag explain \@invoked_cmds;
    is_deeply(\@vnc_logins, [['vnc.server']], 'tried to connect to VNC server') or diag explain \@vnc_logins;
};

subtest 'stop VM' => sub {
    @invoked_cmds = ();
    is_deeply($backend->do_stop_vm, {},                       'return value');
    is_deeply(\@invoked_cmds,       [[$cmd_ctl, 'poweroff']], 'poweroff/on commands invoked') or diag explain \@invoked_cmds;
};

subtest 'error handling' => sub {
    $fake_ipc_error = 'fake error';
    throws_ok(
        sub { $backend->run_cmd('GENERAL_HW_POWEROFF_CMD') },
        qr/Unable to run command '$cmd_ctl poweroff' \(deduced from test variable GENERAL_HW_POWEROFF_CMD\): fake error/,
        'IPC error thrown with context'
    );
    $bmwqemu::vars{GENERAL_HW_CMD_DIR} = 'does-not-exist';
    throws_ok(
        sub { $backend->run_cmd('GENERAL_HW_POWEROFF_CMD') },
        qr/GENERAL_HW_CMD_DIR .* not .* directory/,
        'error when GENERAL_HW_CMD_DIR is not a directory'
    );
    $bmwqemu::vars{WORKER_HOSTNAME} = undef;
    throws_ok(
        sub { backend::generalhw->new },
        qr/WORKER_HOSTNAME/,
        'WORKER_HOSTNAME required'
    );
};

done_testing();
