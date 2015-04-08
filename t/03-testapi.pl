#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 6;

BEGIN {
    unshift @INC, '..';
}

require bmwqemu;
require t::test_driver;

$bmwqemu::backend = t::test_driver->new;

use testapi;

type_string 'hallo';
is_deeply($bmwqemu::backend->{cmds}, ['type_string', { max_interval => 250, text => 'hallo' } ]);
$bmwqemu::backend->{cmds} = [];

type_string 'hallo', 4;
is_deeply($bmwqemu::backend->{cmds}, ['type_string', { max_interval => 4, text => 'hallo' } ]);
$bmwqemu::backend->{cmds} = [];

type_string 'hallo', secret => 1;
is_deeply($bmwqemu::backend->{cmds}, ['type_string', { max_interval => 250, text => 'hallo' } ]);
$bmwqemu::backend->{cmds} = [];

type_string 'hallo', secret => 1, max_interval => 10;
is_deeply($bmwqemu::backend->{cmds}, ['type_string', { max_interval => 10, text => 'hallo' } ]);
$bmwqemu::backend->{cmds} = [];

$testapi::password = 'stupid';
type_password;
is_deeply($bmwqemu::backend->{cmds}, ['type_string', { max_interval => 250, text => 'stupid' } ]);
$bmwqemu::backend->{cmds} = [];

type_password 'hallo';
is_deeply($bmwqemu::backend->{cmds}, ['type_string', { max_interval => 250, text => 'hallo' } ]);
$bmwqemu::backend->{cmds} = [];

# vim: set sw=4 et:
