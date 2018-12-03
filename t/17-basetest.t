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
    my $mock_basetest = Test::MockModule->new('basetest');
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

    $basetest->parse_serial_output_qemu();
    $basetest->{serial_failures} = [
        {type => 'soft', message => 'DoNotMatch', pattern => qr/DoNotMatch/},
    ];
    $basetest->parse_serial_output_qemu();
    is($basetest->{result}, undef, 'test result untouched without match');
    is($message,            undef, 'test details do not have extra message');

    $basetest->{serial_failures} = [
        {type => 'soft', message => 'SimplePattern', pattern => qr/Serial/},
    ];

    $basetest->parse_serial_output_qemu();
    is($basetest->{result}, 'softfail', 'test result set to soft failure');
    is($message, 'SimplePattern - Serial error: Serial to match', 'log message matches output');

    $basetest->{serial_failures} = [
        {type => 'soft', message => 'Proper regexp', pattern => qr/\d{3}/},
    ];
    $basetest->parse_serial_output_qemu();
    is($basetest->{result}, 'softfail', 'test result set to soft failure');
    is($message, 'Proper regexp - Serial error: 1q2w333', 'log message matches output');

    $basetest->{serial_failures} = [
        {type => 'hard', message => 'Message1', pattern => qr/Serial/},
    ];

    eval { $basetest->parse_serial_output_qemu() };
    like($@, qr(Got serial hard failure at.*), 'test died hard after match');
    is($basetest->{result}, 'fail', 'test result set to hard failure');

    $basetest->{serial_failures} = [
        {type => 'fatal', message => 'Message1', pattern => qr/Serial/},
    ];

    eval { $basetest->parse_serial_output_qemu() };
    like($@, qr(Got serial hard failure at.*), 'test died hard after match with fatal type');
    is($basetest->{result}, 'fail', 'test result set to fail after fatal failure');

    $basetest->{serial_failures} = [
        {type => 'non_existent type', message => 'Message1', pattern => qr/Serial/},
    ];
    eval { $basetest->parse_serial_output_qemu() };
    like($@, qr(Wrong type defined for serial failure.*), 'test died because of wrong serial failure type');
    is($basetest->{result}, 'fail', 'test result set to hard failure');

    $basetest->{serial_failures} = [
        {type => 'soft', message => undef, pattern => qr/Serial/},
    ];
    eval { $basetest->parse_serial_output_qemu() };
    like($@, qr(Message not defined for serial failure for the pattern.*), 'test died because of missing message');
    is($basetest->{result}, 'fail', 'test result set to hard failure');

};

subtest record_testresult => sub {
    my $basetest = {
        result     => undef,
        details    => [],
        test_count => 0,
    };

    is_deeply(basetest::record_testresult($basetest), {result => 'unk'}, 'adding unknown result');
    is($basetest->{result},     undef, 'test result unaffected');
    is($basetest->{test_count}, 1,     'test count increased');

    is_deeply(basetest::record_testresult($basetest, 'ok'), {result => 'ok'}, 'adding "ok" result');
    is($basetest->{result}, 'ok', 'test result is now "ok"');

    is_deeply(basetest::record_testresult($basetest, 'softfail'), {result => 'softfail'}, 'adding "softfail" result');
    is($basetest->{result}, 'softfail', 'test result is now "softfail"');

    is_deeply(basetest::record_testresult($basetest, 'ok'), {result => 'ok'}, 'adding one more "ok" result');
    is($basetest->{result}, 'softfail', 'test result is still "softfail"');

    is_deeply(basetest::record_testresult($basetest, 'fail'), {result => 'fail'}, 'adding "fail" result');
    is($basetest->{result}, 'fail', 'test result is now "fail"');

    is_deeply(basetest::record_testresult($basetest, 'ok'), {result => 'ok'}, 'adding one more "ok" result');
    is($basetest->{result}, 'fail', 'test result is still "fail"');

    is_deeply(basetest::record_testresult($basetest, 'softfail'), {result => 'softfail'}, 'adding one more "softfail" result');
    is($basetest->{result}, 'fail', 'test result is still "fail"');

    is_deeply(basetest::record_testresult($basetest), {result => 'unk'}, 'adding one more "unk" result');
    is($basetest->{result}, 'fail', 'test result is still "fail"');

    is_deeply(basetest::record_testresult($basetest, 'softfail', force_status => 1), {result => 'softfail'}, 'adding one more "softfail" result but forcing the status');
    is($basetest->{result}, 'softfail', 'test result was forced to "softfail"');

    my $nr_test_details = 9;
    is($basetest->{test_count},        $nr_test_details, 'test_count accumulated');
    is(scalar @{$basetest->{details}}, $nr_test_details, 'all details added');
};

subtest 'register_extra_test_results' => sub {
    my $test = basetest->new('foo');
    $test->{script} = '/tests/foo/bar.pm';

    my $extra_tests = [
        {
            category => 'foo',
            name     => 'extra1',
            flags    => {},
            script   => 'unk'
        },
        {
            category => 'foo',
            name     => 'extra2',
            flags    => {},
            script   => '/test/foo/baz.pm'
        },
        {
            category => 'foo',
            name     => 'extra3',
            flags    => {},
            script   => undef
        }
    ];

    $test->register_extra_test_results($extra_tests);
    is(@{$test->{extra_test_results}},             @{$extra_tests},             'add extra test results');
    is($test->{extra_test_results}->[0]->{script}, $test->{script},             'unknown script is replaced with self->{script}.');
    is($test->{extra_test_results}->[1]->{script}, $extra_tests->[1]->{script}, 'existing script is untouched.');
    is($test->{extra_test_results}->[2]->{script}, $test->{script},             'undefined script is replaced with self->{script}.');
};

done_testing;
