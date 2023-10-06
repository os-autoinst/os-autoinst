#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Mock::Time;
use Test::MockModule;
use Test::MockObject;
use Test::Output qw(combined_like stderr_like);
use Test::Warnings qw(:all :report_warnings);

BEGIN { *backend::ipmi::system = sub { 1 } }
BEGIN { *consoles::localXvnc::system = sub { "@_" =~ /hardware-console-log/ ? 1 : 0 } }

use backend::ipmi;    # SUT

$bmwqemu::vars{WORKER_HOSTNAME} = 'localhost';
$bmwqemu::vars{"HARDWARE_CONSOLE_LOG"} = 1;
ok my $backend = backend::ipmi->new(), 'backend can be created';
$bmwqemu::vars{"IPMI_$_"} = "fake_$_" foreach qw(HOSTNAME USER PASSWORD);
my @ipmi_cmdline = $backend->ipmi_cmdline;
is_deeply \@ipmi_cmdline, [qw(ipmitool -I lanplus -H fake_HOSTNAME -U fake_USER -P fake_PASSWORD)], 'valid ipmi_cmdline';

my $ipmi = Test::MockModule->new('backend::ipmi');
throws_ok { $backend->ipmitool('foo') } qr/[masked]/, 'ipmi password masked in error output';
$ipmi->redefine(ipmi_cmdline => sub { (qw(echo simulating ipmi)) });
my $ret;
combined_like { $ret = $backend->ipmitool('foo') } qr/IPMI: simulating ipmi foo/, 'log output for IPMI call';
is $ret, 'simulating ipmi foo', 'can call ipmitool';
ok !$backend->dell_sleep, 'dell_sleep would only work on special HW';
$bmwqemu::vars{IPMI_HW} = 'dell';
ok $backend->dell_sleep, 'dell_sleep called with dell hw is effective';
combined_like { $ret = $backend->is_shutdown } qr/IPMI.*power status/, 'log output for is_shutdown';
ok !$ret, 'is_shutdown returning false by default';
my $ipmitool_mock = Test::MockObject->new();
$ipmitool_mock->set_series('ipmitool', 'is on', 'foo', 'is on', 'is off', 'foo', 'is off', 'is on');
$ipmi->redefine(ipmitool => sub { $_[1] =~ /power status/ ? $ipmitool_mock->ipmitool : 'NOT POWER STATUS' });
ok $backend->restart_host, 'can call restart_host';
$ipmi->noop('ipmitool');
my $distri = Test::MockModule->new('distribution');
$testapi::distri = distribution->new;

ok $backend->do_start_vm, 'can call do_start_vm';
ok $backend->do_stop_vm, 'can call do_stop_vm';
ok !$backend->check_socket(undef), 'check_socket not returning true by default';
ok $backend->get_mc_status, 'can call get_mc_status';

is $testapi::distri->{consoles}->{sol}->{args}->{log}, '1';
$testapi::distri->{consoles}->{sol}->{DISPLAY} = "display";
ok !$testapi::distri->{consoles}->{sol}->callxterm('ipmi', "console"), "can create console with log enabled";

subtest 'cold reset' => sub {
    # reduce retries for testing
    $bmwqemu::vars{IPMI_MC_RESET_MAX_TRIES} = $bmwqemu::vars{IPMI_MC_RESET_TIMEOUT} = 3;
    combined_like { $backend->do_mc_reset } qr/IPMI mc reset success/, 'can call do_mc_reset';

    $ipmi->redefine(ipmitool => sub { die 'fake error' });
    throws_ok { combined_like { $backend->do_mc_reset } qr/IPMI mc reset failure: fake error/, 'error logged' }
      qr/IPMI mc reset failure after 3 tries/, 'dies when retries exhausted';
};

subtest 'dell sleep' => sub {
    my $ipc_run_mock = Test::MockModule->new('IPC::Run');
    $ipc_run_mock->redefine(run => sub ($cmd, $stdin, $stdout, $stderr) { $$stdin = 'in', $$stdout = 'out', $$stderr = 'err'; return 0 });
    $ipmi->unmock('ipmitool');
    $bmwqemu::vars{IPMI_HW} = 'dell';
    my $start = time;
    throws_ok { $backend->ipmitool('foo') } qr/ipmi foo: err/, 'error logged';
    is time, $start + 4, 'slept 4 seconds';
};

done_testing;

END {
    unlink 'serial0';
}
