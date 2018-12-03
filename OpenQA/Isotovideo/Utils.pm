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

use File::Spec;
use File::Path;
use Cwd;
use testapi 'diag';
use bmwqemu;

sub calculate_git_hash {
    my ($git_repo_dir) = @_;
    my $dir = getcwd();
    chdir($git_repo_dir);
    chomp(my $git_hash = qx{git rev-parse HEAD});
    $git_hash ||= "UNKNOWN";
    chdir($dir);
    diag "git hash in $git_repo_dir: $git_hash";
    return $git_hash;
}

1;
