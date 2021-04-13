#!/usr/bin/perl

use Test::Most;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::MockModule;
use Test::MockObject;
use Test::Warnings ':report_warnings';
use Test::Output;
use Mojo::Log;
use XML::SemanticDiff;
use backend::svirt;
use distribution;
use Net::SSH2;
use testapi qw(get_var get_required_var check_var set_var);
use backend::svirt qw(SERIAL_CONSOLE_DEFAULT_PORT SERIAL_TERMINAL_DEFAULT_DEVICE SERIAL_TERMINAL_DEFAULT_PORT);
use Mojo::File 'tempdir';
use Mojo::Util qw(scope_guard);

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };
mkdir 'testresults';

bmwqemu::init_logger;

set_var(WORKER_HOSTNAME => 'foo');
set_var(VIRSH_HOSTNAME  => 'bar');
set_var(VIRSH_PASSWORD  => 'password');

my $distri = $testapi::distri = distribution->new();
my $svirt  = backend::svirt->new();

is_deeply({$svirt->get_ssh_credentials()}, {
        hostname => 'bar',
        username => 'root',
        password => 'password',
}, 'read credentials');

$svirt->do_start_vm;
$distri->add_console('sut-serial', 'ssh-virtsh-serial', {});

my $consoles          = $distri->{consoles};
my $svirt_console     = $consoles->{svirt};
my $svirt_sut_console = $consoles->{'sut-serial'};

subtest 'svirt console correctly initialized' => sub {
    ok($svirt_console);
    is($svirt_console->{class},           'consoles::sshVirtsh');
    is($svirt_console->{backend},         $svirt);
    is($svirt_console->{name},            'openQA-SUT-1');
    is($svirt_console->{testapi_console}, 'svirt');
    is($svirt_console->{instance},        1);
    is($svirt_console->{vmm_family},      'kvm');
    is($svirt_console->{vmm_type},        'hvm');
};

is_deeply($svirt_sut_console, {
        activated       => 0,
        args            => {},
        class           => 'consoles::sshVirtshSUT',
        console_hotkey  => 'ctrl-alt-f',
        libvirt_domain  => 'openQA-SUT-1',
        serial_port_no  => 1,
        testapi_console => 'sut-serial',
        pty_dev         => SERIAL_TERMINAL_DEFAULT_DEVICE,
}, 'SUT serial console correctly initialized') or diag explain $consoles;

subtest 'XML config for VNC and serial console' => sub {
    $svirt_console->_init_xml();
    $svirt_console->add_vnc({port        => 5901});
    $svirt_console->add_pty({target_port => SERIAL_CONSOLE_DEFAULT_PORT});
    $svirt_console->add_pty({pty_dev     => SERIAL_TERMINAL_DEFAULT_DEVICE, pty_dev_type => 'pty', target_port => SERIAL_TERMINAL_DEFAULT_PORT});

    my $produced_xml = $svirt_console->{domainxml}->toString(2);
    my $expected_xml = "$Bin/22-svirth-virsh-config.xml";

    my $diff = XML::SemanticDiff->new(keeplinenums => 1);
    if (my @changes = $diff->compare($produced_xml, $expected_xml)) {
        fail('XML not as expected');
        note('differences:');
        diag explain \@changes;
        note('produced XML:');
        note($produced_xml);
    }
    else {
        ok('XML looks as expected');
    }
};

subtest 'SSH credentials' => sub {

    set_var('VIRSH_GUEST',          'foo321');
    set_var('VIRSH_GUEST_PASSWORD', 'password321');
    set_var('VIRSH_VMM_FAMILY',     'hyperv');
    my $svirt = backend::svirt->new();

    my %creds = $svirt->get_ssh_credentials();
    is_deeply(\%creds, {hostname => 'bar', password => 'password', username => 'root'}, 'Check SSH credentials');

    %creds = $svirt->get_ssh_credentials('hyperv');
    is_deeply(\%creds, {hostname => 'foo321', password => 'password321', username => 'root'}, 'Check SSH credentials for hyperv');
};

