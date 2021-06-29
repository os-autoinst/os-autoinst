#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '20';
use autodie ':all';
use IPC::System::Simple qw(system);
use Test::Output qw(combined_like combined_from);
use File::Basename;
use File::Path qw(remove_tree rmtree);
use Cwd 'abs_path';
use Mojo::File qw(tempdir path);
use Mojo::JSON qw(decode_json);
use Mojo::Util qw(scope_guard);
use OpenQA::Isotovideo::Utils qw(load_test_schedule handle_generated_assets);
use OpenQA::Isotovideo::CommandHandler;

my $dir          = tempdir("/tmp/$FindBin::Script-XXXX");
my $toplevel_dir = abs_path(dirname(__FILE__) . '/..');
my $data_dir     = "$toplevel_dir/t/data";
my $pool_dir     = "$dir/pool";
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };
mkdir $pool_dir;

sub isotovideo (%args) {
    $args{default_opts} //= 'backend=null';
    $args{opts}         //= '';
    $args{exit_code}    //= 1;
    my @cmd = ($^X, "$toplevel_dir/isotovideo", '-d', $args{default_opts}, split(' ', $args{opts}));
    note "Starting isotovideo with: @cmd";
    my $output = qx(@cmd);
    my $res    = $?;
    return fail 'failed to execute isotovideo: ' . $!         if $res == -1;    # uncoverable statement
    return fail 'isotovideo died with signal ' . ($res & 127) if $res & 127;    # uncoverable statement
    is $res >> 8, $args{exit_code}, 'isotovideo exit code';
    return $output;
}

subtest 'get the version number' => sub {
    # Make sure we're in a folder we can't write to, no base_state.json should be created here
    chdir('/');
    combined_like { system $^X, "$toplevel_dir/isotovideo", '--version' } qr/Current version is.+\[interface v[0-9]+\]/, 'version printed';
    ok(!-e bmwqemu::STATE_FILE, 'no state file was written');
};

