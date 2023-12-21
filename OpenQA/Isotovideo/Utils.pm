# Copyright 2018-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Isotovideo::Utils;
use IPC::Run;
use Mojo::Base -base, -signatures;
use Mojo::URL;
use Mojo::File qw(path);
use JSON::Validator;
use Cwd 'cwd';
use YAML::XS;    # Required by JSON::Validator as a runtime dependency
use YAML::PP;

use Exporter 'import';
use bmwqemu;
use autotest;
use Try::Tiny;

our @EXPORT_OK = qw(git_rev_parse checkout_git_repo_and_branch
  spawn_debuggers
  checkout_wheels
  checkout_git_refspec git_remote_url
  handle_generated_assets load_test_schedule);

use constant GIT_CLONE_DEPTH => $ENV{OS_AUTOINST_GIT_CLONE_DEPTH} // 1;
use constant GIT_RETRY_COUNT => $ENV{OS_AUTOINST_GIT_RETRY_COUNT} // 2;
use constant GIT_RETRY_INTERVAL => $ENV{OS_AUTOINST_GIT_RETRY_INTERVAL} // 5;

sub git_rev_parse ($dirname, $cmd_prefix = '') {
    $dirname = path($dirname)->realpath;
    chomp(my $version = qx{$cmd_prefix git -C "$dirname" rev-parse HEAD 2>&1});
    return $version if $? == 0;
    return 'UNKNOWN' unless $version =~ /(git config.*safe.directory.*$)/;
    my $addsafe = 'TMPDIR=$(mktemp -d --tmpdir os-autoinst-git.XXXXX) && HOME=$TMPDIR && ' . $1;    # uncoverable statement
    $version = qx{$addsafe && git -C "$dirname" rev-parse HEAD && rm -r \$TMPDIR} || '(unreadable git hash)';    # uncoverable statement
    chomp($version);    # uncoverable statement
    return $version;    # uncoverable statement
}

sub calculate_git_hash ($git_repo_dir) {
    my $git_hash = git_rev_parse($git_repo_dir);
    bmwqemu::diag "git hash in '$git_repo_dir': $git_hash";
    return $git_hash;
}

sub git_remote_url ($git_repo_dir) {
    return 'UNKNOWN (no .git found)' unless -e "$git_repo_dir/.git";
    chomp(my @remotes = qx{git -C "$git_repo_dir" remote});
    return 'UNKNOWN (origin remote not found)' unless grep { $_ eq 'origin' } @remotes;
    chomp(my $url = qx{git -C "$git_repo_dir" remote get-url origin 2>&1});
    return $url if $? == 0;
    bmwqemu::diag("Could not retrieve remote url of $git_repo_dir: '$url'");    # uncoverable statement
    return 'UNKNOWN (error on git remote call)';    # uncoverable statement
}

