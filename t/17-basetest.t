#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::MockModule;
use Test::Fatal;
use Test::Output qw(combined_like);
use File::Basename;
use Mojo::File 'tempdir';
use Mojo::Util qw(scope_guard);

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };
mkdir 'testresults';

use basetest;
use needle;

# define 'write_with_thumbnail' to fake image
sub write_with_thumbnail { }

subtest run_post_fail_test => sub {
    my $basetest_class = 'basetest';
    Test::MockModule->new("autotest")->noop('set_current_test');
    my $mock_basetest = Test::MockModule->new($basetest_class);
    $mock_basetest->noop('take_screenshot');
    $mock_basetest->mock(run => sub { die(); });
    my $basetest = bless({
            details      => [],
            name         => 'foo',
            category     => 'category1',
            execute_time => 42,
    }, $basetest_class);
    combined_like { dies_ok { $basetest->runtest } 'run_post_fail end up with die' } qr/Test died/, 'test died';
    $bmwqemu::vars{_SKIP_POST_FAIL_HOOKS} = 1;
    combined_like { dies_ok { $basetest->runtest } 'behavior persists regardless of _SKIP_POST_FAIL_HOOKS setting' }
    qr/Test died/, 'test died';
};

subtest modules_test => sub {
    ok(my $basetest = basetest->new('installation'), 'module can be created');
    $basetest->{class}    = 'foo';
    $basetest->{fullname} = 'installation-foo';
    ok($basetest->is_applicable, 'module is applicable by default');
    $bmwqemu::vars{EXCLUDE_MODULES} = 'foo,bar';
    ok(!$basetest->is_applicable, 'module can be excluded');
    $bmwqemu::vars{EXCLUDE_MODULES} = '';
    $bmwqemu::vars{INCLUDE_MODULES} = 'bar,baz';
    ok(!$basetest->is_applicable, 'modules can be excluded based on a passlist');
    $bmwqemu::vars{INCLUDE_MODULES} = 'bar,baz,foo';
    ok($basetest->is_applicable, 'a passlisted module shows up');
    $bmwqemu::vars{EXCLUDE_MODULES} = 'foo';
    ok(!$basetest->is_applicable, 'passlisted modules are overriden by blocklist');
};

