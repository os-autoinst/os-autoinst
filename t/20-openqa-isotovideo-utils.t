#!/usr/bin/perl

use Test::Most;
use Test::Warnings qw(warning :report_warnings);
use autodie ':all';
use Test::Output qw(combined_like);
use File::Path qw(remove_tree rmtree);
use Cwd 'abs_path';
use Mojo::File qw(tempdir path);
use Mojo::JSON qw(decode_json);
use Mojo::Util qw(scope_guard);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '10';
use OpenQA::Isotovideo::Utils qw(load_test_schedule);

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
my $pool_dir = "$dir/pool";
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };
mkdir $pool_dir;

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
            like($state->{msg}, qr@unable to load foo/bar,@, 'state file contains error message');
        }
    };
    subtest 'invalid productdir' => sub {
        $bmwqemu::vars{SCHEDULE} = undef;
        $bmwqemu::vars{PRODUCTDIR} = 'not/found';
        throws_ok { load_test_schedule } qr/PRODUCTDIR.*invalid/, 'error logged';
    };
};

done_testing;
