#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::MockObject;
use Test::MockModule;
use Test::Warnings qw(:all :report_warnings);

use backend::baseclass;
use bmwqemu;
use testapi;
use basetest;
use distribution;

my $mock_bmwqemu   = Test::MockModule->new('bmwqemu');
my $mock_basetest  = Test::MockModule->new('basetest');
my $mock_baseclass = Test::MockModule->new('backend::baseclass');
my $mock_jsonrpc   = Test::MockModule->new('myjsonrpc');

my $console_check_args = [];
my %console_const_hash = (x => 'a', y => 'b', z => 'c');
my $console            = Test::MockObject->new();
$console->mock('ret_array',           sub { my @array = qw(a b c d ); });
$console->mock('ret_array_empty',     sub { my @a; });
$console->mock('ret_array_ref',       sub { [qw(a b c d)]; });
$console->mock('ret_array_ref_empty', sub { []; });
$console->mock('ret_hash',            sub { %console_const_hash; });
$console->mock('ret_hash_empty',      sub { my %empty_hash; });
$console->mock('ret_hash_ref',        sub { {x => 'a', y => 'b', z => 'c'}; });
$console->mock('ret_hash_ref_empty',  sub { {} });
$console->mock('ret_scalar',          sub { "a" });
$console->mock('ret_undef',           sub { return undef; });
$console->mock('ret_list',            sub { qw(a b c d); });
$console->mock('ret_list_empty',      sub { return; });
$console->mock('ret_die',             sub { die("!!Urgs!!"); });
$console->mock('check_args', sub {
        my ($self, @args) = @_;
        is_deeply(\@args, $console_check_args, 'Got expected (' . join(',', @args) . ') arguments');
});

$mock_bmwqemu->noop('log_call');
$mock_basetest->noop('_result_add_screenshot');
$mock_baseclass->redefine('console', $console);

my $baseclass = backend::baseclass->new();
testapi::set_distribution(distribution->new());
$autotest::current_test = basetest->new();

my $jsonrpc_cmds    = [];
my $jsonrpc_results = [];
$mock_jsonrpc->redefine(
    send_json => sub { push(@$jsonrpc_cmds, $_[1]); },
    read_json => sub {
        my $cmd = $jsonrpc_cmds->[-1]->{cmd};
        if ($cmd eq 'backend_proxy_console_call') {
            push @$jsonrpc_results, $baseclass->proxy_console_call($jsonrpc_cmds->[-1]);
            return {ret => $jsonrpc_results->[-1]};
        }
        elsif ($cmd eq 'backend_select_console') {
            return {ret => {activated => 0}};
        }

        die("$cmd not handled in this test");
    });

subtest 'Verify fake console return values in scalar context' => sub {
    is_deeply(scalar($console->ret_array()),           4,                              'ARRAY');
    is_deeply(scalar($console->ret_array_empty()),     0,                              'Empty ARRAY');
    is_deeply(scalar($console->ret_array_ref()),       ['a', 'b', 'c', 'd'],           'ARRAY-REF');
    is_deeply(scalar($console->ret_array_ref_empty()), [],                             'Empty ARRAY-REF');
    is_deeply(scalar($console->ret_hash()),            3,                              'HASH');
    is_deeply(scalar($console->ret_hash_empty()),      0,                              'Empty HASH');
    is_deeply(scalar($console->ret_hash_ref()),        {x => 'a', y => 'b', z => 'c'}, 'HASH-REF');
    is_deeply(scalar($console->ret_hash_ref_empty()),  {},                             'Empty HASH-REF');
    is_deeply(scalar($console->ret_scalar()),          "a",                            'SCALAR');
    is_deeply(scalar($console->ret_undef()),           undef,                          'Return undef');
    is_deeply(scalar($console->ret_list()),            'd',                            'LIST');
    is_deeply(scalar($console->ret_list_empty()),      undef,                          'Empty LIST');
};

subtest 'testapi::console() => backend::console_proxy => backend::baseclass::proxy_console_call()' => sub {

    select_console('a-console');
    # Call each method in SCALAR and ARRAY context once via the proxy and once without.
    # Validate that both calls return the same value.
    for my $func (qw(ret_array ret_array_empty ret_array_ref ret_array_ref_empty
        ret_hash ret_hash_empty ret_hash_ref ret_hash_ref_empty
        ret_scalar ret_undef
        ret_list ret_list_empty)) {
        $jsonrpc_cmds = [];    # we do not need $jsonrpc_cmds history!

        # Call in void context
        console('a-console')->$func();

        my $scalar_exp = $console->$func();
        my $scalar_got = console('a-console')->$func();
        is_deeply($scalar_got, $scalar_exp, "Call $func() in SCALAR context");

        my @array_exp = $console->$func();
        my @array_got = console('a-console')->$func();
        is_deeply(\@array_got, \@array_exp, "Call $func() in ARRAY context");

        my $exp = [
            {
                cmd       => 'backend_proxy_console_call',
                console   => 'a-console',
                function  => $func,
                args      => [],
                wantarray => undef,
            },
            {
                cmd       => 'backend_proxy_console_call',
                console   => 'a-console',
                function  => $func,
                args      => [],
                wantarray => !!0,
            },

            {
                cmd       => 'backend_proxy_console_call',
                console   => 'a-console',
                function  => $func,
                args      => [],
                wantarray => !!1,
            },
        ];
        is_deeply([@{$jsonrpc_cmds}[-3 .. -1]], $exp, "Expected call parameters!");
    }

    throws_ok { console('a-console')->ret_die() } qr/!!Urgs!!/, "Exception forwarded";
    like($jsonrpc_results->[-1]->{exception}, qr/!!Urgs!!/, "Exception was JSON encoded");

    my $exp = {
        cmd       => 'backend_proxy_console_call',
        console   => 'a-console',
        function  => 'check_args',
        args      => undef,
        wantarray => undef,
    };

    $exp->{args} = $console_check_args = [];
    console->check_args();
    is_deeply($jsonrpc_cmds->[-1], $exp, "Call without arguments");

    $exp->{args} = $console_check_args = [qw( a b c d e )];
    console->check_args('a', 'b', 'c', 'd', 'e');
    is_deeply($jsonrpc_cmds->[-1], $exp, "Call with 5 arguments");

    $exp->{args} = $console_check_args = [qw(foo bar)];
    console->check_args(foo => 'bar');
    is_deeply($jsonrpc_cmds->[-1], $exp, "Call with hash as argument");
};

done_testing;
