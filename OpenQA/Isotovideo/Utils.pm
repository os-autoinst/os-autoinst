# Copyright © 2018-2021 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package OpenQA::Isotovideo::Utils;
use Mojo::Base -base, -signatures;
use Mojo::URL;

use Exporter 'import';
use File::Spec;
use Cwd;
use bmwqemu;
use Try::Tiny;

our @EXPORT_OK = qw(checkout_git_repo_and_branch checkout_git_refspec
  handle_generated_assets load_test_schedule);

sub calculate_git_hash ($git_repo_dir) {
    my $dir = getcwd();
    chdir($git_repo_dir);
    chomp(my $git_hash = qx{git rev-parse HEAD ||:});
    $git_hash ||= "UNKNOWN";
    chdir($dir);
    bmwqemu::diag "git hash in $git_repo_dir: $git_hash";
    return $git_hash;
}

=head2 checkout_git_repo_and_branch

    checkout_git_repo_and_branch($dir [, clone_depth => <num>]);

Takes a test or needles distribution directory parameter and checks out the
referenced git repository into a local working copy with an additional,
optional git refspec to checkout. The git clone depth can be specified in the
argument C<clone_depth> which defaults to 1.

=cut
sub checkout_git_repo_and_branch ($dir_variable, %args) {
    my $dir = $bmwqemu::vars{$dir_variable};
    return undef unless defined $dir;

    my $url = Mojo::URL->new($dir);
    return undef unless $url->scheme;    # assume we have a remote git URL to clone only if this looks like a remote URL

    $args{clone_depth} //= 1;

    my $branch      = $url->fragment;
    my $clone_url   = $url->fragment(undef)->to_string;
    my $local_path  = $url->path->parts->[-1] =~ s/.git//r;
    my $clone_cmd   = 'env GIT_SSH_COMMAND="ssh -oBatchMode=yes" git clone';
    my $clone_args  = "--depth $args{clone_depth}";
    my $branch_args = '';
    my ($return_code, @out);
    my $handle_output = sub {
        bmwqemu::diag "@out" if @out;
        die "Unable to clone Git repository '$dir' specified via $dir_variable (see log for details)" unless $return_code == 0;
    };
    if ($branch) {
        bmwqemu::diag "Checking out git refspec/branch '$branch'";
        $branch_args = " --branch $branch";
    }
    if (!-e $local_path) {
        bmwqemu::diag "Cloning git URL '$clone_url' to use as test distribution";
        @out         = qx{$clone_cmd $clone_args $branch_args $clone_url 2>&1};
        $return_code = $?;
        if ($branch && grep /warning: Could not find remote branch/, @out) {
            # maybe we misspelled or maybe someone gave a commit hash instead
            # for which we need to take a different approach by downloading the
            # repository in the necessary depth until we can reach the commit
            # References:
            # * https://stackoverflow.com/questions/18515488/how-to-check-if-the-commit-exists-in-a-git-repository-by-its-sha-1
            # * https://stackoverflow.com/questions/26135216/why-isnt-there-a-git-clone-specific-commit-option
            bmwqemu::diag "Fetching more remote objects to ensure availability of '$branch'";
            @out         = qx{$clone_cmd $clone_args $clone_url 2>&1};
            $return_code = $?;
            $handle_output->();
            while (qx[git -C $local_path cat-file -e $branch^{commit} 2>&1] =~ /Not a valid object/) {
                $args{clone_depth} *= 2;
                @out         = qx[git -C $local_path fetch --progress --depth=$args{clone_depth} 2>&1];
                $return_code = $?;
                bmwqemu::diag "git fetch: @out";
                die "Unable to fetch Git repository '$dir' specified via $dir_variable (see log for details)" unless $return_code == 0;
                die "Could not find '$branch' in complete history" if grep /remote: Total 0/, @out;
            }
            qx{git -C $local_path checkout $branch};
            die "Unable to checkout branch '$branch' in cloned Git repository '$dir'" unless $? == 0;
        }
        else {
            $handle_output->();
        }
    }
    else {
        bmwqemu::diag "Skipping to clone '$clone_url'; $local_path already exists";
    }
    return $bmwqemu::vars{$dir_variable} = File::Spec->rel2abs($local_path);
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
    calculate_git_hash($dir);
}

=head2 handle_generated_assets

Handles the assets generated by the test depending on status and test
configuration variables.

=cut

sub handle_generated_assets ($command_handler, $clean_shutdown) {
    my $return_code = 0;
    # mark hard disks for upload if test finished
    return unless $bmwqemu::vars{BACKEND} eq 'qemu';
    my @toextract;
    my $nd = $bmwqemu::vars{NUMDISKS};
    if ($command_handler->test_completed) {
        for my $i (1 .. $nd) {
            my $dir  = 'assets_private';
            my $name = $bmwqemu::vars{"STORE_HDD_$i"} || undef;
            unless ($name) {
                $name = $bmwqemu::vars{"PUBLISH_HDD_$i"} || undef;
                $dir  = 'assets_public';
            }
            next unless $name;
            push @toextract, _store_asset($i, $name, $dir);
        }
        if ($bmwqemu::vars{UEFI} && $bmwqemu::vars{PUBLISH_PFLASH_VARS}) {
            push(@toextract, {pflash_vars => 1,
                    name   => $bmwqemu::vars{PUBLISH_PFLASH_VARS},
                    dir    => 'assets_public',
                    format => 'qcow2'});
        }
        if (@toextract && !$clean_shutdown) {
            bmwqemu::serialize_state(component => 'isotovideo', msg => 'unable to handle generated assets: machine not shut down when uploading disks', log => 1);
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
            bmwqemu::serialize_state(component => 'backend', msg => "unable to extract assets: $@", log => 1);
            $return_code = 1;
        }
    }
    return $return_code;
}

=head2 load_test_schedule

Loads the test schedule (main.pm) or particular test modules if the `SCHEDULE` variable is
present.

=cut

sub load_test_schedule {
    # add lib of the test distributions - but only for main.pm not to pollute
    # further dependencies (the tests get it through autotest)
    my @oldINC = @INC;
    unshift @INC, $bmwqemu::vars{CASEDIR} . '/lib';
    if ($bmwqemu::vars{SCHEDULE}) {
        unshift @INC, '.' unless File::Spec->file_name_is_absolute($bmwqemu::vars{CASEDIR});
        bmwqemu::fctinfo 'Enforced test schedule by \'SCHEDULE\' variable in action';
        $bmwqemu::vars{INCLUDE_MODULES} = undef;
        autotest::loadtest($_ =~ qr/\./ ? $_ : $_ . '.pm') foreach split(',', $bmwqemu::vars{SCHEDULE});
        $bmwqemu::vars{INCLUDE_MODULES} = 'none';
    }
    my $productdir = $bmwqemu::vars{PRODUCTDIR};
    my $main_path  = File::Spec->catfile($productdir, 'main.pm');
    try {
        if (-e $main_path) {
            unshift @INC, '.';
            require $main_path;
        }
        elsif (!File::Spec->file_name_is_absolute($productdir) && -e File::Spec->catfile($bmwqemu::vars{CASEDIR}, $main_path)) {
            require File::Spec->catfile($bmwqemu::vars{CASEDIR}, $main_path);
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

1;
