#!/usr/bin/perl

# Copyright 2017-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
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
use Test::Warnings qw(:report_warnings);

my $toplevel_dir = abs_path(dirname(__FILE__) . '/..');
my $data_dir = "$toplevel_dir/t/data";

sub create_vars ($data) {
    open(my $varsfh, '>', 'vars.json') || BAIL_OUT('can not create vars.json');
    my $json = Cpanel::JSON::XS->new->pretty->canonical;
    print $varsfh $json->encode($data);
    close($varsfh);
}

sub read_vars {
    local $/;
    open(my $varsfh, '<', 'vars.json') || BAIL_OUT('can not open vars.json for reading');
    my $ret;
    eval { $ret = Cpanel::JSON::XS->new->relaxed->decode(<$varsfh>); };
    die "parse error in vars.json:\n$@" if $@;
    close($varsfh);
    return $ret;
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
        my $lines = ["a", ["b"]];
        bmwqemu::log_call(test => $lines);
    }
    stderr_like(\&log_call_indent, qr{\Q<<< main::log_call_indent(test=[\E\n\Q    "a",\E\n\Q    [\E\n\Q      "b"\E\n\Q    ]\E\n\Q  ])}, 'log_call auto indentation');
};

subtest 'update_line_number' => sub {
    $bmwqemu::direct_output = 1;
    bmwqemu::init_logger();
    ok !bmwqemu::update_line_number(), 'update_line_number needs current_test defined';
    $autotest::current_test = {script => 'my/module.pm'};
    stderr_like { bmwqemu::update_line_number() } qr{bmwqemu.t.*called.*subtest}, 'update_line_number identifies caller scope';
};

subtest 'CASEDIR is mandatory' => sub {
    my $dir = '/var/lib/openqa';
    create_vars({DISTRI => 'test'});

    eval {
        use bmwqemu ();
        bmwqemu::init;
        bmwqemu::ensure_valid_vars();
    };
    like($@, qr(CASEDIR variable not set.*), 'bmwqemu refuses to init');


    my %vars = %{read_vars()};
    is($vars{DISTRI}, 'test', 'DISTRI unchanged by init call');
    ok(!$vars{CASEDIR}, 'CASEDIR not set');
};

subtest 'save_vars' => sub {
    my $dir = "$data_dir/tests";
    create_vars({CASEDIR => $dir, _SECRET_TEST => 'my_credentials'});
    $bmwqemu::openqa_default_share = $data_dir;

    eval {
        use bmwqemu ();
        bmwqemu::init;
        bmwqemu::save_vars();
    };
    ok(!$@, 'init successful');

    my %vars = %{read_vars()};
    is($vars{_SECRET_TEST}, 'my_credentials', '_SECRET_TEST unchanged');
    is($vars{CASEDIR}, $dir, 'CASEDIR unchanged');
};

subtest 'save_vars no_secret' => sub {
    my $dir = "$data_dir/tests";
    create_vars({CASEDIR => $dir, _SECRET_TEST => 'my_credentials'});
    $bmwqemu::openqa_default_share = $data_dir;

    eval {
        use bmwqemu ();
        bmwqemu::init;
        bmwqemu::save_vars(no_secret => 1);
    };
    ok(!$@, 'init successful');

    my %vars = %{read_vars()};
    ok(!$vars{_SECRET_TEST}, '_SECRET_TEST not written to vars.json');
    is($vars{CASEDIR}, $dir, 'CASEDIR unchanged');
};

subtest 'HDD variables sanity check' => sub {
    use bmwqemu ();
    %bmwqemu::vars = (NUMDISKS => 1, HDD_1 => 'foo.qcow2', PUBLISH_HDD_1 => 'bar.qcow2');
    ok(bmwqemu::_check_publish_vars, 'one HDD for reading, one for publishing is ok');
    $bmwqemu::vars{PUBLISH_HDD_1} = 'foo.qcow2';
    throws_ok { bmwqemu::_check_publish_vars } qr/HDD_1 also specified in PUBLISH/, 'overwriting source HDD is prevented';
};

my %new_json = (foo => 'bar', baz => 42);
ok bmwqemu::save_json_file(\%new_json, 'new_json_file.json'), 'JSON file can be saved with save_json_file';
is_deeply decode_json(path('new_json_file.json')->slurp), \%new_json, 'JSON file written with correct content';
done_testing;

END {
    unlink for qw(vars.json new_json_file.json);
}

1;
