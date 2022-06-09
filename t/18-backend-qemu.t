#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::MockModule;
use Test::MockObject;
use Test::Output qw(combined_like stderr_like);
use Test::Warnings qw(:all :report_warnings);
use Test::Fatal;
use Carp;
use Mojo::File qw(tempdir path);
use Mojo::Util qw(scope_guard);
use Mojo::JSON;

use backend::qemu;

sub backend () {
    my $backend = backend::qemu->new();
    ($backend->{"select_$_"} = Test::MockObject->new)->set_true('add') for qw(read write);
    return $backend;
}

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

my $proc = Test::MockModule->new('OpenQA::Qemu::Proc');
$proc->redefine(exec_qemu => undef);
$proc->redefine(connect_qmp => undef);
$proc->redefine(init_blockdev_images => undef);
ok(my $backend = backend(), 'backend can be created');
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

stderr_like { ok($backend->start_qemu(), 'qemu can be started') } qr/running .*chattr/, 'preparing local files';
ok(exists $called{add_console}, 'a console has been added');
is($called{add_console}, 1, 'one console has been added');

subtest 'using Open vSwitch D-Bus service' => sub {
    my $expected = qr/Open vSwitch command.*show.*arguments 'foo bar'.*(The name.*not provided|Failed to connect)/;
    my $msg = 'error about missing service';
    like exception { $backend->_dbus_call('show', 'foo', 'bar') }, $expected, $msg . ' in exception';
    $bmwqemu::vars{QEMU_NON_FATAL_DBUS_CALL} = 1;
    combined_like { ok($backend->_dbus_call('show', 'foo', 'bar'), 'failed dbus call ignored gracefully') } $expected, $msg;
    $bmwqemu::vars{QEMU_NON_FATAL_DBUS_CALL} = 0;
    $backend_mock->redefine(_dbus_do_call => sub { (1, 'failed') });
    like exception { $backend->_dbus_call('show') }, qr/failed/, 'failed dbus call throws exception';
};

$backend_mock->redefine(handle_qmp_command => sub { push @{$called{handle_qmp_command}}, $_[1] });
$backend->power({action => 'off'});
ok(exists $called{handle_qmp_command}, 'a qmp command has been called');
is_deeply($called{handle_qmp_command}, [{execute => 'quit'}], 'quit has been called for off');
$called{handle_qmp_command} = undef;
$backend->power({action => 'acpi'});
is_deeply($called{handle_qmp_command}, [{execute => 'system_powerdown'}], 'powerdown has been called for acpi');
$called{handle_qmp_command} = undef;

subtest 'eject cd' => sub {
    my %default_eject_params = (execute => 'eject', arguments => {id => 'cd0-device', force => Mojo::JSON->true});
    my %default_remove_params = (execute => 'blockdev-remove-medium', arguments => {id => 'cd0-device'});
    my %custom_eject_params = (execute => 'eject', arguments => {id => 'cd1', force => Mojo::JSON->false});
    my %custom_remove_params = (execute => 'blockdev-remove-medium', arguments => {id => 'cd1'});

    $called{handle_qmp_command} = undef;
    $backend->eject_cd;
    is_deeply $called{handle_qmp_command}[0], \%default_eject_params, 'eject called with correct defaults';
    is_deeply $called{handle_qmp_command}[1], \%default_remove_params, 'blockdev-remove-medium called with correct defaults';
    $called{handle_qmp_command} = undef;
    $backend->eject_cd({id => 'cd1', force => 0});
    is_deeply $called{handle_qmp_command}[0], \%custom_eject_params, 'eject called with custom parameters';
    is_deeply $called{handle_qmp_command}[1], \%custom_remove_params, 'blockdev-remove-medium called with custom parameters';
};

subtest 'switch_network' => sub {
    my %switch_network_params = (arguments => {name => 'qanet0', up => Mojo::JSON->false}, execute => 'set_link');
    $called{handle_qmp_command} = undef;

    $backend->switch_network({network_enabled => 0});
    ok(exists $called{handle_qmp_command}, 'network must be disabled');
    is_deeply($called{handle_qmp_command}[0], \%switch_network_params, 'qmp command for setlink is passed');

    $called{handle_qmp_command} = undef;
    $backend->switch_network({network_enabled => 1, network_link_name => 'bingo'});
    %switch_network_params = (arguments => {name => 'bingo', up => Mojo::JSON->true}, execute => 'set_link');
    ok(exists $called{handle_qmp_command}, 'a qmp command has been called');
    is_deeply($called{handle_qmp_command}[0], \%switch_network_params, 'Network name can be specified, network can be enabled');

    $called{handle_qmp_command} = undef;
};

subtest 'execute arbitrary QMP command' => sub {
    my %query = (execute => 'foo', arguments => {bar => 1});
    $called{handle_qmp_command} = undef;
    $backend->execute_qmp_command({query => \%query});
    is_deeply $called{handle_qmp_command}, [\%query], 'query params passed as-is';
};

subtest 'process_qemu_output' => sub {
    my $qemu_log = <<'EOF';
QEMU emulator version 4.2.1 (openSUSE Leap 15.2)
Copyright 2003-2019 Fabrice Bellard and the QEMU Project developers
qemu-system-x86_64: cannot set up guest memory 'pc.ram': Cannot allocate memory
EOF
    my $expected = qr/\[debug\].*QEMU emulator version.*\[warn\].*Cannot allocate memory/s;
    my $msg = 'qemu output logged with distinct log levels';
    combined_like { backend::qemu::process_qemu_output($qemu_log) } $expected, $msg;
};

