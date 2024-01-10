#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use Term::ANSIColor qw(colorstrip);
use Test::Warnings ':report_warnings';
use Test::MockModule;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use autodie ':all';

use OpenQA::Test::TimeLimit '20';

use IPC::System::Simple qw(system);
use Test::Output qw(combined_like combined_from stderr_from);
use File::Basename;
use File::Path qw(remove_tree rmtree);
use Cwd 'abs_path';
use Mojo::File qw(tempdir path);
use Mojo::JSON qw(decode_json);
use Mojo::Util qw(scope_guard);
use OpenQA::Isotovideo::Utils qw(checkout_wheels handle_generated_assets load_test_schedule);
use OpenQA::Isotovideo::CommandHandler;

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
my $toplevel_dir = abs_path(dirname(__FILE__) . '/..');
my $data_dir = "$toplevel_dir/t/data";
my $pool_dir = "$dir/pool";
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };
mkdir $pool_dir;

# avoid spending time on git clone retries
$ENV{OS_AUTOINST_GIT_RETRY_COUNT} = 0;

sub isotovideo (%args) {
    $args{default_opts} //= 'backend=null';
    $args{opts} //= '';
    $args{exit_code} //= 1;
    chdir "$Bin/..";
    my @cmd = ($^X, "$toplevel_dir/isotovideo", '--workdir', $pool_dir, '-d', $args{default_opts}, split(' ', $args{opts}));
    chdir $pool_dir;
    note "Starting isotovideo with: @cmd";
    qx(cd $toplevel_dir && @cmd);
    my $res = $?;
    return fail 'failed to execute isotovideo: ' . $! if $res == -1;
    return fail 'isotovideo died with signal ' . ($res & 127) if $res & 127;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    return is $res >> 8, $args{exit_code}, 'isotovideo exit code';
}

subtest 'get the version number' => sub {
    chdir "$Bin/..";
    combined_like { system $^X, "$toplevel_dir/isotovideo", '--workdir', $pool_dir, '--version' } qr/Current version is.+\[interface v[0-9]+\]/, 'version printed';
    chdir $pool_dir;
    ok(!-e bmwqemu::STATE_FILE, 'no state file was written');
};

subtest 'color output can be configured via the command-line' => sub {
    chdir($pool_dir);
    unlink('vars.json') if -e 'vars.json';
    my $out = stderr_from { isotovideo(opts => "--color=yes casedir=$data_dir/tests schedule=module1,bar/module2 _exit_after_schedule=1") };
    isnt($out, colorstrip($out), 'logs use colors when requested');
    $out = stderr_from { isotovideo(opts => "--color=no casedir=$data_dir/tests schedule=module1,bar/module2 _exit_after_schedule=1") };
    is($out, colorstrip($out), 'no colors in logs');
};

subtest 'standalone isotovideo without any parameters' => sub {
    chdir $pool_dir;
    unlink 'vars.json' if -e 'vars.json';
    combined_like { isotovideo(opts => '') } qr{CASEDIR variable not set, unknown test case directory}, 'initialization error printed to user';
};

subtest 'standalone isotovideo without vars.json file and only command line parameters' => sub {
    chdir($pool_dir);
    unlink('vars.json') if -e 'vars.json';
    my $out = stderr_from { isotovideo(opts => "casedir=$data_dir/tests schedule=module1,bar/module2 _exit_after_schedule=1") };
    like $out, qr{scheduling.+(module1)}, 'requested module module1 scheduled';
    like $out, qr{scheduling.+(bar/module2)}, 'requested module bar/module2 scheduled';
};

subtest 'standard tests based on simple vars.json file' => sub {
    chdir($pool_dir);
    open(my $var, '>', 'vars.json');
    print $var <<EOV;
{
   "CASEDIR" : "$data_dir/tests",
   "_EXIT_AFTER_SCHEDULE" : 1,
}
EOV
    close($var);
    combined_like { isotovideo } qr/scheduling shutdown/, 'shutdown scheduled';
};

