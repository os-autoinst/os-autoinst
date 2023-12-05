#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;

use FindBin qw($Bin $Script);
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::MockModule;
use Test::MockObject;
use Test::Mock::Time;
use Test::Output qw(combined_like stderr_like);
use Test::Warnings qw(:all :report_warnings);
use Test::Fatal;
use Carp;
use Mojo::Collection;
use Mojo::File qw(tempdir path);
use Mojo::Util qw(scope_guard);
use Mojo::JSON;
use Scalar::Util qw(looks_like_number);

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
my $invoked_qmp_cmds = \$called{handle_qmp_command};
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

    # test one unmocked _dbus_do_call againsted mocked Net::DBus
    $backend_mock->unmock('_dbus_do_call');
    my $fake_object = Test::MockObject->new;
    $fake_object->mock(foo => sub ($self, $one, $two) { $one == 1 && $two == 2 ? (qw(the result)) : () });
    my $fake_service = Test::MockObject->new;
    $fake_service->mock(get_object => sub ($self, $path, $name) { $path eq '/switch' && $name eq 'org.opensuse.os_autoinst.switch' ? $fake_object : undef });
    my $fake_connection = Test::MockObject->new;
    $fake_connection->set_always(disconnect => 1);
    my $fake_bus = Test::MockObject->new;
    $fake_bus->set_always(get_connection => $fake_connection);
    $fake_bus->mock(get_service => sub ($self, $name) { $name eq 'org.opensuse.os_autoinst.switch' ? $fake_service : undef });
    my $dbus_mock = Test::MockModule->new('Net::DBus');
    $dbus_mock->redefine(system => sub ($self, %args) { $args{private} ? $fake_bus : undef });
    is_deeply [$backend->_dbus_do_call(foo => 1, 2)], [qw(the result)], 'result returned';
};

my $fake_qmp_answer;
$backend_mock->redefine(handle_qmp_command => sub { push @{$called{handle_qmp_command}}, $_[1]; $fake_qmp_answer });
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

subtest 'setting graphics backend' => sub {
    my @params;
    local *backend::qemu::sp = sub (@args) { @params = @args };
    $backend->_set_graphics_backend(0);
    is_deeply \@params, [device => 'VGA,edid=on,xres=1024,yres=768'], 'default backend is VGA with EDID info (no QEMUVGA or QEMU_VIDEO_DEVICE set)' or diag explain \@params;

    $backend->_set_graphics_backend(1);
    is_deeply \@params, [device => 'virtio-gpu-pci,edid=on,xres=1024,yres=768'], 'default backend for ARM is virtio with EDID info (no QEMUVGA or QEMU_VIDEO_DEVICE set)' or diag explain \@params;

    $bmwqemu::vars{QEMU_OVERRIDE_VIDEO_DEVICE_AARCH64} = '1';
    $backend->_set_graphics_backend(1);
    is_deeply \@params, [device => 'VGA,edid=on,xres=1024,yres=768'], 'QEMU_OVERRIDE_VIDEO_DEVICE_AARCH64 changes ARM default to VGA' or diag explain \@params;
    delete $bmwqemu::vars{QEMU_OVERRIDE_VIDEO_DEVICE_AARCH64};

    $bmwqemu::vars{QEMUVGA} = 'virtio';
    $backend->_set_graphics_backend(0);
    is_deeply \@params, [device => 'virtio-vga,edid=on,xres=1024,yres=768'], 'QEMUVGA=virtio results in device virtio-vga with EDID info' or diag explain \@params;

    $bmwqemu::vars{QEMUVGA} = 'cirrus';
    $backend->_set_graphics_backend(0);
    is_deeply \@params, [device => 'cirrus-vga'], 'QEMUVGA=cirrus results in device cirrus-vga with no EDID info' or diag explain \@params;

    $bmwqemu::vars{QEMU_VIDEO_DEVICE} = 'virtio-vga';
    $backend->_set_graphics_backend(0);
    is_deeply \@params, [device => 'virtio-vga,edid=on,xres=1024,yres=768'], 'QEMU_VIDEO_DEVICE wins if both it and QEMUVGA are set' or diag explain \@params;

    delete $bmwqemu::vars{QEMUVGA};
    $bmwqemu::vars{QEMU_VIDEO_DEVICE_OPTIONS} = 'foo=bar';
    $backend->_set_graphics_backend(0);
    is_deeply \@params, [device => 'virtio-vga,edid=on,xres=1024,yres=768,foo=bar'], 'QEMU_VIDEO_DEVICE_OPTIONS gets appended to EDID values' or diag explain \@params;
};