# For all following tests log output is not needed and is disabled to not
# pollute stderr
my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
$mock_bmwqemu->noop('log_call', 'fctwarn', 'diag');

sub qemu_cmdline (%args) {
    $bmwqemu::vars{$_} = $args{$_} for keys %args;
    $backend = backend();
    croak 'Failed to start qemu backend' unless $backend->start_qemu;
    return join(' ', $backend->{proc}->gen_cmdline);
}

$bmwqemu::vars{OFW} = 1;
like qemu_cmdline(), qr/cap-cfpc=broken/, 'OFW workarounds applied';

# test QEMU_HUGE_PAGES_PATH with different options
subtest qemu_huge_pages_option => sub {
    my $cmdline = qemu_cmdline(QEMU_HUGE_PAGES_PATH => '/no/dev/hugepages/');
    like $cmdline, qr/-mem-prealloc/, '-mem-prealloc option added';
    like $cmdline, qr|-mem-path /no/dev/hugepages/|, '-mem-path /no/dev/hugepages/';
    delete $bmwqemu::vars{QEMU_HUGE_PAGES_PATH};
};

subtest qemu_tpm_option => sub {
    $bmwqemu::vars{QEMUTPM_PATH_PREFIX} = "$dir/mytpm";
    my $runcmd;
    $backend_mock->redefine(runcmd => sub (@cmd) { $runcmd = join(' ', @cmd) });
    my $cmdline = qemu_cmdline(QEMUTPM => 'instance', WORKER_INSTANCE => 3);
    like $cmdline, qr|-chardev socket,id=chrtpm,path=.*mytpm3/swtpm-sock|, '-chardev socket option added (instance)';
    like $cmdline, qr|-tpmdev emulator,id=tpm0,chardev=chrtpm|, '-tpmdev emulator option added';
    like $cmdline, qr|-device tpm-tis,tpmdev=tpm0|, '-device tpm-tis option added';

    # call qemu with QEMUTPM=2
    mkdir("$dir/mytpm2");
    path("$dir/mytpm2/swtpm-sock")->touch;
    like qemu_cmdline(QEMUTPM => '2'), qr|-chardev socket,id=chrtpm,path=.*mytpm2/swtpm-sock|, '-chardev socket option added (2)';

    # call qemu with QEMUTPM=instance, ppc64le arch
    $cmdline = qemu_cmdline(QEMUTPM => 'instance', ARCH => 'ppc64le');
    like $cmdline, qr|-chardev socket,id=chrtpm,path=.*mytpm3/swtpm-sock|, '-chardev socket option added (instance)';
    like $cmdline, qr/-tpmdev emulator,id=tpm0,chardev=chrtpm/, '-tpmdev emulator option added';
    like $cmdline, qr/-device tpm-spapr,tpmdev=tpm0/, '-device tpm-spapr option added';
    like $cmdline, qr/-device spapr-vscsi,id=scsi9,reg=0x00002000/, '-device spapr-vscsi option added';

    # call qemu with QEMUTPM=instance, aarch64 arch
    $cmdline = qemu_cmdline(QEMUTPM => 'instance', ARCH => 'aarch64');
    like $cmdline, qr|-chardev socket,id=chrtpm,path=.*mytpm3/swtpm-sock|, '-chardev socket option added (instance)';
    like $cmdline, qr/-tpmdev emulator,id=tpm0,chardev=chrtpm/, '-tpmdev emulator option added';
    like $cmdline, qr/-device tpm-tis-device,tpmdev=tpm0/, '-device tpm-tis option added';

    # call qemu with QEMUTPM=4 w/o creating a device beforehand
    $cmdline = qemu_cmdline(QEMUTPM => '4');
    like $runcmd, qr|swtpm socket --tpmstate dir=.*mytpm4 --ctrl type=unixio,path=.*mytpm4/swtpm-sock --log level=20 -d --tpm2|, 'swtpm default device created';

    # call qemu with QEMUTPM=5, QEMUTPM_VER=2.0 w/o creating a device beforehand
    $cmdline = qemu_cmdline(QEMUTPM => '5', QEMUTPM_VER => '2.0');
    like $runcmd, qr|swtpm socket --tpmstate dir=.*mytpm5 --ctrl type=unixio,path=.*mytpm5/swtpm-sock --log level=20 -d --tpm2|, 'swtpm 2.0 device created';

    # call qemu with QEMUTPM=6, QEMU_TPM_VER=1.2 w/o creating a device beforehand
    $cmdline = qemu_cmdline(QEMUTPM => '6', QEMUTPM_VER => '1.2');
    like $runcmd, qr|swtpm socket --tpmstate dir=.*mytpm6 --ctrl type=unixio,path=.*mytpm6/swtpm-sock --log level=20 -d|, 'swtpm 1.2 device created';
};

subtest qemu_vga_option => sub {
    my $runcmd;
    $backend_mock->redefine(runcmd => sub (@cmd) { $runcmd = join(' ', @cmd) });
    unlike qemu_cmdline(QEMUVGA => undef), qr|-vga|, 'nothing specified by default';
    like qemu_cmdline(QEMUVGA => 'std'), qr|-vga std|, 'std selected explicitly';
    throws_ok { qemu_cmdline(QEMUVGA => 'qxl') } qr/qxl is unsupported/, 'unsupported vga aborts execution';
};

done_testing();
