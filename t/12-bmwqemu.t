#!/usr/bin/perl

# Copyright 2017-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Test::MockModule;
use Mojo::Base -signatures;
use Test::Mock::Time;
use Feature::Compat::Try;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Output 'stderr_like';
use File::Temp 'tempdir';
use File::Basename;
use File::Path 'make_path';
use Cwd 'abs_path';
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json);
use Cpanel::JSON::XS ();
use Test::Warnings qw(warning :report_warnings);

my $toplevel_dir = abs_path(dirname(__FILE__) . '/..');
my $data_dir = "$toplevel_dir/t/data";

sub create_vars ($data) { path('vars.json')->spew(Cpanel::JSON::XS->new->pretty->canonical->encode($data)) }

sub read_vars () {
    try { return Cpanel::JSON::XS->new->relaxed->decode(path('vars.json')->slurp) }
    catch ($e) { die "parse error in vars.json:\n$e" }    # uncoverable statement
}

subtest 'log_call' => sub {
    require bmwqemu;

    sub log_call_test {
        bmwqemu::log_call(foo => "bar\tbaz\rboo\n");
    }
    stderr_like(\&log_call_test, qr{\Q<<< main::log_call_test(foo="bar\tbaz\rboo\n")}, 'log_call escapes special characters');

    sub log_call_test_escape_key {
        bmwqemu::log_call("foo\nbar" => "bar\tbaz\rboo\n");
    }
    stderr_like(\&log_call_test_escape_key, qr{\Q<<< main::log_call_test_escape_key("foo\nbar"="bar\tbaz\rboo\n")}, 'log_call escapes special characters');

    sub log_call_test_single {
        bmwqemu::log_call("bar\tbaz\rboo\n");
    }
    stderr_like(\&log_call_test_single, qr{\Q<<< main::log_call_test_single("bar\tbaz\rboo\n")}, 'log_call escapes special characters');

    sub log_call_indent {
        my $lines = ['a', ['b']];
        bmwqemu::log_call(test => $lines);
    }
    stderr_like(\&log_call_indent, qr{\Q<<< main::log_call_indent(test=[\E\n\Q    "a",\E\n\Q    [\E\n\Q      "b"\E\n\Q    ]\E\n\Q  ])}, 'log_call auto indentation');

    sub log_call_test_secret {
        my (%args) = @_;
        # Use @_ instead of %args to keep the order
        bmwqemu::log_call(@_, ($args{secret} ? (-masked => $args{text}) : ()));
        return;
    }
    stderr_like { log_call_test_secret(text => "password\n", secret => 1) } qr{\Q<<< main::log_call_test_secret(text="[masked]", secret=1)}, 'log_call hides sensitive info';
    stderr_like { log_call_test_secret(text => "password\n") } qr{\Q<<< main::log_call_test_secret(text="password\n")}, 'log_call hides sensitive info';

    my $do_not_show_me = '$^a{1}\n\\FooBar.';
    stderr_like { log_call_test_secret(text => $do_not_show_me, psk => $do_not_show_me, -masked => $do_not_show_me) } qr{\Q<<< main::log_call_test_secret(text="[masked]", psk="[masked]")}, 'Hide secrets with special regex chars';
    stderr_like { log_call_test_secret(text => "$do_not_show_me$do_not_show_me", -masked => $do_not_show_me) } qr{\Q<<< main::log_call_test_secret(text="[masked][masked]")}, 'Hide secrets if it occure multiple times';

    stderr_like { log_call_test_secret(text => 'a666b42c', -masked => ['666', '42']) } qr{\Q<<< main::log_call_test_secret(text="a[masked]b[masked]c")}, 'Hide multiple secrets given as array';
    stderr_like { log_call_test_secret(text => 'a666b42c', -masked => '666', -masked => '42') } qr{\Q<<< main::log_call_test_secret(text="a[masked]b[masked]c")}, 'Hide multiple secrets given as multiple arguments';
    stderr_like { log_call_test_secret(text => 'a666b42c5', -masked => ['666', '5'], -masked => '42') } qr{\Q<<< main::log_call_test_secret(text="a[masked]b[masked]c[masked]")}, 'Hide multiple secrets given in mixed format';

    my $super_long_partly_secret_string = "Hallo world my psk is $do_not_show_me";
    stderr_like { log_call_test_secret(output => $super_long_partly_secret_string, -masked => $do_not_show_me) } qr{\Q<<< main::log_call_test_secret(output="Hallo world my psk is [masked]")}, 'Hide secrets as part of a string';

    stderr_like { log_call_test_secret(value => 0) } qr{\Q<<< main::log_call_test_secret(value=0)}, 'Value evaluate to false';
    stderr_like { log_call_test_secret(value => undef) } qr{\Q<<< main::log_call_test_secret(value=undef)}, 'Undef as value';
};

subtest 'update_line_number' => sub {
    $log::direct_output = 1;
    bmwqemu::init_logger();
    ok !bmwqemu::update_line_number(), 'update_line_number needs current_test defined';
    $autotest::current_test = {script => 'my/module.pm'};
    stderr_like { bmwqemu::update_line_number() } qr{bmwqemu.t.*called.*subtest}, 'update_line_number identifies caller scope';
};

