#!/usr/bin/perl

# Copyright 2017-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Mock::Time;
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

sub create_vars ($data) {
    open(my $varsfh, '>', 'vars.json') || BAIL_OUT('can not create vars.json');
    my $json = Cpanel::JSON::XS->new->pretty->canonical;
    print $varsfh $json->encode($data);
    close($varsfh);
}

sub read_vars () {
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

    stderr_like { log_call_test_secret(text => "a666b42c", -masked => ['666', '42']) } qr{\Q<<< main::log_call_test_secret(text="a[masked]b[masked]c")}, 'Hide multiple secrets given as array';
    stderr_like { log_call_test_secret(text => "a666b42c", -masked => '666', -masked => '42') } qr{\Q<<< main::log_call_test_secret(text="a[masked]b[masked]c")}, 'Hide multiple secrets given as multiple arguments';
    stderr_like { log_call_test_secret(text => "a666b42c5", -masked => ['666', '5'], -masked => '42') } qr{\Q<<< main::log_call_test_secret(text="a[masked]b[masked]c[masked]")}, 'Hide multiple secrets given in mixed format';

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
    create_vars({CASEDIR => $dir, _SECRET_TEST => 'my_credentials', MY_PASSWORD => 'secret'});
    $bmwqemu::openqa_default_share = $data_dir;

    eval {
        use bmwqemu ();
        bmwqemu::init;
        bmwqemu::save_vars(no_secret => 1);
    };
    ok(!$@, 'init successful');

    my %vars = %{read_vars()};
    ok(!$vars{_SECRET_TEST}, '_SECRET_TEST not written to vars.json');
    ok(!$vars{MY_PASSWORD}, 'MY_PASSWORD not written to vars.json');
    is($vars{CASEDIR}, $dir, 'CASEDIR unchanged');
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

my %new_json = (foo => 'bar', baz => 42, object => bless {this => "cannot be encoded"}, 'Foo');
throws_ok { bmwqemu::save_json_file(\%new_json, 'new_json_file.json') } qr{Cannot encode input.*encountered object.*bless.*cannot be encoded}s;
delete $new_json{object};
ok bmwqemu::save_json_file(\%new_json, 'new_json_file.json'), 'JSON file can be saved with save_json_file';
is_deeply decode_json(path('new_json_file.json')->slurp), \%new_json, 'JSON file written with correct content';

ok bmwqemu::wait_for_one_more_screenshot, 'wait for one more screenshot is ok';

done_testing;

END {
    unlink for qw(vars.json new_json_file.json);
}

1;
