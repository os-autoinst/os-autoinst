#!/usr/bin/perl

use strict;
use warnings;
use Test::MockModule;
use Test::More;
use Test::Fatal;

BEGIN {
    unshift @INC, '..';
}

use basetest;

subtest modules_test => sub {
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
};

subtest parse_serial_output => sub {
    my $mock_basetest = new Test::MockModule('basetest');
    # Mock reading of the serial output
    $mock_basetest->mock(get_serial_output_json => sub {
            return {
                serial   => "Serial to match\n1q2w333\nMore text",
                position => '100'
            };
    });
    my $basetest = basetest->new('installation');
    my $message;
    $mock_basetest->mock(record_resultfile => sub {
            my ($self, $title, $output, %nargs) = @_;
            $message = $output;
    });

    is($basetest->parse_serial_output_qemu(0), 100, 'expected json result position returned');

    $basetest->{serial_failures} = [
        {type => 'soft', message => 'DoNotMatch', pattern => qr/DoNotMatch/},
    ];
    $basetest->parse_serial_output_qemu(0);
    is($basetest->{result}, undef, 'test result untouched without match');
    is($message,            undef, 'test details do not have extra message');

    $basetest->{serial_failures} = [
        {type => 'soft', message => 'SimplePattern', pattern => qr/Serial/},
    ];

    $basetest->parse_serial_output_qemu(0);
    is($basetest->{result}, 'softfail', 'test result set to soft failure');
    is($message, 'SimplePattern - Serial error: Serial to match', 'log message matches output');

    $basetest->{serial_failures} = [
        {type => 'soft', message => 'Proper regexp', pattern => qr/\d{3}/},
    ];
    $basetest->parse_serial_output_qemu(0);
    is($basetest->{result}, 'softfail', 'test result set to soft failure');
    is($message, 'Proper regexp - Serial error: 1q2w333', 'log message matches output');

    $basetest->{serial_failures} = [
        {type => 'hard', message => 'Message1', pattern => qr/Serial/},
    ];

    eval { $basetest->parse_serial_output_qemu(0) };
    like($@, qr(Got serial hard failure at.*), 'test died hard after match');
    is($basetest->{result}, 'fail', 'test result set to hard failure');

};

done_testing;
