#!/usr/bin/perl

use Test::Most;
use Test::Warnings qw(warning :report_warnings);
use autodie ':all';
use Test::Output qw(combined_like stderr_like);
use File::Path qw(remove_tree rmtree);
use Cwd 'abs_path';
use Mojo::File qw(tempdir path);
use Mojo::JSON qw(decode_json);
use Mojo::Util qw(scope_guard);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '10';
use OpenQA::Isotovideo::Utils qw(git_rev_parse checkout_git_refspec load_test_schedule);

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
my $pool_dir = "$dir/pool";
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };
mkdir $pool_dir;


is git_rev_parse($dir), 'UNKNOWN', 'non-git repo detected as such';
stderr_like { checkout_git_refspec($dir, 'MY_REFSPEC_VARIABLE') }
qr/git hash in.*UNKNOWN/, 'checkout_git_refspec also detects UNKNOWN';
my $toplevel_dir = "$Bin/..";
my $version = -e "$toplevel_dir/.git" ? qr/[a-f0-9]+/ : qr/UNKNOWN/;
like git_rev_parse($toplevel_dir), $version, 'can parse working copy version (if it is git)';

subtest 'error handling when loading test schedule' => sub {
    chdir($dir);
    my $base_state = path(bmwqemu::STATE_FILE);
    subtest 'no schedule at all' => sub {
        $base_state->remove;
        $bmwqemu::vars{CASEDIR} = $bmwqemu::vars{PRODUCTDIR} = $dir;
        throws_ok { load_test_schedule } qr/'SCHEDULE' not set and/, 'error logged';
        my $state = decode_json($base_state->slurp);
        if (is(ref $state, 'HASH', 'state file contains object')) {
            is($state->{component}, 'tests', 'state file contains component message');
            like($state->{msg}, qr/unable to load main\.pm/, 'state file contains error message');
        }
    };
    subtest 'unable to load test module' => sub {
        $base_state->remove;
        my $module = 'foo/bar';
        $bmwqemu::vars{SCHEDULE} = $module;
        combined_like {
            warning { throws_ok { load_test_schedule } qr/Can't locate $module\.pm/, 'error logged' }
        } qr/Can't locate $module\.pm/, 'debug message logged';
        my $state = decode_json($base_state->slurp);
        if (is(ref $state, 'HASH', 'state file contains object')) {
            is($state->{component}, 'tests', 'state file contains component');
            like($state->{msg}, qr/unable to load foo\/bar\.pm/, 'state file contains error message');
        }
    };
    subtest 'invalid productdir' => sub {
        $bmwqemu::vars{SCHEDULE} = undef;
        $bmwqemu::vars{PRODUCTDIR} = 'not/found';
        throws_ok { load_test_schedule } qr/PRODUCTDIR.*invalid/, 'error logged';
    };
};

is_deeply OpenQA::Isotovideo::Utils::_store_asset(0, 'foo.qcow2', 'bar'), {hdd_num => 0, name => 'foo.qcow2', dir => 'bar', format => 'qcow2'}, '_store_asset returns correct parameters';

done_testing;
