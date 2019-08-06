# Copyright © 2019 SUSE LLC
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

package backend::ssh;

use strict;
use warnings;

use base 'backend::baseclass';


sub new {
    return shift->SUPER::new;
}

sub check_socket {
    my ($self, $fh, $write) = @_;
    return 1 if $self->check_ssh_serial($fh);
    return $self->SUPER::check_socket($fh, $write);
}

1;
