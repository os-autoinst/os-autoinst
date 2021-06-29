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

=head2 OpenQA::Qemu::DrivePath

One drive device can be connected via multiple paths (e.g. connected to
multiple SCSI controllers). This represents a single connection from a drive
to a controller.

=cut

package OpenQA::Qemu::DrivePath;
use Mojo::Base -base, -signatures;

has 'id';
has 'controller';

sub _to_map ($self) { {id => $self->id, controller => $self->controller->id} }

sub _from_map ($self, $map, $cont_conf) {
    $self->id($map->{id})
      ->controller($cont_conf->get_controller($map->{controller}));
}

sub CARP_TRACE { 'OpenQA::Qemu::DrivePath(' . (shift->id || '') . ')' }

1;