subtest 'standalone isotovideo without vars.json file and only command line parameters' => sub {
    chdir($pool_dir);
    unlink('vars.json') if -e 'vars.json';
    combined_like { isotovideo(opts => "casedir=$data_dir/tests schedule=foo,bar/baz _exit_after_schedule=1") } qr{scheduling.+(foo|bar/baz)}, 'requested modules scheduled';
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
    $base_state->remove       if -e $base_state;
    path('vars.json')->remove if -e 'vars.json';
    path('repo.git')->make_path;
    my $git_init_output = qx{git init -q --bare repo.git 2>&1};
    is($?, 0, 'initialized test repo') or diag explain $git_init_output;
    # Ensure the checkout folder does not exist so that git clone tries to
    # create a new checkout on every test run
    remove_tree('repo');
    my $log = combined_from { isotovideo(
            opts => "casedir=file://$pool_dir/repo.git#foo needles_dir=$data_dir _exit_after_schedule=1") };
    like $log,   qr/Cloning into 'repo'/, 'repo picked up';
    like $log,   qr{git URL.*/repo},      'git repository attempted to be cloned';
    like $log,   qr/branch.*foo/,         'branch in git repository attempted to be checked out';
    like $log,   qr/fatal:.*/,            'fatal Git error logged';
    unlike $log, qr/No scripts/,          'execution of isotovideo aborted; no follow-up error about empty CASEDIR produced';

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

subtest 'productdir variable relative/absolute' => sub {
    chdir($pool_dir);
    unlink('vars.json') if -e 'vars.json';
    combined_like { isotovideo(
            opts => "casedir=$data_dir/tests _exit_after_schedule=1 productdir=$data_dir/tests") } qr/\d* scheduling.*shutdown/, 'schedule has been evaluated';
    mkdir('product')                                                    unless -e 'product';
    mkdir('product/foo')                                                unless -e 'product/foo';
    symlink("$data_dir/tests/main.pm", "$pool_dir/product/foo/main.pm") unless -e "$pool_dir/product/foo/main.pm";
    combined_like { isotovideo(opts => "casedir=$data_dir/tests _exit_after_schedule=1 productdir=product/foo") } qr/\d* scheduling.*shutdown/, 'schedule can still be found';
    unlink("$pool_dir/product/foo/main.pm");
    mkdir("$data_dir/tests/product")                                      unless -e "$data_dir/tests/product";
    symlink("$data_dir/tests/main.pm", "$data_dir/tests/product/main.pm") unless -e "$data_dir/tests/product/main.pm";
    combined_like { isotovideo(opts => "casedir=$data_dir/tests _exit_after_schedule=1 productdir=product") } qr/\d* scheduling.*shutdown/, 'schedule can still be found for productdir relative to casedir';
};

subtest 'upload assets on demand even in failed jobs' => sub {
    chdir($pool_dir);
    path(bmwqemu::STATE_FILE)->remove if -e bmwqemu::STATE_FILE;
    path('vars.json')->remove         if -e 'vars.json';
    my $module = 'tests/failing_module';
    my $log    = combined_from { isotovideo(
            opts => "casedir=$data_dir/tests schedule=$module force_publish_hdd_1=foo.qcow2 qemu_no_kvm=1 arch=i386 backend=qemu qemu=i386", exit_code => 0) };
    like $log, qr/scheduling failing_module $module\.pm/, 'module scheduled';
    like $log, qr/qemu-img.*foo.qcow2/,                   'requested image is published even though the job failed';
    ok(-e $pool_dir . '/assets_public/foo.qcow2', 'published image exists');
    ok(!-e $pool_dir . '/base_state.json',        'no fatal error recorded');
};

# mock backend/driver
{
    package FakeBackendDriver;
    sub new ($class, $name) {
        my $self = bless({class => $class}, $class);
        require "backend/$name.pm";
        $self->{backend} = "backend::$name"->new();
        return $self;
    }
    sub extract_assets ($self) {
        $self->{backend}->do_extract_assets(@_);
    }
}

subtest 'upload the asset even in an incomplete job' => sub {
    my $command_handler = OpenQA::Isotovideo::CommandHandler->new();
    $bmwqemu::vars{BACKEND}             = 'qemu';
    $bmwqemu::vars{NUMDISKS}            = 1;
    $bmwqemu::vars{FORCE_PUBLISH_HDD_1} = 'force_publish_test.qcow2';
    $bmwqemu::vars{PUBLISH_HDD_1}       = 'publish_test.qcow2';
    $command_handler->test_completed(0);
    $bmwqemu::backend = FakeBackendDriver->new('qemu');
    my $return_code;
    combined_like {
        $return_code = handle_generated_assets($command_handler, 1)
    } qr/Requested to force the publication/, 'forced publication of asset';
    is $return_code, 0, 'The asset was uploaded success';
    ok(-e $pool_dir . '/assets_public/force_publish_test.qcow2', 'test.qcow2 image exists');
    ok(!-e $pool_dir . '/assets_public/publish_test.qcow2',      'the asset defined by PUBLISH_HDD_X would not be generated in an incomplete job');
};

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
        combined_like { throws_ok {
                load_test_schedule } qr/Can't locate $module\.pm/, 'error logged' } qr/error on $module\.pm: Can't locate $module\.pm/, 'debug message logged';
        my $state = decode_json($base_state->slurp);
        if (is(ref $state, 'HASH', 'state file contains object')) {
            is($state->{component}, 'tests', 'state file contains component');
            like($state->{msg}, qr/unable to load foo\/bar\.pm/, 'state file contains error message');
        }
    };
};

subtest 'load test success when casedir and productdir are relative path' => sub {
    chdir($pool_dir);
    path(bmwqemu::STATE_FILE)->remove if -e bmwqemu::STATE_FILE;
    path('vars.json')->remove         if -e 'vars.json';
    mkdir('my_cases')                                                   unless -e 'my_cases';
    symlink("$data_dir/tests/lib", 'my_cases/lib')                      unless -e 'my_cases/lib';
    mkdir('my_cases/products')                                          unless -e 'my_cases/products';
    mkdir('my_cases/products/foo')                                      unless -e 'my_cases/foo';
    symlink("$data_dir/tests/tests", 'my_cases/tests')                  unless -e 'my_cases/tests';
    symlink("$data_dir/tests/needles", 'my_cases/products/foo/needles') unless -e 'my_cases/products/foo/needles';
    my $module = 'tests/failing_module';
    my $log    = combined_from { isotovideo(opts => "casedir=my_cases productdir=my_cases/products/foo schedule=$module", exit_code => 0) };
    like $log, qr/scheduling failing_module/, 'schedule can still be found';
    like $log, qr/\d* loaded 4 needles/,      'loaded needles successfully';
};

done_testing();

END {
    rmtree "$Bin/data/tests/product";
}
