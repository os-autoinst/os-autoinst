#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::Fatal;

BEGIN {
    unshift @INC, '..';
}

use basetest;

ok(my $basetest = basetest->new('installation'), 'module can be created');
$basetest->{class}    = 'foo';
$basetest->{fullname} = 'installation-foo';
ok($basetest->is_applicable, 'module is applicable by default');
$bmwqemu::vars{EXCLUDE_MODULES} = 'foo,bar';
ok(!$basetest->is_applicable, 'module can be excluded');
$bmwqemu::vars{EXCLUDE_MODULES} = '';
$bmwqemu::vars{INCLUDE_MODULES} = 'bar,baz';
ok(!$basetest->is_applicable, 'modules can be excluded based on a whitelist');
$bmwqemu::vars{INCLUDE_MODULES} = 'bar,baz,foo';
ok($basetest->is_applicable, 'a whitelisted module shows up');
$bmwqemu::vars{EXCLUDE_MODULES} = 'foo';
ok(!$basetest->is_applicable, 'whitelisted modules are overriden by blacklist');


done_testing;
