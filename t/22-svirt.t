#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
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

subtest 'SSH usage in console::sshVirtsh' => sub {
    # Check console::sshVirtsh
    my $ssh_creds_svirt    = {hostname => 'hostname_svirt', password => 'password_svirt', username => 'root'};
    my %ssh_expect         = (%$ssh_creds_svirt, wantarray => undef, keep_open => undef);
    my $run_ssh_cmd_return = undef;
    my $mock_baseclass     = Test::MockModule->new('backend::baseclass');
    $mock_baseclass->redefine('run_ssh_cmd' => sub {
            my ($self, $cmd, %args) = @_;
            for my $key (keys(%ssh_expect)) {
                is($args{$key}, $ssh_expect{$key}, "Correct $key for ssh connection") if $ssh_expect{$key};
            }
            if (ref($run_ssh_cmd_return) eq 'ARRAY') {
                return @$run_ssh_cmd_return;
            } else {
                return $run_ssh_cmd_return;
            }
    });

    # W/A cause $svirt_console->activate() didn't worked so far
    $svirt_console->_init_ssh($ssh_creds_svirt);
    $run_ssh_cmd_return = 0;
    is($svirt_console->run_cmd('echo "BLAFAFU"'), 0, "sshVirtsh::run_cmd() test return value");

    $run_ssh_cmd_return = [0, 'BLAFAFU', ''];
    $ssh_expect{wantarray} = 1;
    is_deeply([$svirt_console->run_cmd('echo -n "BLAFAFU"', wantarray => 1)], $run_ssh_cmd_return, "sshVirtsh::run_cmd_(wantarray => 1) ");

    $run_ssh_cmd_return = [undef, 'BLAFAFU', undef];
    is($svirt_console->get_cmd_output('echo -n "BLAFAFU"'), 'BLAFAFU', "sshVirtsh::get_cmd_output()");

    $run_ssh_cmd_return = [undef, 'STDOUT', 'STDERR'];
    is_deeply($svirt_console->get_cmd_output('echo -n "BLAFAFU"', {wantarray => 1}), ['STDOUT', 'STDERR'], "sshVirtsh::get_cmd_output(wantarray => 1 ");
    $ssh_expect{wantarray} = undef;

    $ssh_expect{keep_open} = 0;
    $run_ssh_cmd_return = 0;
    is($svirt_console->run_cmd('echo "BLAFAFU"', keep_open => 0), 0, "sshVirtsh::run_cmd(keep_open=>0) test return value ");
    $ssh_expect{keep_open} = undef;

    subtest 'SSH usage in consoles::sshVirtsh(vmware)' => sub {
        set_var('VMWARE_HOST',      'my_vmware_host');
        set_var('VMWARE_PASSWORD',  'my_vmware_password');
        set_var('VIRSH_VMM_FAMILY', 'vmware');

        my $svirt_vmware_console = consoles::sshVirtsh->new('svirt');
        $svirt_vmware_console->_init_ssh($ssh_creds_svirt);
        $svirt_vmware_console->backend(backend::baseclass->new);

        is($svirt_vmware_console->run_cmd('echo "BLAFAFU"'), 0, "sshVirtsh::run_cmd() Check use of `default` credentials");

        $run_ssh_cmd_return = [undef, 'STDOUT', undef];
        is_deeply($svirt_console->get_cmd_output('echo -n "BLAFAFU"'), 'STDOUT', "sshVirtsh::get_cmd_output() Check use of `default` credentials");

        $ssh_expect{hostname} = 'my_vmware_host';
        $ssh_expect{password} = 'my_vmware_password';
        $run_ssh_cmd_return   = 0;
        is($svirt_vmware_console->run_cmd('echo "BLAFAFU"', domain => 'sshVMwareServer'), 0, "sshVirtsh::run_cmd(domain => sshVMwareServer) check use of VMWARE credentials ");

        $run_ssh_cmd_return = [undef, 'STDOUT', undef];
        is_deeply($svirt_vmware_console->get_cmd_output('echo -n "BLAFAFU"', {domain => 'sshVMwareServer'}), 'STDOUT', "sshVirtsh::get_cmd_output() Check use of VMWARE credentials");
    }
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
