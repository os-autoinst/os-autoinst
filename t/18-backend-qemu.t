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

subtest 'setting graphics backend' => sub {
    my @params;
    local *backend::qemu::sp = sub (@args) { @params = @args };
    $backend->_set_graphics_backend;
    is_deeply \@params, [device => 'VGA,edid=on,xres=1024,yres=768'], 'consistent EDID info set for std backend (no QEMUVGA set)' or diag explain \@params;

    $bmwqemu::vars{QEMUVGA} = 'virtio';
    $backend->_set_graphics_backend;
    is_deeply \@params, [device => 'virtio-vga,edid=on,xres=1024,yres=768'], 'consistent EDID info set for virtio backend' or diag explain \@params;

    $bmwqemu::vars{QEMUVGA} = 'cirrus';
    $backend->_set_graphics_backend;
    is_deeply \@params, [vga => 'cirrus'], 'other backends passes as-is via "-vga" parameter' or diag explain \@params;
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

like qemu_cmdline(OFW => 1, XRES => 640, YRES => 480), qr/-g 640x480/, 'res is set for ppc/sparc';
like qemu_cmdline(OFW => 1), qr/cap-cfpc=broken/, 'OFW workarounds applied';

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
};

done_testing();
