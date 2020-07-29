#!/usr/bin/perl

use 5.018;
use strict;
use warnings;

use Test::More;
use Test::MockModule;
use Test::MockObject;
use Test::Output qw(combined_like stderr_like);
use Test::Warnings qw(:all :report_warnings);
use Test::Fatal;
use FindBin '$Bin';
use Mojo::File 'tempdir';

use backend::qemu;

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;

my $proc = Test::MockModule->new('OpenQA::Qemu::Proc');
$proc->redefine(exec_qemu            => undef);
$proc->redefine(connect_qmp          => undef);
$proc->redefine(init_blockdev_images => undef);
ok(my $backend = backend::qemu->new(), 'backend can be created');
# disable any graphics display in tests
$bmwqemu::vars{QEMU_APPEND} = '-nographic';
# as needed to start backend
$bmwqemu::vars{VNC} = '1';
my $jsonrpc = Test::MockModule->new('myjsonrpc');
$jsonrpc->redefine(read_json => undef);
my $backend_mock = Test::MockModule->new('backend::qemu', no_auto => 1);
$backend_mock->redefine(handle_qmp_command => undef);
my $distri = Test::MockModule->new('distribution');
my %called;
$distri->redefine(add_console => sub {
        $called{add_console}++;
        my $ret = Test::MockObject->new();
        $ret->set_true('backend');
        return $ret;
});
# "redefine" fails with "backend::qemu::select_console does not exist!" but
# defining this still matters for unknown reason
$backend_mock->mock(select_console => undef);
$testapi::distri = distribution->new;
($backend->{"select_$_"} = Test::MockObject->new)->set_true('add') for qw(read write);
stderr_like { ok($backend->start_qemu(), 'qemu can be started') } qr/running .*chattr/, 'preparing local files';
ok(exists $called{add_console}, 'a console has been added');
is($called{add_console}, 1, 'one console has been added');

my $expected = qr/The name.*not provided|Failed to connect/;
my $msg      = 'error about missing service';
like exception { $backend->_dbus_call('show') }, $expected, $msg . ' in exception';
$bmwqemu::vars{QEMU_NON_FATAL_DBUS_CALL} = 1;
combined_like { ok($backend->_dbus_call('show'), 'failed dbus call ignored gracefully') } $expected, $msg;
$bmwqemu::vars{QEMU_NON_FATAL_DBUS_CALL} = 0;
$backend_mock->redefine(_dbus_do_call => sub { (1, 'failed') });
like exception { $backend->_dbus_call('show') }, qr/failed/, 'failed dbus call throws exception';

$backend_mock->redefine(handle_qmp_command => sub { $called{handle_qmp_command} = $_[1] });
$backend->power({action => 'off'});
ok(exists $called{handle_qmp_command}, 'a qmp command has been called');
is_deeply($called{handle_qmp_command}, {execute => 'quit'}, 'quit has been called for off');
$backend->power({action => 'acpi'});
is_deeply($called{handle_qmp_command}, {execute => 'system_powerdown'}, 'powerdown has been called for acpi');

done_testing();

chdir $Bin;
