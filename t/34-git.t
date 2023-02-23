#!/usr/bin/perl
#
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use File::Path qw(rmtree);
use FindBin '$Bin';
use Test::Output qw(combined_from combined_like);
use Test::Mock::Time;
use OpenQA::Isotovideo::Utils qw(checkout_git_repo_and_branch);
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Warnings ':report_warnings';

use Mojo::File 'tempdir';
my $tmpdir = tempdir("/tmp/$FindBin::Script-XXXX");
my $git_dir = "$tmpdir/tmpgitrepo";
my $clone_dir = "$Bin/tmpgitrepo";

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
touch README && \
git add README && \
git commit -mInit >/dev/null
EOM
    system $git_init and die "git init failed";

    # Create some dummy commits so the code has to increase the clone depth a
    # couple of times
    for (1 .. 10) {
        my $git_add = qq{cd $git_dir; echo $_ >>README; git add README; git commit -m"Commit $_" >/dev/null};
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
