#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 11;
use Test::Output;

BEGIN {
    unshift @INC, '..';
}

require bmwqemu;
require t::test_driver;

$bmwqemu::backend = t::test_driver->new;

use testapi;

type_string 'hallo';
is_deeply($bmwqemu::backend->{cmds}, ['type_string', {max_interval => 250, text => 'hallo'}]);
$bmwqemu::backend->{cmds} = [];

type_string 'hallo', 4;
is_deeply($bmwqemu::backend->{cmds}, ['type_string', {max_interval => 4, text => 'hallo'}]);
$bmwqemu::backend->{cmds} = [];

type_string 'hallo', secret => 1;
is_deeply($bmwqemu::backend->{cmds}, ['type_string', {max_interval => 250, text => 'hallo'}]);
$bmwqemu::backend->{cmds} = [];

type_string 'hallo', secret => 1, max_interval => 10;
is_deeply($bmwqemu::backend->{cmds}, ['type_string', {max_interval => 10, text => 'hallo'}]);
$bmwqemu::backend->{cmds} = [];

$testapi::password = 'stupid';
type_password;
is_deeply($bmwqemu::backend->{cmds}, ['type_string', {max_interval => 100, text => 'stupid'}]);
$bmwqemu::backend->{cmds} = [];

type_password 'hallo';
is_deeply($bmwqemu::backend->{cmds}, ['type_string', {max_interval => 100, text => 'hallo'}]);
$bmwqemu::backend->{cmds} = [];

is($autotest::current_test->{dents}, undef, 'no soft failures so far');
stderr_like(\&record_soft_failure, qr/record_soft_failure\(reason=undef\)/, 'soft failure recorded in log');
is($autotest::current_test->{dents}, 1, 'soft failure recorded');
stderr_like(sub { record_soft_failure('workaround for bug#1234') }, qr/record_soft_failure.*reason=.*workaround for bug#1234.*/, 'soft failure with reason');
is($autotest::current_test->{dents}, 2, 'another');

# vim: set sw=4 et:
