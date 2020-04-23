#!/usr/bin/perl

use 5.018;
use strict;
use warnings;

use Test::More;
use Test::MockModule;
use Test::MockObject;
use Test::Output qw(combined_like stderr_like);
use Test::Warnings;
use FindBin '$Bin';
use Mojo::File 'tempdir';

use backend::qemu;

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;

my $proc = Test::MockModule->new('OpenQA::Qemu::Proc');
$proc->mock(exec_qemu            => undef);
$proc->mock(connect_qmp          => undef);
$proc->mock(init_blockdef_images => undef);
ok(my $backend = backend::qemu->new(), 'backend can be created');
# disable any graphics display in tests
$bmwqemu::vars{QEMU_APPEND} = '-nographic';
# as needed to start backend
$bmwqemu::vars{VNC} = '1';
my $jsonrpc = Test::MockModule->new('myjsonrpc');
$jsonrpc->mock(read_json => undef);
my $backend_mock = Test::MockModule->new('backend::qemu', no_auto => 1);
$backend_mock->mock(handle_qmp_command => undef);
my $distri = Test::MockModule->new('distribution');
my %called;
$distri->mock(add_console => sub {
        $called{add_console}++;
        my $ret = Test::MockObject->new();
        $ret->set_true('backend');
        return $ret;
});
$backend_mock->mock(select_console => undef);
$testapi::distri = distribution->new;
($backend->{"select_$_"} = Test::MockObject->new)->set_true('add') for qw(read write);
stderr_like(sub { ok($backend->start_qemu(), 'qemu can be started'); }, qr/running .*chattr/, 'preparing local files');
ok(exists $called{add_console}, 'a console has been added');
is($called{add_console}, 1, 'one console has been added');

done_testing();

chdir $Bin;