subtest 'isotovideo with custom git repo parameters specified' => sub {
    chdir($pool_dir);
    my $base_state = path(bmwqemu::STATE_FILE);
    $base_state->remove if -e $base_state;
    path('vars.json')->remove if -e 'vars.json';
    path('repo.git')->make_path;
    # some git variables might be set if this test is
    # run during a `git rebase -x 'make test'`
    delete @ENV{qw(GIT_DIR GIT_REFLOG_ACTION GIT_WORK_TREE)};
    my $git_init_output = qx{git init -q --bare repo.git 2>&1};
    is($?, 0, 'initialized test repo') or diag explain $git_init_output;
    # Ensure the checkout folder does not exist so that git clone tries to
    # create a new checkout on every test run
    remove_tree('repo');
    my $log = combined_from { isotovideo(
            opts => "casedir=file://$pool_dir/repo.git#foo needles_dir=$data_dir _exit_after_schedule=1") };
    like $log, qr/Cloning into 'repo'/, 'repo picked up';
    like $log, qr{git URL.*/repo}, 'git repository attempted to be cloned';
    like $log, qr/branch.*foo/, 'branch in git repository attempted to be checked out';
    like $log, qr/fatal:.*/, 'fatal Git error logged';
    unlike $log, qr/No scripts/, 'execution of isotovideo aborted; no follow-up error about empty CASEDIR produced';

    subtest 'fatal error recorded for passing as reason' => sub {
        my $state = decode_json($base_state->slurp);
        if (is(ref $state, 'HASH', 'state file contains object')) {
            is($state->{component}, 'isotovideo', 'state file contains component');
            like($state->{msg}, qr/Unable to clone Git repository/, 'state file contains error message');
        }
    };
};

subtest 'isotovideo with git refspec specified' => sub {
    chdir($pool_dir);
    unlink('vars.json') if -e 'vars.json';
    combined_like { isotovideo(
            opts => "casedir=$data_dir/tests test_git_refspec=deadbeef _exit_after_schedule=1") } qr/Checking.*local.*deadbeef/, 'refspec in local git repository would be checked out';
};

subtest 'isotovideo with wheels' => sub {
    chdir($pool_dir);
    unlink('vars.json') if -e 'vars.json';
    $bmwqemu::scriptdir = "$Bin/..";
    my $case_dir = "$data_dir/tests";
    my $wheels_dir = "$data_dir/wheels_dir";
    my $specfile = path($case_dir)->make_path->child('wheels.yaml');
    $specfile->spew("wheels: [foo/bar]");
    throws_ok { checkout_wheels(
            $case_dir, $wheels_dir) } qr@Invalid.*\Q$specfile\E.*Missing property@, 'invalid YAML causes error';
    $specfile->spew("version: v99\nwheels: [foo/bar]");
    throws_ok { checkout_wheels(
            $case_dir, $wheels_dir) } qr@Unsupported version.*\Q$specfile\E.*@, 'unsupported version';
    $specfile->spew("version: v0.1\nwheels: [https://github.com/foo/bar.git]");
    my $utils_mock = Test::MockModule->new('OpenQA::Isotovideo::Utils');
    my $bmwqemu_mock = Test::MockModule->new('bmwqemu');
    my @repos;
    $utils_mock->redefine(clone_git => sub ($local_path, $clone_url, $clone_depth, $branch, $dir, $dir_variable, $direct_fetch) {
            push @repos, [$clone_url, $branch];
            return 1;
    });
    checkout_wheels($case_dir, $wheels_dir);
    is($repos[0][0], 'https://github.com/foo/bar.git', 'repo with full URL');
    is(scalar @repos, 1, 'one wheel');
    $specfile->spew("version: v0.1\nwheels: [https://github.com/foo/bar.git#branch]");
    checkout_wheels($case_dir, $wheels_dir);
    is($repos[1][0], 'https://github.com/foo/bar.git', 'repo URL with branch');
    is($repos[1][1], 'branch', 'repo URL with branch');
    is(scalar @repos, 2, 'one wheel');
    $specfile->spew("version: v0.1\nwheels: [foo/bar]");
    checkout_wheels($case_dir, $wheels_dir);
    is(scalar @repos, 3, 'one wheel');
    is($repos[2][0], 'https://github.com/foo/bar.git', 'only wheel');
    $specfile->spew("version: v0.1\nwheels: [foo/bar, spam/eggs]");
    checkout_wheels($case_dir, $wheels_dir);
    is($repos[4][0], 'https://github.com/spam/eggs.git', 'second wheel');
    is(scalar @repos, 5, 'two wheels');
    $specfile->remove;
    is(checkout_wheels($case_dir, $wheels_dir), 1, 'no wheels');
    is(scalar @repos, 5, 'git never called');

    # also verify that isotovideo invokes the wheel code correctly
    $specfile->spew("version: v0.1\nwheels: [copy/writer]");

    my @warnings;
    my @infos;
    my @diags;
    $bmwqemu_mock->redefine(fctwarn => sub { push @warnings, $_[0] });
    $bmwqemu_mock->redefine(fctinfo => sub { push @infos, $_[0] });
    $bmwqemu_mock->redefine(diag => sub { push @diags, $_[0] });

    my @tests = ("$data_dir/wheels_dir", undef);
    for my $i (0 .. $#tests) {
        my $dir = $tests[$i];
        chdir $pool_dir;
        $wheels_dir = $dir // $pool_dir;
        $bmwqemu::vars{CASEDIR} = $case_dir;
        $bmwqemu::vars{PRODUCTDIR} = $pool_dir;
        $bmwqemu::vars{SCHEDULE} = "pen/ink$i";
        $bmwqemu::vars{WHEELS_DIR} = $dir;

        subtest "wheels in $wheels_dir" => sub {
            @diags = ();
            path($wheels_dir, 'writer', 'lib', 'Copy', 'Writer')->make_path->child("Content$i.pm")->spew(<<~"EOM");
            package Copy::Writer::Content$i;
            use Mojo::Base 'Exporter';
            our \@EXPORT_OK = qw(write);
            sub write { "val$i"};
            1;
            EOM
            path($wheels_dir, 'writer', 'tests', 'pen')->make_path->child("ink$i.pm")->spew("use Mojo::Base 'basetest'; use Copy::Writer::Content$i 'write'; sub run {}; 1");
            is(0, checkout_wheels($case_dir, $wheels_dir), 'wheels checkout out');
            load_test_schedule;
            like $diags[0], qr/scheduling ink$i/, 'module from the wheel scheduled';
            my $ret = eval "Copy::Writer::Content${i}::write()";
            is $ret, "val$i", 'called function in wheel library returns expected value';
            rmtree "$wheels_dir/writer";
        };
    }
    $specfile->remove;

    subtest 'non-existant WHEELS_DIR' => sub {
        my $runner_mock = Test::MockModule->new('OpenQA::Isotovideo::Runner');
        $runner_mock->redefine(checkout_wheels => sub { 1 });
        $runner_mock->redefine(checkout_git_repo_and_branch => sub { 1 });
        $runner_mock->redefine(checkout_git_refspec => sub { 1 });
        my $wheels_dir = '/does/not/exist';
        $bmwqemu::vars{WHEELS_DIR} = $wheels_dir;
        throws_ok { OpenQA::Isotovideo::Runner->checkout_code } qr{WHEELS_DIR '$wheels_dir' does not exist}, "Invalid WHEELS_DIR dies";
    };
};

