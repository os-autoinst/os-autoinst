# Copyright © 2018 SUSE LLC
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
use Mojo::Base -base;
use Mojo::URL;

use Exporter 'import';
use File::Spec;
use Cwd;
use bmwqemu 'diag';

our @EXPORT_OK = qw(checkout_git_repo_and_branch checkout_git_refspec);

sub calculate_git_hash {
    my ($git_repo_dir) = @_;
    my $dir = getcwd();
    chdir($git_repo_dir);
    chomp(my $git_hash = qx{git rev-parse HEAD ||:});
    $git_hash ||= "UNKNOWN";
    chdir($dir);
    diag "git hash in $git_repo_dir: $git_hash";
    return $git_hash;
}

=head2 checkout_git_repo_and_branch

    checkout_git_repo_and_branch($dir [, clone_depth => <num>]);

Takes a test or needles distribution directory parameter and checks out the
referenced git repository into a local working copy with an additional,
optional git refspec to checkout. The git clone depth can be specified in the
argument C<clone_depth> which defaults to 1.

=cut
sub checkout_git_repo_and_branch {
    my ($dir_variable, %args) = @_;
    my $dir = $bmwqemu::vars{$dir_variable};
    return undef unless defined $dir;

    my $url = Mojo::URL->new($dir);
    return undef unless $url->scheme;    # assume we have a remote git URL to clone only if this looks like a remote URL

    $args{clone_depth} //= 1;

    my $branch     = $url->fragment;
    my $clone_url  = $url->fragment(undef)->to_string;
    my $local_path = $url->path->parts->[-1] =~ s/.git//r;
    my $clone_args = "--depth $args{clone_depth}";
    if ($branch) {
        diag "Checking out git refspec/branch '$branch'";
        $clone_args .= " --branch $branch";
    }
    if (!-e $local_path) {
        diag "Cloning git URL '$clone_url' to use as test distribution";
        qx{env GIT_SSH_COMMAND="ssh -oBatchMode=yes" git clone $clone_args $clone_url};
    }
    else {
        diag "Skipping to clone '$clone_url'; $local_path already exists";
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
sub checkout_git_refspec {
    my ($dir, $refspec_variable) = @_;
    return undef unless defined $dir;
    if (my $refspec = $bmwqemu::vars{$refspec_variable}) {
        diag "Checking out local git refspec '$refspec' in '$dir'";
        qx{env git -C $dir checkout -q $refspec};
        die "Failed to checkout '$refspec' in '$dir'\n" unless $? == 0;
    }
    calculate_git_hash($dir);
}

1;
