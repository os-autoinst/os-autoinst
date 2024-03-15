#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(warning :report_warnings);
use autodie ':all';
use Test::Output qw(combined_like combined_from stderr_like);
use File::Path qw(remove_tree rmtree);
use Cwd 'abs_path';
use Mojo::File qw(tempdir path);
use Mojo::JSON qw(decode_json);
use Mojo::Util qw(scope_guard);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '10';
use OpenQA::Isotovideo::Utils qw(git_rev_parse checkout_git_refspec
  handle_generated_assets
  git_remote_url load_test_schedule);
use OpenQA::Isotovideo::CommandHandler;

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
note 'call again git_rev_parse under different user (if available)';
my $sudo_user = $ENV{OS_AUTOINST_TEST_SECOND_USER} // 'nobody';
qx{command -v sudo >/dev/null && sudo --non-interactive -u $sudo_user true};
like git_rev_parse($toplevel_dir, "sudo -u $sudo_user"), $version, 'can parse git version as different user' if $? == 0;    # uncoverable statement

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

    subtest 'prevent upload assets when publish_hdd is none with case-insensitive' => sub {
        my $command_handler = OpenQA::Isotovideo::CommandHandler->new();
        my @possible_values = qw(none None NONE);
        $bmwqemu::vars{BACKEND} = 'qemu';
        for my $v (@possible_values) {
            $bmwqemu::vars{PUBLISH_HDD_1} = $v;
            $command_handler->test_completed(1);
            my $return_code;
            my $log = combined_from { $return_code = handle_generated_assets($command_handler, 1) };
            like $log, qr/Asset upload is skipped for PUBLISH_HDD/, "Upload is skipped when PUBLISH_HDD_1 is $v";
        }
    };
};

is_deeply OpenQA::Isotovideo::Utils::_store_asset(0, 'foo.qcow2', 'bar'), {hdd_num => 0, name => 'foo.qcow2', dir => 'bar', format => 'qcow2'}, '_store_asset returns correct parameters';

subtest 'git repo url' => sub {
    my $gitrepo = "$dir/git";
    mkdir "$dir/git";
    qx{git -C "$gitrepo" init >/dev/null 2>&1};
    qx{git -C "$gitrepo" remote add origin foo >/dev/null};
    my $url = git_remote_url($gitrepo);
    is $url, 'foo', 'git_remote_url works correctly';
    qx{git -C "$gitrepo" remote rm origin >/dev/null};
    $url = git_remote_url($gitrepo);
    is $url, 'UNKNOWN (origin remote not found)', 'git_remote_url with no "origin" remote';
    $url = git_remote_url($dir);
    is $url, 'UNKNOWN (no .git found)', 'git_remote_url for a non-git dir';
};

done_testing;