subtest 'productdir variable relative/absolute' => sub {
    chdir($pool_dir);
    unlink('vars.json') if -e 'vars.json';
    combined_like { isotovideo(
            opts => "casedir=$data_dir/tests _exit_after_schedule=1 productdir=$data_dir/tests") } qr/\d* scheduling.*shutdown/, 'schedule has been evaluated';
    mkdir('product') unless -e 'product';
    mkdir('product/foo') unless -e 'product/foo';
    symlink("$data_dir/tests/main.pm", "$pool_dir/product/foo/main.pm") unless -e "$pool_dir/product/foo/main.pm";
    combined_like { isotovideo(opts => "casedir=$data_dir/tests _exit_after_schedule=1 productdir=product/foo") } qr/\d* scheduling.*shutdown/, 'schedule can still be found';
    unlink("$pool_dir/product/foo/main.pm");
    mkdir("$data_dir/tests/product") unless -e "$data_dir/tests/product";
    symlink("$data_dir/tests/main.pm", "$data_dir/tests/product/main.pm") unless -e "$data_dir/tests/product/main.pm";
    # additionally testing correct schedule for our "integration tests" mode
    my $log = combined_from { isotovideo(opts => "casedir=$data_dir/tests _exit_after_schedule=1 productdir=product integration_tests=1") };
    like $log, qr/\d* scheduling.*shutdown/, 'schedule can still be found for productdir relative to casedir';
    unlike $log, qr/assert_screen_fail_test/, 'assert screen test not scheduled';
};

