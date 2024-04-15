#!/usr/bin/perl
#
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Mojo::JSON qw(decode_json);
use Mojo::File qw(path tempdir);
use Mojo::Util qw(scope_guard);
use File::Path qw(rmtree);
use FindBin '$Bin';
use Test::Output qw(combined_from combined_like combined_unlike);
use Test::Mock::Time;
use OpenQA::Isotovideo::Utils qw(checkout_git_repo_and_branch git_remote_url limit_git_cache_dir);
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Warnings ':report_warnings';

my $tmpdir = tempdir("/tmp/$FindBin::Script-XXXX");
my $git_repo = 'tmpgitrepo';
my $git_dir = "$tmpdir/$git_repo";
my $clone_dir = "$Bin/$git_repo";

chdir $Bin;
# some git variables might be set if this test is
# run during a `git rebase -x 'make test'`
delete @ENV{qw(GIT_DIR GIT_REFLOG_ACTION GIT_WORK_TREE)};

subtest 'failure to clone results once' => sub {
    my $utils_mock = Test::MockModule->new('OpenQA::Isotovideo::Utils');
    my $failed_once = 0;
    $utils_mock->redefine(clone_git => sub (@) {
            unless ($failed_once++) {
                bmwqemu::diag "Connection reset by peer";
                die "Unable to clone Git repository";
            }
            bmwqemu::diag "Cloning into ...";
            return 1;
    });
    combined_like { checkout_git_repo_and_branch('test', repo => 'https://github.com/foo/bar.git', retry_count => 3) } qr@Clone failed, retries left: 3 of 3@;
};

subtest 'failure to clone results in repeated attempts' => sub {
    my $utils_mock = Test::MockModule->new('OpenQA::Isotovideo::Utils');
    my $failed_once = 0;
    $utils_mock->redefine(clone_git => sub (@) {
            bmwqemu::diag "Connection reset by peer";
            die "Unable to clone Git repository";
    });
    my $out = combined_from {
        eval { checkout_git_repo_and_branch('test', repo => 'https://github.com/foo/bar.git') };
    };
    my $error = $@;
    like $error, qr@Unable to clone Git repository@;
    like $out, qr@Clone failed, retries left: 0 of 2@, 'all retry attempts used';
};

my $head = initialize_git_repo();
my $case_dir_ok = "file://$git_dir#$head";
my $case_dir = "file://$git_dir#abcdef";

subtest 'failing clone' => sub {
    %bmwqemu::vars = (CASEDIR => $case_dir);
    my $path;
    my $out = combined_from {
        eval { $path = checkout_git_repo_and_branch('CASEDIR', retry_count => 0) };
    };
    my $error = $@;
    like $error, qr{Could not find 'abcdef' in complete history in cloned Git repository '\Q$case_dir\E'}, "Error message when trying to clone wrong git hash";
    like $out, qr{Fetching 'abcdef' from origin manually}s, 'manual git fetch for revspec was attempted';
    like $out, qr{Cloning git URL.*Fetching more remote objects.*Enumerating objects}s, 'git fetch with --depth option was attempted';
};