subtest parse_serial_output => sub {
    my $mock_basetest = Test::MockModule->new('basetest');
    # Mock reading of the serial output
    $mock_basetest->redefine(get_serial_output_json => sub {
            return {
                serial   => "Serial to match\n1q2w333\nMore text",
                position => '100'
            };
    });
    my $basetest = basetest->new('installation');
    my $message;
    $mock_basetest->redefine(record_resultfile => sub {
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
        {type => 'info', message => 'CPU soft lockup detected', pattern => qr/Serial/},
    ];
    $basetest->parse_serial_output_qemu();
    is($basetest->{result}, 'ok',                                                       'test result set to ok');
    is($message,            'CPU soft lockup detected - Serial error: Serial to match', 'log message matches output');

    $basetest->{serial_failures} = [
        {type => 'soft', message => 'SimplePattern', pattern => qr/Serial/},
    ];

    $basetest->parse_serial_output_qemu();
    is($basetest->{result}, 'softfail',                                      'test result set to soft failure');
    is($message,            'SimplePattern - Serial error: Serial to match', 'log message matches output');

    $basetest->{serial_failures} = [
        {type => 'soft', message => 'Proper regexp', pattern => qr/\d{3}/},
    ];
    $basetest->parse_serial_output_qemu();
    is($basetest->{result}, 'softfail',                              'test result set to soft failure');
    is($message,            'Proper regexp - Serial error: 1q2w333', 'log message matches output');

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
    my $basetest_class = 'basetest';
    my $mock_basetest  = Test::MockModule->new($basetest_class);
    $mock_basetest->redefine(_result_add_screenshot => sub { });

    my $basetest = bless({
            result     => undef,
            details    => [],
            test_count => 0,
    }, $basetest_class);

    is_deeply($basetest->record_testresult(), {result => 'unk'}, 'adding unknown result');
    is($basetest->{result},     undef, 'test result unaffected');
    is($basetest->{test_count}, 1,     'test count increased');

    is_deeply($basetest->record_testresult('ok'), {result => 'ok'}, 'adding "ok" result');
    is($basetest->{result}, 'ok', 'test result is now "ok"');

    is_deeply($basetest->record_testresult('softfail'), {result => 'softfail'}, 'adding "softfail" result');
    is($basetest->{result}, 'softfail', 'test result is now "softfail"');

    is_deeply($basetest->record_testresult('ok'), {result => 'ok'}, 'adding one more "ok" result');
    is($basetest->{result}, 'softfail', 'test result is still "softfail"');

    is_deeply($basetest->record_testresult('fail'), {result => 'fail'}, 'adding "fail" result');
    is($basetest->{result}, 'fail', 'test result is now "fail"');

    is_deeply($basetest->record_testresult('ok'), {result => 'ok'}, 'adding one more "ok" result');
    is($basetest->{result}, 'fail', 'test result is still "fail"');

    is_deeply($basetest->record_testresult('softfail'), {result => 'softfail'}, 'adding one more "softfail" result');
    is($basetest->{result}, 'fail', 'test result is still "fail"');

    is_deeply($basetest->record_testresult(), {result => 'unk'}, 'adding one more "unk" result');
    is($basetest->{result}, 'fail', 'test result is still "fail"');

    is_deeply($basetest->record_testresult('softfail', force_status => 1), {result => 'softfail'}, 'adding one more "softfail" result but forcing the status');
    is($basetest->{result}, 'softfail', 'test result was forced to "softfail"');

    is_deeply($basetest->take_screenshot(), {result => 'unk'},
        'unknown result from take_screenshot not added to details');

    my $nr_test_details = 9;
    is($basetest->{test_count},        $nr_test_details, 'test_count accumulated');
    is(scalar @{$basetest->{details}}, $nr_test_details, 'all details added');
};

subtest record_screenmatch => sub {
    my $basetest = basetest->new();
    my $image    = bless({} => __PACKAGE__);
    my %match    = (
        area => [
            {x => 1, y => 2, w => 3, h => 4, similarity => 0, result => 'ok'},
        ],
        error  => 0.128,
        needle => {
            name => 'foo',
            file => 'some/path/foo.json',
        },
    );
    my @tags           = (qw(some tags));
    my @failed_needles = (
        {
            error => 1,
            area  => [
                {x => 4, y => 3, w => 2, h => 1, similarity => 0, result => 'fail'},
            ],
            needle => {
                name => 'failure',
                file => 'some/path/failure.json',
            },
        },
    );
    my $frame = 24;

    $basetest->record_screenmatch($image, \%match, \@tags, \@failed_needles, $frame);
    is_deeply($basetest->{details}, [
            {
                area => [
                    {
                        x          => 1,
                        y          => 2,
                        w          => 3,
                        h          => 4,
                        similarity => 0,
                        result     => 'ok',
                    },
                ],
                error     => 0.128,
                frametime => [qw(1.00 1.04)],
                needle    => 'foo',
                json      => 'some/path/foo.json',
                needles   => [
                    {
                        area => [
                            {
                                x          => 4,
                                y          => 3,
                                w          => 2,
                                h          => 1,
                                similarity => 0,
                                result     => 'fail',
                            },
                        ],
                        error => 1,
                        name  => 'failure',
                        json  => 'some/path/failure.json',
                    }
                ],
                properties => [],
                screenshot => 'basetest-1.png',
                tags       => [qw(some tags)],
                result     => 'ok',
            }
    ], 'screenmatch detail recorded as expected')
      or diag explain $basetest->{details};

    # check a needle has workaround property
    my $basetest_for_workaround = basetest->new();
    my $misc_needles_dir        = dirname(__FILE__) . '/misc_needles/';
    my $needle_file             = $misc_needles_dir . "check-workaround-hash-20190522.json";
    my %workaround_match        = (
        area => [
            {x => 1, y => 2, w => 3, h => 4, similarity => 0, result => 'ok'},
        ],
        error  => 0.25,
        needle => {
            name       => 'check-workaround-hash-20190522',
            file       => $needle_file,
            properties => [
                {
                    name  => 'workaround',
                    value => 'bsc#7654321: this is a test about workaround.',
                }
            ],
        },
    );

    combined_like { $basetest_for_workaround->record_screenmatch($image, \%workaround_match, ['check-workaround-hash'], [], $frame) }
    qr/needle.*is a workaround/, 'needle workaround debug message found';
    is_deeply($basetest_for_workaround->{details}, [
            {
                result => 'softfail',
                title  => 'Soft Failed',
                text   => 'basetest-3.txt'
            },
            {
                area => [
                    {
                        x          => 1,
                        y          => 2,
                        w          => 3,
                        h          => 4,
                        similarity => 0,
                        result     => 'ok',
                    },
                ],
                error      => 0.25,
                frametime  => [qw(1.00 1.04)],
                needle     => 'check-workaround-hash-20190522',
                json       => $needle_file,
                properties => [
                    {
                        name  => 'workaround',
                        value => 'bsc#7654321: this is a test about workaround.',
                    }
                ],
                screenshot => 'basetest-1.png',
                tags       => [qw(check-workaround-hash)],
                result     => 'softfail',
                dent       => 1,
            }
    ], 'screenmatch detail with workaround property recorded as expected')
      or diag explain $basetest_for_workaround->{details};
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

subtest 'execute_time' => sub {
    my $basetest_class = 'basetest';
    my $mock_basetest  = Test::MockModule->new($basetest_class);
    my $test           = basetest->new('foo');
    is($test->{execution_time}, 0, 'the execution time is initiated correctly');
    $mock_basetest->mock(execution_time => 42);
    $mock_basetest->mock(run            => undef);
    $mock_basetest->redefine(done => undef);
    combined_like { $test->runtest } qr/finished basetest foo/, 'finish status message found';
    is($test->{execution_time}, 42, 'the execution time is correct');
};

done_testing;