subtest 'CASEDIR is mandatory' => sub {
    my $dir = '/var/lib/openqa';
    create_vars({DISTRI => 'test'});

    throws_ok {
        use bmwqemu ();
        bmwqemu::init;
        bmwqemu::ensure_valid_vars();
    } qr(CASEDIR variable not set.*), 'bmwqemu refuses to init';


    my %vars = %{read_vars()};
    is($vars{DISTRI}, 'test', 'DISTRI unchanged by init call');
    ok(!$vars{CASEDIR}, 'CASEDIR not set');
};

subtest 'save_vars' => sub {
    my $dir = "$data_dir/tests";
    create_vars({CASEDIR => $dir, _SECRET_TEST => 'my_credentials'});
    $bmwqemu::openqa_default_share = $data_dir;

    lives_ok {
        use bmwqemu ();
        bmwqemu::init;
        bmwqemu::save_vars();
    } 'init successful';

    my %vars = %{read_vars()};
    is($vars{_SECRET_TEST}, 'my_credentials', '_SECRET_TEST unchanged');
    is($vars{CASEDIR}, $dir, 'CASEDIR unchanged');
};

subtest load_vars => sub {
    path('vars.json')->spew(']]]');
    throws_ok { bmwqemu::load_vars() } qr/parse error in vars.json.*malformed/s, 'load_vars dies on invalid vars.json';
};

subtest 'save_vars no_secret' => sub {
    my $dir = "$data_dir/tests";
    create_vars({CASEDIR => $dir, _SECRET_TEST => 'my_credentials', MY_PASSWORD => 'secret', SNEAKY_TEXT => 'secret', NOT_SECRET => 'SNEAKY_VAL'});
    $bmwqemu::openqa_default_share = $data_dir;

    lives_ok {
        use bmwqemu ();
        bmwqemu::init;
        bmwqemu::save_vars(no_secret => 1);
    } 'init successful';

    my %vars = %{read_vars()};
    ok(!$vars{_SECRET_TEST}, '_SECRET_TEST not written to vars.json');
    ok(!$vars{MY_PASSWORD}, 'MY_PASSWORD not written to vars.json');
    is($vars{CASEDIR}, $dir, 'CASEDIR unchanged');
    is($vars{SNEAKY_TEXT}, 'secret', 'custom text is included by default');
    is($vars{NOT_SECRET}, 'SNEAKY_VAL', 'variable with matching value but non-matching name is included');

    $bmwqemu::vars{_HIDE_SECRETS_REGEX} = '^SNEAKY_';
    bmwqemu::save_vars(no_secret => 1);
    %vars = %{read_vars()};
    ok(!$vars{SNEAKY_TEXT}, 'custom text name matching regex is excluded');
    is($vars{NOT_SECRET}, 'SNEAKY_VAL', 'matching value but non-matching name (due to anchor) is still included');
    is($vars{CASEDIR}, $dir, 'CASEDIR unchanged if custom text matches secret');
    is($vars{_HIDE_SECRETS_REGEX}, '^SNEAKY_', '_HIDE_SECRETS_REGEX itself is preserved');
};

subtest 'HDD variables sanity check' => sub {
    use bmwqemu ();
    %bmwqemu::vars = (NUMDISKS => 1, HDD_1 => 'foo.qcow2', PUBLISH_HDD_1 => 'bar.qcow2');
    ok(bmwqemu::_check_publish_vars, 'one HDD for reading, one for publishing is ok');
    $bmwqemu::vars{PUBLISH_HDD_1} = 'foo.qcow2';
    throws_ok { bmwqemu::_check_publish_vars } qr/HDD_1 also specified in PUBLISH/, 'overwriting source HDD is prevented';
};

subtest 'invalid vars characters' => sub {
    my $num = scalar %bmwqemu::vars;
    throws_ok { $bmwqemu::vars{lowercase_not_accepted} = 23 } qr{Settings key 'lowercase_not_accepted' is invalid.*12-bmwqemu.t}s, 'Invalid keys results in an exception';
    $bmwqemu::vars{LOWERCASE_NOT_ACCEPTED} = 23;
    my $new_num = %bmwqemu::vars;
    is $new_num, $num + 1, '%vars in scalar context works';
    is exists $bmwqemu::vars{lowercase_not_accepted}, '', 'exists $vars{...} works, lowercase key not found';
    is exists $bmwqemu::vars{LOWERCASE_NOT_ACCEPTED}, 1, 'exists $vars{...} works';
};

my %new_json = (foo => 'bar', baz => 42, object => bless {this => 'cannot be encoded'}, 'Foo');
throws_ok { bmwqemu::save_json_file(\%new_json, 'new_json_file.json') } qr{Cannot encode input.*encountered object.*bless.*cannot be encoded}s;
delete $new_json{object};
ok bmwqemu::save_json_file(\%new_json, 'new_json_file.json'), 'JSON file can be saved with save_json_file';
is_deeply decode_json(path('new_json_file.json')->slurp), \%new_json, 'JSON file written with correct content';

