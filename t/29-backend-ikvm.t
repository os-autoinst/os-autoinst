#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;

use Test::MockModule;
use Test::Mock::Time;
use Test::Output qw(stderr_like);
use Test::Warnings qw(:report_warnings);
use Test::Fatal;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Scalar::Util qw(blessed);

use backend::ikvm;    # SUT

$bmwqemu::vars{WORKER_HOSTNAME} = 'localhost';
like(exception { backend::ikvm->new }, qr/DEPRECATED/, 'deprecated backend dies by default');
$bmwqemu::vars{NO_DEPRECATE_BACKEND_IKVM} = 1;
$bmwqemu::vars{IPMI_HW} = 1;
my $backend;
stderr_like { $backend = backend::ikvm->new } qr/DEPRECATED/, 'backend can be created but is deprecated';
my $distri = Test::MockModule->new('distribution');
$testapi::distri = distribution->new;
ok $backend->relogin_vnc, 'relogin_vnc returns truthy value';
like(exception { $backend->do_start_vm }, qr/Need variable IPMI/, 'do_start_vm needs IPMI parameters');

my $sut_console = $testapi::distri->{consoles}->{sut};
is blessed $sut_console, 'consoles::vnc_base', 'VNC console added';

my $ikvm_mock = Test::MockModule->new('backend::ikvm');
my $ipmi_mock = Test::MockModule->new('backend::ipmi');
my $ipmi_sol_mock = Test::MockModule->new('consoles::ipmiSol');
my (%ikvm_invocations, @ipmi_invocations, %ipmi_sol_invocations);
$ikvm_mock->redefine(relogin_vnc => sub ($self) { ++$ikvm_invocations{relogin_vnc} });
$ikvm_mock->redefine(truncate_serial_file => sub ($self) { ++$ikvm_invocations{truncate_serial_file} });
$ipmi_mock->redefine(ipmitool => sub ($self, $cmd, %args) { push @ipmi_invocations, [$cmd => \%args]; 'is on is off' });
$ipmi_sol_mock->redefine(activate => sub ($self) { ++$ipmi_sol_invocations{activate} });
$bmwqemu::vars{IPMI_HOSTNAME} = 'foobar';
$bmwqemu::vars{IPMI_PASSWORD} = '123456';
$bmwqemu::vars{IPMI_USER} = 'ADMIN';

subtest 'starting VM' => sub {
    $backend->do_start_vm;
    is_deeply \%ikvm_invocations, {relogin_vnc => 1, truncate_serial_file => 1}, 'expected ikvm backend functions called'
      or diag explain \%ikvm_invocations;
    is_deeply \@ipmi_invocations, [
        ['mc guid' => {}], ['mc info' => {}], ['mc selftest' => {}], ['chassis power status' => {tries => 3}],
        ['chassis power on' => {}], ['chassis power status' => {tries => 3}]
      ], 'expected ipmi commands invoked'
      or diag explain \@ipmi_invocations;
    is_deeply \%ipmi_sol_invocations, {activate => 1}, 'expected ikvm SOL console functions called' or diag explain \%ipmi_sol_invocations;
};

subtest 'stopping VM' => sub {
    (%ikvm_invocations, @ipmi_invocations, %ipmi_sol_invocations) = ();
    $backend->do_stop_vm;
    is_deeply \%ikvm_invocations, {}, 'expected ikvm backend functions called' or diag explain \%ikvm_invocations;
    is_deeply \@ipmi_invocations, [['chassis power off' => {}]], 'expected ipmi commands invoked' or diag explain \@ipmi_invocations;
    is_deeply \%ipmi_sol_invocations, {}, 'expected ikvm SOL console functions called' or diag explain \%ipmi_sol_invocations;
};

done_testing;