subtest 'successful clone' => sub {
    my $path;

    subtest 'fetch commit manually but directly' => sub {
        cleanup();
        %bmwqemu::vars = (CASEDIR => $case_dir_ok);
        my $out = combined_from { $path = checkout_git_repo_and_branch('CASEDIR') };
        is $path, $clone_dir, 'checkout_git_repo_and_branch returned correct path';
        like $out, qr{Cloning git URL.*Fetching '.*' from origin manually}s, 'git clone and fetch were called again to fetch rev manually';
        unlike $out, qr{Cloning git URL.*Fetching more remote objects}s, 'no need to resort to general fetch';
    };
    subtest 'skip cloning when repo already exists (not even switching to the correct branch)' => sub {
        %bmwqemu::vars = (CASEDIR => $case_dir_ok);
        my $out = combined_from { $path = checkout_git_repo_and_branch('CASEDIR') };
        is $path, $clone_dir, 'checkout_git_repo_and_branch with existing local directory returned correct path';
        like $out, qr{Skipping to clone.*tmpgitrepo already exists}, 'Log says that local directory already exists';
    };
    subtest 'fetch commit manually by fetching repeatedly with increasing depth' => sub {
        cleanup();
        %bmwqemu::vars = (CASEDIR => $case_dir_ok);
        my $out = combined_from { $path = checkout_git_repo_and_branch('CASEDIR', direct_fetch => 0) };
        is $path, $clone_dir, 'checkout_git_repo_and_branch returned correct path';
        like $out, qr{Cloning git URL.*Fetching more remote objects}s, 'git clone and fetch were called again to fetch rev manually';
    };

    eval { bmwqemu::save_vars(no_secret => 1) };
    is($@, '', 'serialization successful');
};