subtest 'exit status from test results' => sub {
    # dummy isotovideo invocations
    chdir($pool_dir);
    path(bmwqemu::STATE_FILE)->remove if -e bmwqemu::STATE_FILE;
    path('vars.json')->remove if -e 'vars.json';
    path('serial0')->touch;

    subtest 'no test scheduled' => sub {
        path('testresults/')->remove_tree;
        my $log = combined_from { isotovideo(
                default_opts => '--exit-status-from-test-results backend=null',
                opts => "casedir=$data_dir/empty_test_distribution", exit_code => 100) };
    };

    subtest 'tests scheduled' => sub {
        path('testresults/')->remove_tree;
        my $module_basename = 'failing_module';
        my $module = "tests/$module_basename";
        my $log = combined_from { isotovideo(
                default_opts => '--exit-status-from-test-results backend=null',
                opts => "casedir=$data_dir/tests schedule=$module", exit_code => 101) };

        like $log, qr/scheduling $module_basename $module\.pm/, 'module scheduled';
        like $log, qr/Test result \[testresults\/result\-$module_basename\.json\] fail/, 'failed test module report';
    };

    subtest 'softfailed module' => sub {
        path('testresults/')->remove_tree;
        my $module_basename = 'softfail_module';
        my $module = "tests/$module_basename";
        my $log = combined_from { isotovideo(
                default_opts => '--exit-status-from-test-results backend=null',
                opts => "casedir=$data_dir/tests schedule=$module", exit_code => 0) };

        like $log, qr/scheduling $module_basename $module\.pm/, 'module scheduled';
        like $log, qr/Test result \[testresults\/result\-$module_basename\.json\] softfail/, 'soft failed test module report';
    };
};

subtest 'upload assets on demand even in failed jobs' => sub {
    # qemu isotovideo invocation
    chdir($pool_dir);
    path(bmwqemu::STATE_FILE)->remove if -e bmwqemu::STATE_FILE;
    path('vars.json')->remove if -e 'vars.json';
    my $module = 'tests/failing_module';
    my $log = combined_from { isotovideo(
            opts => "casedir=$data_dir/tests schedule=$module force_publish_hdd_1=foo.qcow2 qemu_no_kvm=1 arch=i386 backend=qemu qemu=i386 novideo=1", exit_code => 0) };
    like $log, qr/scheduling failing_module $module\.pm/, 'module scheduled';
    like $log, qr/qemu-img.*foo.qcow2/, 'requested image is published even though the job failed';
    ok(-e $pool_dir . '/assets_public/foo.qcow2', 'published image exists');
    ok(!-e bmwqemu::STATE_FILE, 'no fatal error recorded') or die path(bmwqemu::STATE_FILE)->slurp;
};

subtest 'load test success when casedir and productdir are relative path' => sub {
    # qemu isotovideo invocation
    chdir($pool_dir);
    path(bmwqemu::STATE_FILE)->remove if -e bmwqemu::STATE_FILE;
    path('vars.json')->remove if -e 'vars.json';
    mkdir('my_cases') unless -e 'my_cases';
    symlink("$data_dir/tests/lib", 'my_cases/lib') unless -e 'my_cases/lib';
    mkdir('my_cases/products') unless -e 'my_cases/products';
    mkdir('my_cases/products/foo') unless -e 'my_cases/foo';
    symlink("$data_dir/tests/tests", 'my_cases/tests') unless -e 'my_cases/tests';
    symlink("$data_dir/tests/needles", 'my_cases/products/foo/needles') unless -e 'my_cases/products/foo/needles';
    my $module = 'tests/failing_module';
    my $log = combined_from { isotovideo(opts => "casedir=my_cases productdir=my_cases/products/foo schedule=$module", exit_code => 0) };
    unlike $log, qr/\[warn\]/, 'no warnings';
    like $log, qr/scheduling failing_module/, 'schedule can still be found';
    like $log, qr/\d* loaded 4 needles/, 'loaded needles successfully';
};


# mock backend/driver
{
    package FakeBackendDriver;    # uncoverable statement
    sub new ($class, $name) {
        my $self = bless({class => $class}, $class);
        require "backend/$name.pm";
        $self->{backend} = "backend::$name"->new();
        return $self;
    }
    sub extract_assets ($self, @args) { $self->{backend}->do_extract_assets(@args) }
}