sub qemu_cmdline (%args) {
    $bmwqemu::vars{$_} = $args{$_} for keys %args;
    $backend = backend();
    croak 'Failed to start qemu backend' unless $backend->start_qemu;
    return join(' ', $backend->{proc}->gen_cmdline);
}

like qemu_cmdline(OFW => 1, XRES => 640, YRES => 480), qr/-g 640x480/, 'res is set for ppc/sparc';
like qemu_cmdline(OFW => 1), qr/cap-cfpc=broken/, 'OFW workarounds applied';

sub test_boot_options ($boot, $arch, $pxe, $expected) {
    my $cmdline;
    my $bootfrom_supported = 0;
    if ($pxe) {
        $cmdline = qemu_cmdline(PXEBOOT => $pxe, ARCH => $arch);
    } else {
        $cmdline = qemu_cmdline(BOOTFROM => $boot, ARCH => $arch);
        $bootfrom_supported = $arch ne 'x86_64';
    }
    if ($bootfrom_supported) {
        unlike $cmdline, $expected, "'-boot' option is ignored on $arch";
    } else {
        like $cmdline, $expected, '-boot gets correct parameter';
    }
}

subtest 'qemu_net_boot' => sub {
    subtest 'qemu_bootindex_default' => sub {
        my $cmdline = qemu_cmdline(ARCH => 'x86_64');
        like $cmdline, qr|mac=\d{2}:\d{2}:\d{2}:\d{2}:\d{2}:\d{2}\s|, 'device does not set bootindex by default on x86_64';
        like $cmdline, qr|-boot once=d|, 'boot parameter is set to once';
        $cmdline = qemu_cmdline(ARCH => 'aarch64');
        like $cmdline, qr|mac=\d{2}:\d{2}:\d{2}:\d{2}:\d{2}:\d{2}\s|, 'device does not set bootindex by default on aarch64';
        unlike $cmdline, qr|-boot once=d|, 'boot parameter is not set on aarch64';
    };
    subtest('Test boot with n on x86_64', \&test_boot_options, 'n', 'x86_64', undef, qr|-boot order=n|);
    subtest('Test boot with net on x86_64', \&test_boot_options, 'net', 'x86_64', undef, qr|-boot order=n|);
    subtest('Test boot with n on aarch64', \&test_boot_options, 'n', 'aarch64', undef, qr|-boot order=n|);
    subtest('Test boot with net on aarch64', \&test_boot_options, 'net', 'aarch64', undef, qr|-boot order=n|);
    $bmwqemu::vars{BOOTFROM} = 'nc';
    throws_ok { $backend->start_qemu } qr{unsupported boot order: nc}, 'dies on multi boot order as os-autoinst doesnt supported';
    delete $bmwqemu::vars{BOOTFROM};
    delete $bmwqemu::vars{BOOT_MENU};
    subtest('Test boot with n on x86_64', \&test_boot_options, 0, 'x86_64', 1, qr|mac=52:54:00:12:34:56,bootindex=1|);
    subtest('Test boot with set c to bootindex=0 on x86_64', \&test_boot_options, 0, 'x86_64', 1, qr|drive=hd0,bootindex=0|);
    subtest('Test boot with n on aarch64', \&test_boot_options, 0, 'aarch64', 1, qr|mac=52:54:00:12:34:56,bootindex=1|);
    subtest('Test boot with set c to bootindex=0 on aarch64', \&test_boot_options, 0, 'aarch64', 1, qr|drive=hd0,bootindex=0|);
    subtest('Test boot with n on s390x', \&test_boot_options, 0, 's390x', 1, qr|mac=52:54:00:12:34:56,bootindex=1|);
    subtest('Test boot with set c to bootindex=0 on s390x', \&test_boot_options, 0, 's390x', 1, qr|drive=hd0,bootindex=0|);
    subtest('Test boot with n on ppc64le', \&test_boot_options, 0, 'ppc64le', 1, qr|mac=52:54:00:12:34:56,bootindex=1|);
    subtest('Test boot with set c to bootindex=0 on ppc64le', \&test_boot_options, 0, 'ppc64le', 1, qr|drive=hd0,bootindex=0|);
    delete $bmwqemu::vars{PXEBOOT};
    delete $bmwqemu::vars{ARCH};
};

# test QEMU_HUGE_PAGES_PATH with different options
subtest qemu_huge_pages_option => sub {
    my $cmdline = qemu_cmdline(QEMU_HUGE_PAGES_PATH => '/no/dev/hugepages/');
    like $cmdline, qr/-mem-prealloc/, '-mem-prealloc option added';
    like $cmdline, qr|-mem-path /no/dev/hugepages/|, '-mem-path /no/dev/hugepages/';
    delete $bmwqemu::vars{QEMU_HUGE_PAGES_PATH};
};

