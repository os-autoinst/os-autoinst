#!/usr/bin/perl

use 5.018;
use Test::Most;

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Warnings qw(:all :report_warnings);

use backend::s390x;    # SUT

$bmwqemu::vars{WORKER_HOSTNAME} = 'localhost';
ok my $backend = backend::s390x->new(), 'can instantiate backend';
ok !$backend->check_socket, 'check_socket returns false by default';

done_testing;

1;
