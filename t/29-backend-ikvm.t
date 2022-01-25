#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;

use Test::MockModule;
use Test::Warnings qw(:report_warnings);
use Test::Fatal;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';

use backend::ikvm;    # SUT

$bmwqemu::vars{WORKER_HOSTNAME} = 'localhost';
ok my $backend = backend::ikvm->new(), 'backend can be created';
my $distri = Test::MockModule->new('distribution');
$testapi::distri = distribution->new;
$backend->relogin_vnc;
like(exception { $backend->do_start_vm }, qr/Need variable IPMI/, 'do_start_vm needs IPMI parameters');

done_testing;
