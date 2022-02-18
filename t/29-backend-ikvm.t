#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;

use Test::MockModule;
use Test::Output qw(stderr_like);
use Test::Warnings qw(:report_warnings);
use Test::Fatal;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';

use backend::ikvm;    # SUT

$bmwqemu::vars{WORKER_HOSTNAME} = 'localhost';
like(exception { backend::ikvm->new }, qr/DEPRECATED/, 'deprecated backend dies by default');
$bmwqemu::vars{"NO_DEPRECATE_BACKEND_IKVM"} = 1;
my $backend;
stderr_like { $backend = backend::ikvm->new } qr/DEPRECATED/, 'backend can be created but is deprecated';
my $distri = Test::MockModule->new('distribution');
$testapi::distri = distribution->new;
$backend->relogin_vnc;
like(exception { $backend->do_start_vm }, qr/Need variable IPMI/, 'do_start_vm needs IPMI parameters');

done_testing;