subtest 'SSH usage in svirt' => sub {
    my $ssh_expect_credentials = {username => 'root', password => 'password'};
    my $ssh_obj_data           = {};                                             # used to store Net::SSH2 fake data per object
    my $net_ssh2               = Test::MockModule->new('Net::SSH2');
    $net_ssh2->redefine(new => sub {
            my ($class, %opts) = @_;
            my $self = bless {}, $class;
            my $id   = $self->{my_custom_id} = bmwqemu::random_string(32);
            die 'Identifier not unique' if exists $ssh_obj_data->{$id};
            $ssh_obj_data->{$id} = {};
            return $self;
    });
    sub refaddr { return shift->{my_custom_id}; }
    $net_ssh2->noop('DESTROY');
    $net_ssh2->redefine(connect => sub {
            my $self = shift;
            $ssh_obj_data->{refaddr($self)}->{connected} = 1;
            $ssh_obj_data->{refaddr($self)}->{blocking}  = 0;
            return 1;
    });
    $net_ssh2->redefine(auth => sub {
            my ($self, %args) = @_;
            is($args{username}, $ssh_expect_credentials->{username}, 'Correct username for ssh connection');
            is($args{password}, $ssh_expect_credentials->{password}, 'Correct password for ssh connection');
            return 1;
    });
    $net_ssh2->redefine(auth_ok => sub { return 1; });
    $net_ssh2->redefine(blocking => sub {
            my ($self, $v);
            $ssh_obj_data->{refaddr($self)}->{blocking} = $v if defined($v);
            return $self->{blocking};
    });
    $net_ssh2->redefine(disconnect => sub {
            $ssh_obj_data->{refaddr(shift)}->{connected} = 0;
            return 1;
    });
    $net_ssh2->redefine(channel => sub {
            my $self = shift;
            die("Not connected") unless ($ssh_obj_data->{refaddr($self)}->{connected});
            my $mock_channel = Test::MockObject->new();
            $mock_channel->{ssh} = $self;
            $mock_channel->mock(exec => sub {
                    my ($self, $cmd) = @_;
                    $self->{cmd} = $cmd;
                    $self->{eof} = 0;
                    if ($cmd =~ /^(echo|test)/) {
                        $self->{stdout}      = `$cmd`;
                        $self->{exit_status} = $?;
                        $self->{stderr}      = '';
                    }
                    return 1;
            });
            $mock_channel->mock(read2 => sub {
                    my ($self) = @_;
                    $self->{eof} = 1;
                    return ($self->{stdout}, $self->{stderr});
            });
            $mock_channel->mock(eof         => sub { return shift->{eof}; });
            $mock_channel->mock(blocking    => sub { return shift->{ssh}->blocking(shift) });
            $mock_channel->mock(pty         => sub { return 1; });
            $mock_channel->mock(send_eof    => sub { return 1; });
            $mock_channel->mock(exit_status => sub { shift->{exit_status}; });
    });

    # check connection handling
    my $ssh1 = $svirt->new_ssh_connection();
    my ($ssh2, $ssh3, $ssh4);
    my $exp_log        = qr/SSH connection to root\@bar established/;
    my $default_logger = $bmwqemu::logger;
    $bmwqemu::logger = Mojo::Log->new(level => 'debug');
    stderr_like { $ssh2 = $svirt->new_ssh_connection() } $exp_log, 'New SSH connection announced in logs';
    stderr_like { $ssh3 = $svirt->new_ssh_connection(keep_open => 1) } $exp_log, 'New SSH connection announced in logs';
    stderr_unlike { $ssh4 = $svirt->new_ssh_connection(keep_open => 1) } $exp_log, 'No new SSH connection announced, if it already exists';
    $bmwqemu::logger = $default_logger;
    $ssh_expect_credentials->{username} = 'foo911';
    my $ssh5 = $svirt->new_ssh_connection(keep_open => 1, username => 'foo911');
    $ssh_expect_credentials->{username} = 'root';
    isnt(refaddr($ssh1), refaddr($ssh2), "Got new connection each call");
    is(refaddr($ssh3), refaddr($ssh4), "Got same connection with keep_open");
    isnt(refaddr($ssh4), refaddr($ssh5), "Got new connection with different credentials");

    $net_ssh2->redefine(auth_ok => sub { return 0; });
    throws_ok(sub { $svirt->new_ssh_connection() }, qr/Error connecting to/, 'Got exception on connection error');
    $net_ssh2->redefine(auth_ok => sub { return 1; });

    # check run_ssh_cmd() usage
    is($svirt->run_ssh_cmd('echo -n "foo"'), 0, 'Command successful exit');
    isnt($svirt->run_ssh_cmd('test 23 -eq 42'), 0, 'Command failed exit');
    my @output = $svirt->run_ssh_cmd('echo -n "foo"', wantarray => 1);
    is_deeply(\@output, [0, 'foo', ''], 'Command successful exit with output');
    # Check more complicated command (like those we execute against Hyper-V on Windows
    my $ps = 'echo powershell -Command';
    is($svirt->run_ssh_cmd(qq($ps "\$ProgressPreference='SilentlyContinue'; Remove-VM -Force -VMName Test-VM-1")), 0, 'Hyper-V command successful exit');

    $ssh_expect_credentials->{password} = '2+3=5';
    is($svirt->run_ssh_cmd('echo -n "foo"', password => '2+3=5'), 0, 'Allow SSH credentials per run_ssh_cmd() call');

    my $num_ssh_connect = scalar(keys(%{$ssh_obj_data}));
    $svirt->run_ssh_cmd('echo -n "foo"', password => '2+3=5', keep_open => 0);
    is(scalar(keys(%{$ssh_obj_data})), $num_ssh_connect + 1, 'Ensure run_ssh_cmd(keep_open => 0) uses a new SSH connection');

    # cleanup kept ssh connections
    for my $ssh_ref ((refaddr($ssh3), refaddr($ssh4), refaddr($ssh5))) {
        is($ssh_obj_data->{$ssh_ref}->{connected}, 1, "SSH connection $ssh_ref connected");
    }
    $svirt->close_ssh_connections();
    is(scalar(keys(%{$svirt->{ssh_connections}})), 0, "Cleanup ssh connections");
    for my $ssh_ref ((refaddr($ssh3), refaddr($ssh4), refaddr($ssh5))) {
        is($ssh_obj_data->{$ssh_ref}->{connected}, 0, "SSH connection $ssh_ref is disconnected");
    }

    # Check console::sshVirtsh
    my $ssh_creds_svirt = {hostname => 'hostname_svirt', password => 'password_svirt'};
    # W/A cause $svirt_console->activate() didn't worked so far
    $svirt_console->_init_ssh($ssh_creds_svirt);
    %{$ssh_expect_credentials} = (%{$ssh_expect_credentials}, %{$ssh_creds_svirt});
    is($svirt_console->run_cmd('echo "BLAFAFU"'), 0, "sshVirtsh::run_cmd() test return value");
    $num_ssh_connect = scalar(keys(%{$ssh_obj_data}));
    is($svirt_console->run_cmd('echo "BLAFAFU"'), 0,                "sshVirtsh::run_cmd() test return value [2]");
    is(scalar(keys(%{$ssh_obj_data})),            $num_ssh_connect, "sshVirtsh::run_cmd() _no_ new ssh connection created");
    is_deeply([$svirt_console->run_cmd('echo -n "BLAFAFU"', wantarray => 1)], [0, 'BLAFAFU', ''], "sshVirtsh::run_cmd_(wantarray => 1) ");
    is($svirt_console->get_cmd_output('echo -n "BLAFAFU"'), 'BLAFAFU', "sshVirtsh::get_cmd_output()");
    is_deeply($svirt_console->get_cmd_output('echo -n "BLAFAFU"', {wantarray => 1}), ['BLAFAFU', ''], "sshVirtsh::get_cmd_output(wantarray => 1 ");

    $num_ssh_connect = scalar(keys(%{$ssh_obj_data}));
    is($svirt_console->run_cmd('echo "BLAFAFU"', keep_open => 0), 0,                    "sshVirtsh::run_cmd(keep_open=>0) test return value ");
    is(scalar(keys(%{$ssh_obj_data})),                            $num_ssh_connect + 1, "sshVirtsh::run_cmd(keep_open=>0) new ssh object created");
};