subtest 'publish assets' => sub {
    $bmwqemu::vars{BACKEND} = 'qemu';
    $bmwqemu::backend = FakeBackendDriver->new('qemu');
    my $publish_asset = $pool_dir . '/assets_public/publish_test.qcow2';

    my $command_handler = OpenQA::Isotovideo::CommandHandler->new();
    subtest publish => sub {
        $bmwqemu::vars{PUBLISH_HDD_1} = 'publish_test.qcow2';
        $command_handler->test_completed(1);
        my $return_code;
        my $out = combined_from { $return_code = handle_generated_assets($command_handler, 1) };
        like $out, qr/convert.*publish_test.qcow2/, 'publication of asset';
        is $return_code, 0, 'The asset was uploaded successfully' or die path(bmwqemu::STATE_FILE)->slurp;
        ok(-e $publish_asset, 'test.qcow2 image exists');
        unlink $publish_asset;
    };

    subtest 'upload the asset even in an incomplete job' => sub {
        $bmwqemu::vars{FORCE_PUBLISH_HDD_1} = 'force_publish_test.qcow2';
        $bmwqemu::vars{PUBLISH_HDD_1} = 'publish_test.qcow2';
        $command_handler->test_completed(0);
        my $return_code;
        my $out = combined_from { $return_code = handle_generated_assets($command_handler, 1) };
        like $out, qr/Requested to force the publication/, 'forced publication of asset';
        is $return_code, 0, 'The asset was uploaded successfully' or die path(bmwqemu::STATE_FILE)->slurp;
        my $force_publish_asset = $pool_dir . '/assets_public/force_publish_test.qcow2';
        ok(-e $force_publish_asset, 'test.qcow2 image exists');
        ok(!-e $pool_dir . '/assets_public/publish_test.qcow2', 'the asset defined by PUBLISH_HDD_X would not be generated in an incomplete job');
        delete $bmwqemu::vars{FORCE_PUBLISH_HDD_1};
    };

    subtest 'unclean shutdown' => sub {
        $bmwqemu::vars{PUBLISH_HDD_1} = 'publish_test.qcow2';
        $command_handler->test_completed(1);
        my $return_code;
        my $out = combined_from { $return_code = handle_generated_assets($command_handler, 0) };
        like $out, qr/unable to handle generated assets:/, 'correct output';
        is $return_code, 1, 'Unsuccessful handle_generated_assets' or die path(bmwqemu::STATE_FILE)->slurp;
        ok !-e $publish_asset, 'test.qcow2 does not exist';
    };

    subtest 'unsuccessful do_extract_assets' => sub {
        my $mock = Test::MockModule->new('backend::qemu');
        $mock->redefine(do_extract_assets => sub (@) { die "oops" });
        $bmwqemu::vars{PUBLISH_HDD_1} = 'publish_test.qcow2';
        $command_handler->test_completed(1);
        my $return_code;
        my $out = combined_from { $return_code = handle_generated_assets($command_handler, 1) };
        like $out, qr/unable to extract assets: oops/, 'correct output';
        is $return_code, 1, 'Unsuccessful handle_generated_assets' or die path(bmwqemu::STATE_FILE)->slurp;
        ok !-e $publish_asset, 'test.qcow2 does not exist';
    };

    subtest 'UEFI & PUBLISH_PFLASH_VARS' => sub {
        $bmwqemu::vars{PUBLISH_HDD_1} = 'publish_test.qcow2';
        $bmwqemu::vars{UEFI} = 1;
        $bmwqemu::vars{PUBLISH_PFLASH_VARS} = 'opensuse-15.3-x86_64-20220617-4-kde@uefi-uefi-vars.qcow2';
        $bmwqemu::vars{UEFI_PFLASH_CODE} = '/usr/share/qemu/ovmf-x86_64-ms-code.bin';
        $bmwqemu::vars{UEFI_PFLASH_VARS} = '/usr/share/qemu/ovmf-x86_64-ms-vars.bin';
        my $mock = Test::MockModule->new('OpenQA::Qemu::Proc');
        $mock->redefine(export_blockdev_images => sub ($self, $filter, $img_dir, $name, $qemu_compress_qcow) {
                return 1;
        });
        $command_handler->test_completed(1);
        my $return_code;
        my $out = combined_from { $return_code = handle_generated_assets($command_handler, 1) };
        like $out, qr/Extracting.*pflash-vars/, 'correct output';
        is $return_code, 0, 'Successful handle_generated_assets' or die path(bmwqemu::STATE_FILE)->slurp;
        ok !-e $publish_asset, 'test.qcow2 does not exist';
    };
};

done_testing();

END {
    unlink "./serial0" if -e "./serial0";
    rmtree "$Bin/data/tests/product";
    rmtree "$data_dir/wheels_dir/writer";
    rmtree "$pool_dir/writer";
    unlink("$data_dir/tests/wheels.yaml") if -e "$data_dir/tests/wheels.yaml";
}
