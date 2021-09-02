# Copyright © 2016 SUSE LLC
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

package backend::virt;

use Mojo::Base -strict;

use base 'backend::baseclass';

use testapi 'get_var';
use bmwqemu;

sub new {
    my ($class) = @_;
    my $self = $class->SUPER::new;
    $bmwqemu::vars{QEMURAM}  //= 1024;
    $bmwqemu::vars{QEMUCPUS} //= 1;
    return $self;
}


1;