ok bmwqemu::wait_for_one_more_screenshot, 'wait for one more screenshot is ok';

subtest 'serializing state' => sub {
    bmwqemu::serialize_state(msg => 'myjsonrpc: remote end terminated');
    ok !-e bmwqemu::STATE_FILE, 'no statefile created for shutdown-related message';
    bmwqemu::serialize_state(msg => 'foo');
    is_deeply decode_json(path(bmwqemu::STATE_FILE)->slurp), {msg => 'foo'}, 'state serialized';
};

subtest 'abort on low disk space' => sub {
    my $bmw_mock = Test::MockModule->new('bmwqemu', no_auto => 1);
    my @cases = (
        {hdd_size_gb => 1, total_storage => 100, avail_storage => 10, expect => 'fail',
            desc => 'abort if requested HDDSIZEGB exceeds default threshold (1GB requested with 10GB avail on 100GB disk)'},
        {hdd_size_gb => 10, total_storage => 100, avail_storage => 100, expect => 'pass',
            desc => 'succeed if requested HDDSIZEGB is well within available space'},
        {hdd_size_gb => 60, total_storage => 5, avail_storage => 5, expect => 'fail', extra_vars => {STORAGE_KEEP_FREE_RATIO => 0.9},
            desc => 'abort if requested HDDSIZEGB exceeds custom threshold'},
        {hdd_size_gb => 1, total_storage => 1, avail_storage => 0.1, expect => 'pass', extra_vars => {STORAGE_KEEP_FREE_RATIO => 0},
            desc => 'succeed if requested HDDSIZEGB exceeds available space but ratio is 0'},
        {total_storage => 100, avail_storage => 100, expect => 'pass',
            desc => 'succeed with default HDDSIZEGB'},
        {hdd_size_gb => 20, total_storage => 1000, avail_storage => 200, expect => 'pass',
            desc => 'passes if only relative threshold exceeded but leaves > 50GB free (e.g. 20GB requested on 1000GB disk with 200GB avail)'},
        {hdd_size_gb => 160, total_storage => 1000, avail_storage => 200, expect => 'fail',
            desc => 'large job fails when both relative and default 50GB absolute thresholds exceeded'},
        {hdd_size_gb => 160, total_storage => 1000, avail_storage => 500, expect => 'pass',
            desc => 'large job passes when sufficient absolute storage available'},
        {hdd_size_gb => 50, total_storage => 100, avail_storage => 60, expect => 'fail',
            desc => 'fails if both relative and absolute thresholds exceeded (e.g. 50GB requested on 100GB disk with 60GB avail leaves 10GB free)'},
        {hdd_size_gb => 50, total_storage => 100, avail_storage => 60, expect => 'pass', extra_vars => {STORAGE_KEEP_FREE_GB => 0},
            desc => 'passes if both thresholds would be exceeded but absolute threshold is disabled via 0'},
    );
    for my $case (@cases) {
        unlink bmwqemu::STATE_FILE;
        my %vars = (CASEDIR => "$data_dir/tests", %{$case->{extra_vars} // {}});
        $vars{HDDSIZEGB} = $case->{hdd_size_gb} if defined $case->{hdd_size_gb};
        create_vars(\%vars);
        $bmw_mock->mock(_get_storage_stats => sub (@) { ($case->{total_storage} * 1024**3, $case->{avail_storage} * 1024**3) });
        if ($case->{expect} eq 'pass') {
            lives_ok { bmwqemu::init(); bmwqemu::ensure_valid_vars(); } $case->{desc};
        }
        else {
            throws_ok { bmwqemu::init(); bmwqemu::ensure_valid_vars(); } qr/Not enough storage for requested HDDSIZEGB/, $case->{desc};
            is decode_json(path(bmwqemu::STATE_FILE)->slurp)->{result}, 'incomplete', "serialized result is incomplete for: $case->{desc}";
        }
    }
};

subtest '_get_storage_stats' => sub {
    my $tmp = tempdir(CLEANUP => 1);
    my $dummy_df = "$tmp/df";
    for my $case (
        {output => ' 1000 500', total => 1000, avail => 500, msg => 'matches dummy df'},
        {output => 'malformed', total => undef, avail => undef, msg => 'is undef on malformed df output'},
    ) {
        path($dummy_df)->spew("#!/bin/sh\necho '$case->{output}'");
        chmod 0755, $dummy_df;
        local $ENV{PATH} = "$tmp:$ENV{PATH}";
        my ($total, $available) = bmwqemu::_get_storage_stats('.');
        is $total, $case->{total}, "total $case->{msg}";
        is $available, $case->{avail}, "available $case->{msg}";
    }

    my ($total, $available) = bmwqemu::_get_storage_stats('.');
    like $total, qr/^\d+$/, 'returns numeric total storage';
    like $available, qr/^\d+$/, 'returns numeric available storage';
};

done_testing;

END {
    unlink for qw(vars.json new_json_file.json), bmwqemu::STATE_FILE;
}

1;