subtest 'cloning with caching' => sub {
    # setup temp dir for cache and configure using it
    my $start_time = time;
    my $git_cache_dir_from_env = $ENV{OS_AUTOINST_TEST_GIT_CACHE_DIR};
    my $git_cache_dir = $git_cache_dir_from_env ? path($git_cache_dir_from_env) : tempdir('temp-git-caching-XXXXX');
    $git_cache_dir = $git_cache_dir->make_path->realpath;
    note "temp dir for cache: $git_cache_dir";
    $bmwqemu::vars{GIT_CACHE_DIR} = $git_cache_dir->to_string;

    # make up parameters for cloning
    my ($orga, $repo, $suffix) = (qw(os-autoinst os-autoinst-wheel-launcher .git));
    my $rev = '742bd0570a5d086be12fecb3b108bff15f4cb202';
    my $url = Mojo::URL->new("https://github.com/$orga/$repo$suffix");
    ($orga, $repo, $rev, $suffix, $url) = ($tmpdir, $git_repo, $head, '', Mojo::URL->new("file://$git_dir"))
      unless $ENV{OS_AUTOINST_TEST_GIT_ONLINE};

    my $orga_cache_dir = $git_cache_dir->child($orga);
    my $repo_cache_dir = $orga_cache_dir->child("$repo$suffix");
    my @clone_args = ($repo, $url, 1, $rev, $repo, '?', 1);
    my $clone = sub {
        combined_from { ok OpenQA::Isotovideo::Utils::clone_git(@clone_args), 'cloned repo' };
    };

    # setup temp dir for the working tree
    my $pwd = tempdir('temp-git-working-tree-XXXXX')->make_path;
    note "temp dir for working trees: $pwd";
    my $working_tree_dir = path($repo);
    chdir $pwd;
    my $chdir_guard = scope_guard sub { chdir '..'; $git_cache_dir->remove_tree unless $git_cache_dir_from_env };

    # clone the same repo twice
    my $index;
    my $check_working_tree = sub {
        ok -f $working_tree_dir->child('README.md'), 'working tree has been created / is present';
        my $working_tree_config = $working_tree_dir->child('.git/config')->slurp;
        ok index($working_tree_config, $repo_cache_dir), 'working tree config refers to cache dir';
        is git_remote_url($working_tree_dir), $url, 'remote URL still computed as before';
    };
    my $handle_du = sub ($exit_status, $output) {
        fail "du failed with exit status $exit_status: $output" if $exit_status != 0;
    };
    subtest 'first clone' => sub {
        my $out = $clone->();
        like $out, qr/Creating bare repository for caching/, 'created bare repo for caching';
        like $out, qr/Updating Git cache/, 'updated bare repo';
        ok -d $repo_cache_dir, 'cache dir created';
        is $repo_cache_dir->child("refs/heads/$rev")->slurp, "$rev\n", 'cache dir has ref';
        $check_working_tree->();
    };
    subtest 'second clone' => sub {
        $working_tree_dir->remove_tree;    # ensure we actually clone the repo again
        my $out = $clone->();
        unlike $out, qr/Creating bare repository for caching/, 'no new bare repo created';
        like $out, qr/Updating Git cache/, 'updated bare repo';
        $check_working_tree->();
    };
    subtest 'clone default branch' => sub {
        $working_tree_dir->remove_tree;    # ensure we actually clone the repo again
        my @clone_args = ($repo, $url, 1, '', $repo, '?', 1);
        combined_like { ok OpenQA::Isotovideo::Utils::clone_git(@clone_args), 'cloned repo with default branch' }
          qr/master/, 'detected master branch';
    };

    subtest 'index creation' => sub {
        $index = decode_json($git_cache_dir->child('index.json')->slurp);
        is ref $index, 'HASH', 'index is hash' or return;
        my $repo_path = $ENV{OS_AUTOINST_TEST_GIT_ONLINE} ? "/$orga/$repo$suffix" : "$orga/$repo";
        my $repo_entry = $index->{$repo_path};
        is ref $repo_entry, 'HASH', "entry for '$repo_path' exists" or return;
        cmp_ok $repo_entry->{size}, '>', 0, 'valid size assigned';
        cmp_ok $repo_entry->{last_use}, '>=', $start_time, 'valid last use assigned';
    } or diag explain $index;

    subtest 'limit size of cache directory' => sub {
        sleep 10;    # simulate time has passed via "Test::Mock::Time"

        # pretend we have made other Git checkouts
        my $fake_checkout_relative1 = path('foo');
        my $fake_checkout1 = $git_cache_dir->child('foo')->make_path;
        $fake_checkout1->child('some-file')->spew('This file is 27 bytes long.');
        my $fake_checkout_relative2 = path('bar');
        my $fake_checkout2 = $git_cache_dir->child('bar')->make_path;

        subtest 'below limit' => sub {
            $bmwqemu::vars{GIT_CACHE_DIR_LIMIT} = 10000000;
            combined_unlike { limit_git_cache_dir($git_cache_dir, $fake_checkout1, $fake_checkout_relative1, $handle_du) }
            qr/removing/i, 'no cleanup was logged';
            ok -d $repo_cache_dir, 'no cleanup has happened yet';
        };
        subtest 'over limit' => sub {
            $bmwqemu::vars{GIT_CACHE_DIR_LIMIT} = 100;
            combined_like { limit_git_cache_dir($git_cache_dir, $fake_checkout2, $fake_checkout_relative2, $handle_du) }
            qr|removing.*$orga/$repo$suffix|i, 'cleanup was logged';
            ok !-d $repo_cache_dir, 'the repo that was cloned first has been cleaned up';
            ok -d $fake_checkout1, 'fake repo 1 has not been cleaned up yet';
            ok -d $fake_checkout2, 'fake repo 2 has not been cleaned up yet';
        };
    };
};

done_testing;

sub initialize_git_repo () {
    my $git_init = <<"EOM";
mkdir $git_dir && \
cd $git_dir && \
git init >/dev/null 2>&1 && \
git config user.email "you\@example.com" >/dev/null && \
git config user.name "Your Name" >/dev/null && \
git config init.defaultBranch main >/dev/null && \
git config commit.gpgsign false >/dev/null && \
touch README.md && \
git add README.md && \
git commit -mInit >/dev/null
EOM
    system $git_init and die "git init failed";

    # Create some dummy commits so the code has to increase the clone depth a
    # couple of times
    for (1 .. 10) {
        my $git_add = qq{cd $git_dir; echo $_ >>README.md; git add README.md; git commit -m"Commit $_" >/dev/null};
        system $git_add;
    }
    chomp(my $head = qx{git -C $git_dir rev-parse HEAD});
    return $head;
}

sub cleanup () {
    rmtree $clone_dir;
    unlink 'vars.json';
}

END {
    cleanup();
}