my $runcmd;
$backend_mock->redefine(runcmd => sub (@cmd) { $runcmd = join(' ', @cmd) });

subtest qemu_tpm_option => sub {
    $bmwqemu::vars{QEMUTPM_PATH_PREFIX} = "$dir/mytpm";
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

subtest s390x_options => sub {
    my $cmdline = qemu_cmdline(ARCH => 's390x', QEMU_VIDEO_DEVICE => 'virtio-gpu', OFW => 0);
    like $cmdline, qr/-device virtio-gpu,edid=on/, '-device virtio-gpu,edid=on option added';
    unlike $cmdline, qr/-boot.*/, '-boot options not added';
    like $cmdline, qr/-device virtio-keyboard/, '-device virtio-keyboard option added';
    unlike $cmdline, qr/(audiodev|soundhw)/, 'audio options not added';
    unlike $cmdline, qr/isa-fdc.fdtypeA=none/, 'isa-fdc.fdtypeA=none option is not added';
    like $cmdline, qr/-device virtio-rng/, '-device virtio-rng option added';
    like $cmdline, qr/-device virtio-tablet/, '-device virtio-tablet option added';
};

subtest 'capturing audio' => sub {
    $called{handle_qmp_command} = undef;
    $backend->start_audiocapture({filename => 'foo'});
    $backend->stop_audiocapture({});
    is_deeply $called{handle_qmp_command}, [{
            arguments => {'command-line' => 'wavcapture foo snd0 44100 16 1'},
            execute => 'human-monitor-command',
        }, {
            arguments => {'command-line' => 'stopcapture 0'},
            execute => 'human-monitor-command',
        }], 'expected QMP command called' or diag explain $called{handle_qmp_command};
};

subtest 'wait functions' => sub {
    my $start = time;
    my $timeout = $bmwqemu::vars{QEMU_MAX_MIGRATION_TIME} = 3;
    my $log_mock = Test::MockModule->new('log')->redefine(diag => undef);
    subtest 'waiting until status changes' => sub {
        $fake_qmp_answer = {return => {status => 'foo'}};
        $$invoked_qmp_cmds = undef;
        throws_ok { $backend->_wait_while_status_is('foo', $timeout, 'test fail message') } qr/test fail message.*status is foo/, 'dies on timeout';
        is time - $start, $timeout, "would have waited $timeout seconds";
        $fake_qmp_answer = undef;
        $backend->_wait_while_status_is('foo', $timeout, 'test fail message');
        is time - $start, $timeout, 'waited no further as status differs';
        is_deeply $$invoked_qmp_cmds->[$_], {execute => 'query-status'}, "status queries ($_)" for (0 .. 4);
    };
    subtest 'waiting for migration (failure)' => sub {
        $fake_qmp_answer = {return => {status => 'running', ram => {total => 41, remaining => 15}}};
        $$invoked_qmp_cmds = undef;
        throws_ok { $backend->_wait_for_migrate } qr/Migrate to file failed.*running for more than $timeout/,
          'migration considered failed after timeout';
        is_deeply $$invoked_qmp_cmds->[-2], {execute => 'query-migrate'}, 'migration queried';
        is_deeply $$invoked_qmp_cmds->[-1], {execute => 'migrate_cancel'}, 'migration cancelled';
    };
    subtest 'waitinng for migration (success)' => sub {
        my @wait_args;
        $backend_mock->redefine(_wait_while_status_is => sub ($self, $regex, @) { @wait_args = ($self, $regex) });
        $fake_qmp_answer = {return => {status => 'completed', ram => {total => 41, remaining => 15}}};
        $$invoked_qmp_cmds = undef;
        $backend->_wait_for_migrate;
        is_deeply $$invoked_qmp_cmds, [{execute => 'query-migrate'}], 'migration queried' or diag explain $$invoked_qmp_cmds;
        is_deeply \@wait_args, [$backend, qr/paused|finish-migrate/], 'waited for status change' or diag explain \@wait_args;
    };
};

subtest 'migration to file' => sub {
    my @wait_for_migrate_args;
    $backend_mock->redefine(_wait_for_migrate => sub (@args) { @wait_for_migrate_args = @args });
    $$invoked_qmp_cmds = undef;
    $backend->_migrate_to_file(filename => 'foo');
    is_deeply \@wait_for_migrate_args, [$backend], 'migration awaited';
    is_deeply $$invoked_qmp_cmds, [
        {execute => 'migrate-set-capabilities', arguments => {capabilities => [{capability => 'events', state => Mojo::JSON->true}]}},
        {execute => 'migrate-set-parameters', arguments => {'compress-level' => 0, 'compress-threads' => 2, 'max-bandwidth' => '9223372036854775807'}},
        {execute => 'getfd', arguments => {fdname => 'dumpfd'}},
        {execute => 'stop'},
        {execute => 'migrate', arguments => {uri => 'fd:dumpfd'}},
    ], 'expected QMP commands invoked' or diag explain $$invoked_qmp_cmds;
};

subtest 'misc functions' => sub {
    $backend->{proc}->_process(Test::MockObject->set_always(pid => $$));
    my $res = $backend->cpu_stat;
    is scalar @$res, 2, 'cpu_stat returns two values' or diag explain $res;
    ok looks_like_number($res->[$_]), "cpu_stat value $_ is a number" for (0, 1);

    $bmwqemu::vars{HDDMODEL} = 'nvme';
    is $backend->can_handle({function => 'snapshots'}), undef, 'NVMe snapshots not supported';

    $called{handle_qmp_command} = undef;
    $backend->set_migrate_capability('foo', 0);
    is_deeply $called{handle_qmp_command}, [{
            execute => 'migrate-set-capabilities',
            arguments => {capabilities => [{capability => 'foo', state => Mojo::JSON::false}]},
    }], 'expected QMP command called for "set_migrate_capability"' or diag explain $called{handle_qmp_command};

    $called{handle_qmp_command} = undef;
    $backend->open_file_and_send_fd_to_qemu("$Bin/$Script", 'foo');
    is_deeply $called{handle_qmp_command}, [{
            execute => 'getfd',
            arguments => {fdname => 'foo'},
    }], 'expected QMP command called for "open_file_and_send_fd_to_qemu"' or diag explain $called{handle_qmp_command};

    @bmwqemu::ovmf_locations = ('does not exist', "$Bin/$Script", 'does not exist either');
    is backend::qemu::find_ovmf, "$Bin/$Script", 'locating ovmf (normally "/usr/share/qemu/ovmf-x86_64-ms-code.bin")';
};

subtest 'saving memory dump' => sub {
    my $which_mock = Test::MockModule->new('File::Which')->redefine(which => 1);
    $mock_bmwqemu->unmock('fctwarn');

    $fake_qmp_answer = {return => {status => 'running'}};
    $called{handle_qmp_command} = undef;
    combined_like { $backend->save_memory_dump({filename => 'foo'}) } qr/memory dump completed/i, 'completion logged';
    is_deeply $called{handle_qmp_command}, [
        {execute => 'query-status'},
        {
            execute => 'migrate-set-capabilities',
            arguments => {capabilities => [{capability => 'events', state => Mojo::JSON->true}]},
        },
        {
            execute => 'migrate-set-parameters',
            arguments => {'compress-level' => 0, 'compress-threads' => 1, 'max-bandwidth' => '9223372036854775807'},
        },
        {execute => 'getfd', arguments => {fdname => 'dumpfd'}},
        {execute => 'stop'},
        {execute => 'migrate', arguments => {uri => 'fd:dumpfd'}},
        {execute => 'cont'},
    ], 'expected QMP command called for "save_memory_dump"' or diag explain $called{handle_qmp_command};
    is $runcmd, 'xz --no-warn -T 1 -v6 ulogs/foo-vm-memory-dump', 'expected compression command invoked';

    $which_mock->redefine(which => undef);
    combined_like { $backend->save_memory_dump({filename => 'foo'}) } qr/falling back to bzip2/i, 'fallback to bzip2 logged';
    is $runcmd, 'bzip2 -v6 ulogs/foo-vm-memory-dump', 'expected compression fallback command invoked';
};

subtest '"balloon" handling' => sub {
    $fake_qmp_answer = {return => {actual => 1}};
    $$invoked_qmp_cmds = undef;
    $backend->inflate_balloon;
    $backend->deflate_balloon;
    is_deeply $$invoked_qmp_cmds, undef, 'no QMP commands invoked without QEMU_BALLOON_TARGET' or diag explain $$invoked_qmp_cmds;

    $bmwqemu::vars{QEMU_BALLOON_TARGET} = 1;
    $backend->inflate_balloon;
    is_deeply $$invoked_qmp_cmds, [
        {execute => 'balloon', arguments => {value => 1048576}}, {execute => 'query-balloon'}, {execute => 'query-balloon'}
    ], 'expected QMP commands invoked when "inflating balloon"' or diag explain $$invoked_qmp_cmds;

    $$invoked_qmp_cmds = undef;
    $backend->deflate_balloon;
    is_deeply $$invoked_qmp_cmds, [
        {execute => 'balloon', arguments => {value => 1073741824}}    # QEMURAM * 1048576
    ], 'expected QMP commands invoked when "deflating balloon"' or diag explain $$invoked_qmp_cmds;
};

subtest 'snapshot handling' => sub {
    my @migrate_args;
    $backend_mock->redefine(_migrate_to_file => sub (@args) { push @migrate_args, \@args });
    $fake_qmp_answer = {return => {status => 'running'}};
    $bmwqemu::vars{QEMU_BALLOON_TARGET} = undef;
    $$invoked_qmp_cmds = undef;
    my $proc = $backend->{proc};
    $proc->snapshot_conf->add_snapshot('fakevm')->name('fakesnapshot');
    $proc->blockdev_conf->add_new_drive('some-id', 'some-model', 1024);
    combined_like { $backend->save_snapshot({name => 'fakevm'}) } qr/snapshot complete/i, 'completion logged (1)';
    my $snapshot_file = delete $$invoked_qmp_cmds->[2]->{arguments}->{'snapshot-file'};
    like $snapshot_file, qr{/raid/hd0-overlay1$}, 'snapshot file passed';
    is_deeply $$invoked_qmp_cmds, [
        {execute => 'query-status'},
        {execute => 'stop'},
        {execute => 'blockdev-snapshot-sync', arguments => {format => 'qcow2', 'node-name' => 'hd0', 'snapshot-node-name' => 'hd0-overlay1'}},
        {execute => 'blockdev-snapshot-sync', arguments => {
                format => 'qcow2', 'node-name' => 'some-id', 'snapshot-file' => "$dir/raid/some-id-overlay1", 'snapshot-node-name' => 'some-id-overlay1'},
        },
        {execute => 'cont'},
    ], 'expected QMP commands invoked when saving snapshot' or diag explain $$invoked_qmp_cmds;

    # save the snapshot again again assuming the blockdev-snapshot-sync call fails
    my %first_overlay = (
        execute => 'blockdev-snapshot-sync',
        # error handling adds "device" and removes "node-name"
        arguments => {device => 'hd0-overlay1', format => 'qcow2', 'snapshot-file' => "$dir/raid/hd0-overlay2", 'snapshot-node-name' => 'hd0-overlay2'},
    );
    my %second_overlay = (
        execute => 'blockdev-snapshot-sync',
        arguments => {device => 'some-id-overlay1', format => 'qcow2', 'snapshot-file' => "$dir/raid/some-id-overlay2", 'snapshot-node-name' => 'some-id-overlay2'}
    );
    $$invoked_qmp_cmds = undef;
    $fake_qmp_answer = {return => {status => 'running'}, error => 1};
    combined_like { $backend->save_snapshot({name => 'fakevm'}) } qr/snapshot complete/i, 'completion logged (2)';
    is_deeply $$invoked_qmp_cmds, [
        {execute => 'query-status'}, {execute => 'stop'}, \%first_overlay, \%first_overlay, \%second_overlay, \%second_overlay, {execute => 'cont'},
    ], 'expected QMP commands invoked when saving snapshot with error' or diag explain $$invoked_qmp_cmds;

    $$invoked_qmp_cmds = undef;
    combined_like { $backend->load_snapshot({name => 'fakevm'}) } qr/restored snapshot/i, 'restoration logged';
    is_deeply $$invoked_qmp_cmds, [
        {execute => 'query-status'},
        {execute => 'stop'},
        {execute => 'qmp_capabilities'},
        {execute => 'migrate-set-capabilities', arguments => {capabilities => [{capability => 'compress', state => Mojo::JSON->true}]}},
        {execute => 'migrate-set-capabilities', arguments => {capabilities => [{capability => 'events', state => Mojo::JSON->true}]}},
        {execute => 'migrate-incoming', arguments => {uri => 'exec:cat vm-snapshots/fakevm'}},
        {execute => 'cont'},
    ], 'expected QMP commands invoked when loading snapshot' or diag explain $$invoked_qmp_cmds;
};

subtest 'save storage' => sub {
    $bmwqemu::vars{QEMU_BALLOON_TARGET} = undef;
    $bmwqemu::vars{NAME} = 'FAKE_TEST';
    my $i = 0;
    my %running = (return => {status => 'running'});
    my %done = (return => []);
    my @fake_qmp_answer = (\%running, \%done, \%done, \%done, \%done, \%done, \%done, \%done);
    $backend_mock->unmock('handle_qmp_command');
    $mock_bmwqemu->unmock('diag');
    $backend_mock->redefine(handle_qmp_command => sub { push @{$called{handle_qmp_command}}, $_[1]; $fake_qmp_answer[$i++] });
    $$invoked_qmp_cmds = undef;
    combined_like { $backend->save_storage({filename => 'fakevm'}) } qr/Saving storage complete/i, 'completion logged (1)';
    is_deeply $$invoked_qmp_cmds, [
        {execute => 'query-status'},
        {execute => 'stop'},
        {arguments => {
                driver => 'qcow2',
                file => {
                    driver => 'file',
                    filename => 'assets_public/hd0-overlay2-fakevm-FAKE_TEST.qcow2'
                },
                'node-name' => 'hd0-overlay2-fakevm'
            },
            execute => 'blockdev-add'
        },
        {arguments => {
                device => 'hd0-overlay2',
                'job-id' => 'hd0-backup-fakevm',
                sync => 'full',
                target => 'hd0-overlay2-fakevm'
            },
            execute => 'blockdev-backup'
        },
        {execute => 'query-jobs'},
        {arguments => {
                driver => 'qcow2',
                file => {
                    driver => 'file',
                    filename => 'assets_public/some-id-overlay2-fakevm-FAKE_TEST.qcow2'
                },
                'node-name' => 'some-id-overlay2-fakevm'
            },
            execute => 'blockdev-add'
        },
        {arguments => {
                device => 'some-id-overlay2',
                'job-id' => 'some-id-backup-fakevm',
                sync => 'full',
                target => 'some-id-overlay2-fakevm'
            },
            execute => 'blockdev-backup'},
        {execute => 'query-jobs'},
        {execute => 'cont'}], 'excepted QMP commands when saving storage' or diag explain $$invoked_qmp_cmds;
    # timeout exceeded
    $bmwqemu::vars{SAVE_STORAGE_TIMEOUT} = 2;
    $i = 0;
    my %working = (return => [{s => 'r'}]);
    @fake_qmp_answer = (\%running, \%working, \%working, \%working, \%working, \%working, \%working, \%working);
    combined_like { throws_ok { $backend->save_storage({filename => 'failvm'}) } qr/Saving volume hd0-overlay2 exceeded the timeout/, 'die on timeout exceeed' } qr/current VM state is running/, 'exception happended in save_storage sub';
};

subtest 'special cases when starting QEMU' => sub {
    # set certain variables to test special handling for them that is not otherwise tested
    $bmwqemu::scriptdir = "$Bin/..";    # for dmi data
    $bmwqemu::vars{UEFI_PFLASH} = 1;
    $bmwqemu::vars{ARCH} = 'x86_64';
    $bmwqemu::vars{KERNEL} = 'linuxboot.bin';
    $bmwqemu::vars{LAPTOP} = '1';
    $bmwqemu::vars{BOOT_HDD_IMAGE} = 1;
    $bmwqemu::vars{MULTIPATH} = 1;
    $bmwqemu::vars{HDDMODEL} = '';
    $bmwqemu::vars{NICTYPE} = 'vde';
    $bmwqemu::vars{NICVLAN} = 'foovlan';
    $bmwqemu::vars{WORKER_ID} = 42;
    $bmwqemu::vars{VDE_USE_SLIRP} = 1;
    $bmwqemu::vars{KEEPHDDS} = 1;
    $bmwqemu::vars{NBF} = 1;
    $bmwqemu::vars{WORKER_HOSTNAME} = 1;
    $bmwqemu::vars{BOOT_MENU} = 1;
    $bmwqemu::vars{QEMU_NUMA} = 1;
    $bmwqemu::vars{QEMUCPUS} = 1;
    $bmwqemu::vars{DELAYED_START} = 1;
    $bmwqemu::vars{WORKER_CLASS} = 'qemu_aarch64';

    my ($pid, $load_state, @qemu_params);
    $backend_mock->redefine(_child_process => sub ($self, $coderef) { ++$pid });
    $proc->redefine(load_state => sub ($self) { ++$load_state });
    $proc->redefine(static_param => sub ($self, @params) { push @qemu_params, @params });
    $backend_mock->redefine(requires_audiodev => 0);

    my @invoked_cmds;
    $backend_mock->redefine(runcmd => sub (@cmd) { push @invoked_cmds, join(' ', @cmd) });
    combined_like { $backend->start_qemu } qr{UEFI_PFLASH and BIOS are deprecated.*slirpvde --dhcp -s ./vde.ctl --port 87 started with pid 1.*not starting CPU}s,
      'deprecation warning for UEFI_PFLASH/BIOS logged, slirpvde started, DELAYED_START logged';
    is $bmwqemu::vars{BIOS}, "$Bin/$Script", 'BIOS set to @bmwqemu::ovmf_locations for UEFI_PFLASH=1 and ARCH=x86_64';
    like $bmwqemu::vars{KERNEL}, qr{/.*/linuxboot\.bin}, 'KERNEL set to absolute location';
    is $bmwqemu::vars{LAPTOP}, 'hp_elitebook_820g1', 'default laptop model assigned for LAPTOP=1';
    is $bmwqemu::vars{BOOTFROM}, 'c', 'BOOTFROM defaults to "c" for BOOT_HDD_IMAGE=1';
    is $bmwqemu::vars{HDDMODEL}, 'scsi-hd', 'HDDMODEL set for MULTIPATH=1';
    is $bmwqemu::vars{PATHCNT}, 2, 'PATHCNT set for MULTIPATH=1';
    is $bmwqemu::vars{VDE_SOCKETDIR}, '.', 'VDE_SOCKETDIR set for NICTYPE=vde';
    is $bmwqemu::vars{VDE_PORT}, 86, 'VDE_PORT set for NICTYPE=vde';
    is $load_state, 1, 'load_state called once due to KEEPHDDS=1';
    my $qemu_params = Mojo::Collection->new(\@qemu_params)->flatten->join(' ');
    like $qemu_params, qr{smbios file=.*dmidata/hp_elitebook_820g1/smbios_type_1.bin}, 'smbios params present';
    like $qemu_params, qr{kernel /usr/share/.*/ipxe.lkrn}, 'ipxe kernel param for NBF=1 present';
    like $qemu_params, qr{menu=on,splash-time=\d+}, 'menu parameter present for BOOT_MENU=1';
    unlike $qemu_params, qr{order=}, 'order parameter not present despite BOOT_HDD_IMAGE=1 because UEFI=1';
    unlike $qemu_params, qr{\sbios}, 'bios parameter not present despite BIOS=1 because UEFI=1';
    like $qemu_params, qr{object memory-backend-ram,size=1024m,id=m0 numa node nodeid=0,memdev=m0,cpus=0}, 'numa parameters present for QEMU_NUMA=1/QEMUCPUS=1';
    is_deeply \@invoked_cmds, [
        'vdecmd -s ./vde.mgmt port/remove 86', 'vdecmd -s ./vde.mgmt port/create 86', 'vdecmd -s ./vde.mgmt vlan/create foovlan',
        'vdecmd -s ./vde.mgmt port/setvlan 86 foovlan', 'vdecmd -s ./vde.mgmt port/setvlan 87 foovlan',
        "swtpm socket --tpmstate dir=$dir/mytpm6 --ctrl type=unixio,path=$dir/mytpm6/swtpm-sock --log level=20 -d"
    ], 'vde and swtpm commands invoked' or diag explain \@invoked_cmds;

    # set different parameters to test more cases
    $bmwqemu::vars{UEFI} = $bmwqemu::vars{UEFI_PFLASH} = 0;
    $bmwqemu::vars{NICTYPE} = 'tap';
    $bmwqemu::vars{DELAYED_START} = 0;
    $bmwqemu::vars{OVS_DEBUG} = 1;
    $bmwqemu::vars{WORKER_CLASS} = '';
    $bmwqemu::vars{BOOTFROM} = 'cdrom';

    my $process_mock = Test::MockObject->new;
    my %callbacks;
    $process_mock->set_always(emit => 1);
    $process_mock->mock(on => sub ($self, $event_name, $function) { $callbacks{$event_name} = $function });
    my @dbus_invocations;
    $backend_mock->redefine(_dbus_call => sub (@args) { push @dbus_invocations, \@args });
    $backend->{proc}->_process($process_mock);
    @qemu_params = ();
    combined_like { $backend->start_qemu } qr{.*}s, 'invoked with tap';

    $qemu_params = Mojo::Collection->new(\@qemu_params)->flatten->join(' ');
    like $qemu_params, qr{tap id=qanet0 ifname=tap2 script=no downscript=no}, 'parameters for NICTYPE=tap present';
    like $qemu_params, qr{order=}, 'order parameter present due to BOOT_HDD_IMAGE=1 and UEFI=0';
    like $qemu_params, qr{\sbios}, 'bios parameter present due to BIOS=1 and UEFI=0';
    is $bmwqemu::vars{BOOTFROM}, 'd', 'BOOTFROM set to "d" for "cdrom"';
    is scalar @dbus_invocations, 2, 'two D-Bus invocatios made';
    is_deeply $dbus_invocations[0], [$backend, set_vlan => 'tap2', 'foovlan'], 'vlan set for tap device via D-Bus call' or diag explain \@dbus_invocations;
    is_deeply $dbus_invocations[1], [$backend, 'show'], 'networking status shown for OVS_DEBUG=1' or diag explain \@dbus_invocations;
    if (is ref $callbacks{cleanup}, 'CODE', 'cleanup callback set') {
        $callbacks{cleanup}->();
        is_deeply $dbus_invocations[2], [$backend, unset_vlan => 'tap2', 'foovlan'], 'vlan unset in cleanup handler via D-Bus call';
    }
    if (is ref $callbacks{collected}, 'CODE', 'collected callback set') {
        $callbacks{collected}->();
        $process_mock->called_pos_ok(3, 'emit', 'emit called');
        $process_mock->called_args_pos_is(3, 2, 'cleanup', 'cleanup event emitted');
    }

    # set different parameters to test remaining cases
    @qemu_params = ();
    $bmwqemu::vars{PXEBOOT} = 'once';
    combined_like { $backend->start_qemu } qr{.+}s, 'invoked with PXEBOOT=once';
    $qemu_params = Mojo::Collection->new(\@qemu_params)->flatten->join(' ');
    unlike $qemu_params, qr{order=}, 'order parameter not present due to PXEBOOT';
    like $qemu_params, qr{once=n}, 'once=n parameter present due to PXEBOOT';

    subtest 'various error cases' => sub {
        my %initial_vars = %bmwqemu::vars;
        $bmwqemu::vars{NICTYPE} = 'foo';
        combined_like { throws_ok { $backend->start_qemu } qr/unknown NICTYPE foo/, 'dies on unknown NICTYPE' }
          qr/qemu version.*Initializing block device images/si, 'expected logs until exception thrown (1)';
        $bmwqemu::vars{BOOTFROM} = 'punch-card';
        combined_like { throws_ok { $backend->start_qemu } qr{unsupported boot order: punch-card}, 'dies on unsupported boot order' }
          qr/qemu version/si, 'expected logs until exception thrown (2)';
        $bmwqemu::vars{LAPTOP} = '..';
        combined_like { throws_ok { $backend->start_qemu } qr{invalid characters in LAPTOP}, 'dies on invalid characters in LAPTOP' }
          qr/qemu version/si, 'expected logs until exception thrown (3)';
        $bmwqemu::vars{LAPTOP} = 'auslaufmoDELL';
        combined_like { throws_ok { $backend->start_qemu } qr{no dmi data for 'auslaufmoDELL'}, 'dies on unknown LAPTOP' }
          qr/qemu version/si, 'expected logs until exception thrown (4)';
        $bmwqemu::vars{KERNEL} = 'does-not-exist';
        combined_like { throws_ok { $backend->start_qemu } qr{'/.*/does-not-exist' missing, check KERNEL}, 'dies on non-existant BOOT/KERNEL/INITRD' }
          qr/qemu version/si, 'expected logs until exception thrown (5)';
        $bmwqemu::vars{UEFI_PFLASH} = 0;
        $bmwqemu::vars{UEFI} = 1;
        $bmwqemu::vars{UEFI_PFLASH_CODE} = 0;
        combined_like { throws_ok { $backend->start_qemu } qr{No UEFI firmware can be found}, 'dies if UEFI firmware not found' }
          qr/qemu version/si, 'expected logs until exception thrown (6)';
        %bmwqemu::vars = %initial_vars;
        combined_like { qemu_cmdline(UEFI => 1, UEFI_PFLASH_CODE => '/OVMF_CODE.fd') }
        qr/qemu version/si, 'expected logs until exception thrown (7)';
        is $bmwqemu::vars{UEFI_PFLASH_VARS}, '/OVMF_VARS.fd', 'default UEFI_PFLASH_VARS was guessed correctly';
    };
};

subtest 'special cases when handling QMP command' => sub {
    my $create_virtio_console_fifo_called;
    # uncoverable statement count:2
    # uncoverable statement count:3
    # uncoverable statement count:4
    $backend_mock->redefine(create_virtio_console_fifo => sub () { ++$create_virtio_console_fifo_called });
    $backend_mock->unmock('handle_qmp_command');
    $bmwqemu::vars{QEMU_ONLY_EXEC} = 1;
    combined_like { is $backend->handle_qmp_command('foo'), undef, 'handling skipped via QEMU_ONLY_EXEC' }
    qr/Skipping.*because QEMU_ONLY_EXEC/, 'skipping logged';
};

done_testing();
