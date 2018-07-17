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

=head2 OpenQA::Qemu::DrivePath

One drive device can be connected via multiple paths (e.g. connected to
multiple SCSI controllers). This represents a single connection from a drive
to a controller.

=cut
package OpenQA::Qemu::DrivePath;
use Mojo::Base -base;
use Mojo::JSON 'encode_json';

has 'id';
has 'controller';

sub _to_map {
    my $self = shift;

    return {id => $self->id,
        controller => $self->controller->id};
}

sub _from_map {
    my ($self, $map, $cont_conf) = @_;

    return $self->id($map->{id})
      ->controller($cont_conf->get_controller($map->{controller}));
}

sub CARP_TRACE {
    return 'OpenQA::Qemu::DrivePath(' . (shift->id || '') . ')';
}

1;
