#!/usr/bin/perl

use Mojo::Base -strict;
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
ok my $backend = backend::s390x->new(), 'can instantiate backend';
ok !$backend->check_socket(undef), 'check_socket returns false by default';

my $serialfile = $backend->{serialfile} = tempfile;
my $distri = $testapi::distri = distribution->new;

my $local_xvnc_mock = Test::MockModule->new('consoles::localXvnc');
my $local_xvnc_activated;
$local_xvnc_mock->redefine(activate => sub { $local_xvnc_activated = 1 });


subtest 'starting VM' => sub {
    ok $backend->do_start_vm, 'can start vm';
    ok $local_xvnc_activated, 'local Xvnc console activated';
    my $x3270_console = $testapi::distri->{consoles}->{x3270};
    is blessed $x3270_console, 'consoles::s3270', 'x3270 console assigned';
    is $x3270_console->backend, $backend, 'backend assignes itself to console';
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