subtest 'Method backend::svirt::open_serial_console_via_ssh()' => sub {
    my $module = Test::MockModule->new('backend::baseclass');
    my @LAST_;
    my $test_log_cnt = 0;
    my $grep_return  = 1;
    my @deleted_logs;
    $module->redefine(run_ssh_cmd => sub {
            my $self = shift;
            @LAST_ = @_;
            my $cmd = shift;
            return !!($test_log_cnt > 0 ? --$test_log_cnt : 0) if ($cmd =~ m/^test -e/);
            return $grep_return                                if ($cmd =~ m/^grep -q/);
            push @deleted_logs, ($cmd =~ /(\S+)$/)             if ($cmd =~ / && rm /);
            return (0, "FOOBAR_OUTPUT", '')                    if ($cmd =~ m/^cat /);
            die("Adopt test, unexpected call of run_ssh_cmd()");
    });

    my $run_ssh_expect = '$a';
    $module->redefine(run_ssh => sub {
            my ($self, $cmd, %args) = @_;
            like($cmd, qr/$run_ssh_expect/, "run_ssh() command is like qr/$run_ssh_expect/");
            return ('A', 'B');
    });

    delete $bmwqemu::vars{VIRSH_VMM_FAMILY};
    $bmwqemu::vars{JOBTOKEN} = 'XYZ23';

    my $svirt = backend::svirt->new();
    $run_ssh_expect = 'virsh console NAME\s+;';
    $svirt->open_serial_console_via_ssh('NAME');

    $run_ssh_expect = 'virsh console NAME DEV\s*;';
    $svirt->open_serial_console_via_ssh('NAME', devname => 'DEV');
    $run_ssh_expect = 'virsh console NAME DEV666\s*;';
    $svirt->open_serial_console_via_ssh('NAME', devname => 'DEV', port => 666);
    $run_ssh_expect = 'virsh console NAME 666\s*;';
    $svirt->open_serial_console_via_ssh('NAME', port => 666);

    $bmwqemu::vars{VIRSH_VMM_FAMILY} = 'vmware';
    $bmwqemu::vars{VMWARE_HOST}      = 'my.vmware.host';
    $run_ssh_expect                  = 'socat - TCP4:my.vmware.host:,crnl;';
    $svirt->open_serial_console_via_ssh('NAME');
    $run_ssh_expect = 'socat - TCP4:my.vmware.host:666,crnl;';
    $svirt->open_serial_console_via_ssh('NAME', port => 666);

    $bmwqemu::vars{VIRSH_VMM_FAMILY} = 'hyperv';
    $bmwqemu::vars{HYPERV_SERVER}    = 'my.hyperv.server';
    $run_ssh_expect                  = 'socat - TCP4:my.hyperv.server:,crnl;';
    $svirt->open_serial_console_via_ssh('NAME');
    $run_ssh_expect = 'socat - TCP4:my.hyperv.server:666,crnl;';
    $svirt->open_serial_console_via_ssh('NAME', port => 666);

    # Disable command check, as we do not care anymore
    $module->redefine(run_ssh => sub { return ('A', 'B') });
    is_deeply([$svirt->open_serial_console_via_ssh('NAME')], ['A', 'B'], 'Check that we get output from run_ssh() call');

    $bmwqemu::vars{JOBTOKEN} = 'CHECK_DELETE_TOKEN';
    my $expected_serial_file = '/tmp/' . $svirt->SERIAL_TERMINAL_LOG_PATH . '.CHECK_DELETE_TOKEN';
    $test_log_cnt = 11;
    dies_ok(sub { $svirt->open_serial_console_via_ssh('NAME') }, "die() when log file wasn't created");
    is(shift @deleted_logs, $expected_serial_file, "Check if $expected_serial_file was deleted on die()");

    $test_log_cnt = 0;
    $grep_return  = 0;
    dies_ok(sub { $svirt->open_serial_console_via_ssh('NAME') }, 'die() when emulate CONSOLE_EXIT token in log file');
    is(shift @deleted_logs, $expected_serial_file, "Check if $expected_serial_file was deleted on die()");
};

done_testing;