sub clone_git ($local_path, $clone_url, $clone_depth, $branch, $dir, $dir_variable, $direct_fetch) {
    if (-e $local_path) {
        bmwqemu::diag "Skipping to clone '$clone_url'; $local_path already exists";
        return 1;
    }
    bmwqemu::fctinfo "Cloning git URL '$clone_url' into '" . cwd . "'";
    my $branch_args = '';
    if ($branch) {
        bmwqemu::fctinfo "Checking out git refspec/branch '$branch'";
        $branch_args = " --branch $branch";
    }
    my $clone_cmd = 'env GIT_SSH_COMMAND="ssh -oBatchMode=yes" git clone';
    my @out = qx{$clone_cmd --depth=$clone_depth $branch_args $clone_url 2>&1};
    my $handle_output = sub ($return_value, @out) {
        bmwqemu::diag "@out" if @out;
        die "Unable to clone Git repository '$dir' specified via $dir_variable (see log for details)" unless $return_value == 0;
        return 1;
    };
    return $handle_output->($?, @out) unless ($branch && grep /warning: Could not find remote branch/, @out);

    # if cloning with `--branch=…` does not work, just clone the default branch instead and fetch and checkout the missing
    # ref manually
    @out = qx{$clone_cmd --depth=$clone_depth $clone_url 2>&1};
    if ($direct_fetch) {
        bmwqemu::diag "Fetching '$branch' from origin manually";
        $handle_output->($?, @out);
        @out = qx{git -C "$local_path" fetch origin "$branch" 2>&1 && git -C "$local_path" checkout FETCH_HEAD 2>&1};
        return $handle_output->($?, @out) unless (grep /could(n't| not) find remote ref/, @out);
    }

    # if fetching the specified rev did not work, take yet another approach (maybe we just misspelled, though)
    # note: This approach repeatedly fetches further commits with increasing depth until the referenced rev exists.
    # references:
    # * https://stackoverflow.com/questions/18515488/how-to-check-if-the-commit-exists-in-a-git-repository-by-its-sha-1
    # * https://stackoverflow.com/questions/26135216/why-isnt-there-a-git-clone-specific-commit-option
    bmwqemu::diag "Fetching more remote objects to ensure availability of '$branch'";
    while (qx[git -C $local_path cat-file -e $branch^{commit} 2>&1] =~ /Not a valid object/) {
        $clone_depth *= 2;
        @out = qx[git -C $local_path fetch --progress --depth=$clone_depth 2>&1];
        $handle_output->($?, @out);
        die "Could not find '$branch' in complete history in cloned Git repository '$dir'" if grep /remote: Total 0/, @out;
    }
    @out = qx{git -C $local_path checkout $branch};
    bmwqemu::diag "@out" if @out;
    die "Unable to checkout branch '$branch' in cloned Git repository '$dir'" unless $? == 0;
    return 1;
}

=head2 checkout_git_repo_and_branch

    checkout_git_repo_and_branch($dir [, clone_depth => <num>]);

Takes a test or needles distribution directory parameter and checks out the
referenced git repository into a local working copy with an additional,
optional git refspec to checkout. The git clone depth can be specified in the
argument C<clone_depth> which defaults to 1.
If C<repo> is specified it is used as the actual URL of the repo.

Cloning may fail up to C<retry_count> times with a delay of C<retry_interval> seconds.

=cut
sub checkout_git_repo_and_branch ($dir_variable, %args) {
    my $dir = $bmwqemu::vars{$dir_variable} // $args{repo};
    return undef unless defined $dir;

    my $url = Mojo::URL->new($dir);
    return undef unless $url->scheme;    # assume we have a remote git URL to clone only if this looks like a remote URL

    my $clone_depth = $args{clone_depth} // GIT_CLONE_DEPTH;
    my $retry_count = $args{retry_count} // GIT_RETRY_COUNT;
    my $retry_interval = $args{retry_interval} // GIT_RETRY_INTERVAL;

    my $branch = $url->fragment;
    my $clone_url = $url->fragment(undef)->to_string;
    my $local_path = $url->path->parts->[-1] =~ s/\.git$//r;
    my $tries = $retry_count;

    my $local_abs = path($local_path)->to_abs->to_string;
    $bmwqemu::vars{$dir_variable} = $local_abs unless $args{repo};

    my $error;
    do {
        my $status;
        eval { $status = clone_git($local_path, $clone_url, $clone_depth, $branch, $dir, $dir_variable, $args{direct_fetch} // 1) };
        $error = $@;
        return $local_abs if $status;
        bmwqemu::diag "Clone failed, retries left: $tries of $retry_count";
        sleep $retry_interval if $tries;
    } while ($tries-- > 0);
    die $error;
}

=head2 checkout_wheels

    checkout_wheels($dir);

Takes a directory which may require wheels and checks out the
referenced git repository into a local working copy with an additional,
optional git refspec to checkout.
If no wheels are configured the function returns early.

=cut
sub checkout_wheels ($case_dir, $wheels_dir = undef) {
    my $specfile = path($case_dir, 'wheels.yaml');
    return 1 unless -e $specfile;

    my $schema_file = "$bmwqemu::scriptdir/schema/Wheels-01.yaml";
    # JSON::Validator 4.10 reports an unexpected error message for
    # non-existent schema files with absolute paths
    die "Unable to load schema '$schema_file'" unless -f $schema_file;
    my $validator = JSON::Validator->new;
    $validator->schema($schema_file);
    my $spec = YAML::PP->new->load_file($specfile);
    my @errors = $validator->validate($spec);
    die "Invalid YAML ($specfile): " . join(',', @errors) if @errors;
    die "Unsupported version ($specfile): Version must be 'v0.1'" if $spec->{version} ne 'v0.1';

    my $old_cwd = cwd;
    chdir $wheels_dir if defined $wheels_dir;
    foreach my $repo (@{$spec->{wheels}}) {
        $repo = "https://github.com/$repo.git" unless $repo =~ qr/^http/;
        if (my $clone = checkout_git_repo_and_branch($specfile, repo => $repo)) {
            unshift @INC, "$clone/lib";
        }
    }
    chdir $old_cwd;
    return 0;
}

=head2 checkout_git_refspec

    checkout_git_refspec($dir, $refspec_variable);

Takes a git working copy directory path and checks out a git refspec specified
in a git hash test parameter if possible. Returns the determined git hash in
any case, also if C<$refspec> was not specified or is not defined.

Example:

    checkout_git_refspec('/path/to/casedir', 'TEST_GIT_REFSPEC');

=cut
sub checkout_git_refspec ($dir, $refspec_variable) {
    return undef unless defined $dir;
    if (my $refspec = $bmwqemu::vars{$refspec_variable}) {
        bmwqemu::diag "Checking out local git refspec '$refspec' in '$dir'";
        qx{env git -C $dir checkout -q $refspec};
        die "Failed to checkout '$refspec' in '$dir'\n" unless $? == 0;
    }
    my $hash = calculate_git_hash($dir);
    my $url = git_remote_url($dir);
    bmwqemu::diag "git url in '$dir': $url";
    return ($url, $hash);
}

=head2 handle_generated_assets

Handles the assets generated by the test depending on status and test
configuration variables.

=cut

sub handle_generated_assets ($command_handler, $clean_shutdown) {
    my $return_code = 0;
    # mark hard disks for upload if test finished
    return unless $bmwqemu::vars{BACKEND} =~ m/^(qemu|generalhw)$/;
    my @toextract;
    my $nd = $bmwqemu::vars{NUMDISKS} // 1;
    if ($command_handler->test_completed) {
        for my $i (1 .. $nd) {
            my $dir = 'assets_private';
            my $name = $bmwqemu::vars{"STORE_HDD_$i"} || undef;
            unless ($name) {
                $name = $bmwqemu::vars{"PUBLISH_HDD_$i"} || undef;
                $dir = 'assets_public';
            }
            next unless $name;
            push @toextract, _store_asset($i, $name, $dir);
        }
        if ($bmwqemu::vars{UEFI} && $bmwqemu::vars{PUBLISH_PFLASH_VARS}) {
            push(@toextract, {pflash_vars => 1,
                    name => $bmwqemu::vars{PUBLISH_PFLASH_VARS},
                    dir => 'assets_public',
                    format => 'qcow2'});
        }
        if (@toextract && !$clean_shutdown) {
            bmwqemu::serialize_state(component => 'isotovideo', msg => 'unable to handle generated assets: machine not shut down when uploading disks', error => 1);
            return 1;
        }
    }
    for my $i (1 .. $nd) {
        my $name = $bmwqemu::vars{"FORCE_PUBLISH_HDD_$i"} || next;
        bmwqemu::diag "Requested to force the publication of '$name'";
        push @toextract, _store_asset($i, $name, 'assets_public');
    }
    for my $asset (@toextract) {
        local $@;
        eval { $bmwqemu::backend->extract_assets($asset); };
        if ($@) {
            bmwqemu::serialize_state(component => 'backend', msg => "unable to extract assets: $@", error => 1);
            $return_code = 1;
        }
    }
    return $return_code;
}

=head2 load_test_schedule

Loads the test schedule (main.pm) or particular test modules if the `SCHEDULE` variable is
present.

=cut

sub load_test_schedule (@) {
    # add lib of the test distributions - but only for main.pm not to pollute
    # further dependencies (the tests get it through autotest)
    my @oldINC = @INC;
    unshift @INC, $bmwqemu::vars{CASEDIR} . '/lib';
    if ($bmwqemu::vars{SCHEDULE}) {
        unshift @INC, '.' unless path($bmwqemu::vars{CASEDIR})->is_abs;
        bmwqemu::fctinfo 'Enforced test schedule by \'SCHEDULE\' variable in action';
        $bmwqemu::vars{INCLUDE_MODULES} = undef;
        autotest::loadtest($_ =~ qr/\./ ? $_ : $_ . '.pm') foreach split(/[, ]+/, $bmwqemu::vars{SCHEDULE});
        $bmwqemu::vars{INCLUDE_MODULES} = 'none';
    }
    my $productdir = $bmwqemu::vars{PRODUCTDIR};
    my $main_path = path($productdir, 'main.pm');
    try {
        if (-e $main_path) {
            unshift @INC, '.';
            require $main_path;
        }
        elsif (!path($productdir)->is_abs && -e path($bmwqemu::vars{CASEDIR}, $main_path)) {
            require(path($bmwqemu::vars{CASEDIR}, $main_path)->to_string);
        }
        elsif ($productdir && !-e $productdir) {
            die "PRODUCTDIR '$productdir' invalid, could not be found";
        }
        elsif (!$bmwqemu::vars{SCHEDULE}) {
            die "'SCHEDULE' not set and $main_path not found, need one of both";
        }
    }
    catch {
        # record that the exception is caused by the tests themselves before letting it pass
        my $error_message = $_;
        bmwqemu::serialize_state(component => 'tests', msg => 'unable to load main.pm, check the log for the cause (e.g. syntax error)');
        die "$error_message\n";
    };
    @INC = @oldINC;

    if ($bmwqemu::vars{_EXIT_AFTER_SCHEDULE}) {
        bmwqemu::fctinfo 'Early exit has been requested with _EXIT_AFTER_SCHEDULE. Only evaluating test schedule.';
        exit 0;
    }
}

sub _store_asset ($index, $name, $dir) {
    $name =~ /\.([[:alnum:]]+)$/;
    my $format = $1;
    return {hdd_num => $index, name => $name, dir => $dir, format => $format};
}

sub spawn_debuggers () {
    my %debugging_tools;
    $debugging_tools{vncviewer} = ['vncviewer', '-viewonly', '-shared', "localhost:$bmwqemu::vars{VNC}"] if $ENV{RUN_VNCVIEWER};
    $debugging_tools{debugviewer} = ["$bmwqemu::scriptdir/debugviewer/debugviewer", 'qemuscreenshot/last.png'] if $ENV{RUN_DEBUGVIEWER};
    for my $tool (keys %debugging_tools) {
        my ($stdin, $stdout, $stderr, $ret);
        IPC::Run::run(\@{$debugging_tools{$tool}}, \$stdin, \$stdout, \$stderr);
    }
}

1;
