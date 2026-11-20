#!/usr/bin/perl

use Test::Most;

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::MockObject;
use Test::MockModule;
use Test::Output qw(combined_like);
use Test::Warnings qw(:all :report_warnings);
use Mojo::File qw(tempfile);
use Scalar::Util qw(blessed);

use backend::s390x;    # SUT
use distribution;
use testapi;

$bmwqemu::vars{WORKER_HOSTNAME} = 'localhost';
$bmwqemu::vars{ZVM_HOST} = 'localhost';
$bmwqemu::vars{ZVM_GUEST} = 'guest';
$bmwqemu::vars{ZVM_PASSWORD} = 'password';
ok my $backend = backend::s390x->new(), 'can instantiate backend';
ok !$backend->check_socket(undef), 'check_socket returns false by default';

my $serialfile = $backend->{serialfile} = tempfile;
my $distri = $testapi::distri = distribution->new;

my $local_xvnc_mock = Test::MockModule->new('consoles::localXvnc');
my $local_xvnc_activated;
$local_xvnc_mock->redefine(activate => sub { $local_xvnc_activated = 1 });

my $s3270_mock = Test::MockModule->new('consoles::s3270');
$s3270_mock->noop('new_3270_console');
$s3270_mock->noop('connect_and_login');


subtest 'starting VM' => sub {
    ok $backend->do_start_vm, 'can start vm';
    ok $local_xvnc_activated, 'local Xvnc console activated';
    my $x3270_console = $testapi::distri->{consoles}->{x3270};
    is blessed $x3270_console, 'consoles::s3270', 'x3270 console assigned';
    is $x3270_console->backend, $backend, 'backend assignes itself to console';
};

subtest 'is_shutdown' => sub {
    my $x3270 = $testapi::distri->{consoles}->{x3270};
    my $console = Test::MockObject->new;
    $testapi::distri->{consoles}->{x3270} = $console;

    $console->set_always(shutdown_state => 'stopped');
    ok $backend->is_shutdown, 'CP READ is a shutdown';

    $console->set_always(shutdown_state => 'running');
    ok !$backend->is_shutdown, 'RUNNING is not a shutdown';

    $console->set_always(shutdown_state => 'panicked');
    my @panic_warnings = warnings { ok !$backend->is_shutdown, 'a kernel panic is not a shutdown' };
    like join('', @panic_warnings), qr/panicked during shutdown/, 'a kernel panic is logged';

    $testapi::distri->{consoles}->{x3270} = undef;
    my @warnings = warnings { ok !$backend->is_shutdown, 'a missing console is not a shutdown' };
    like join('', @warnings), qr/console x3270 does not exist/, 'a missing console warns';

    $testapi::distri->{consoles}->{x3270} = $x3270;
};

subtest 'stopping VM' => sub {
    my $dummy_console = $backend->{current_console} = $testapi::distri->{consoles}->{x3270} = Test::MockObject->new->set_always(disable => 1);
    $backend->{consoles} = {x3270 => $dummy_console};
    $backend->do_stop_vm;
    is $backend->{current_console}, undef, 'x3270 console no longer current console';
    $dummy_console->called_ok('disable', 'x3270 console disabled');
};

$serialfile->remove;

done_testing;

1;
