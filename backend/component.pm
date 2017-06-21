# Copyright (C) 2017 SUSE LLC
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

package backend::component;

use Mojo::Base -base;
use bmwqemu;
use POSIX;
use Carp 'confess';

has verbose => 1;
has load    => 0;
has 'backend';

sub _diag {
    my ($self, @messages) = @_;
    my $caller = (caller(1))[3];
    bmwqemu::diag ">> ${caller}(): @messages" if $self->verbose;
}

1;
