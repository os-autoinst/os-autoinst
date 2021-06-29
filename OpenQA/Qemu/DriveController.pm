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

=head2 OpenQA::Qemu::DriveController

A device which provides at least one bus for the drive devices to attach
to. Buses are documented in <qemu source>/docs/qdev-device-use.txt.

=cut

package OpenQA::Qemu::DriveController;
use Mojo::Base 'OpenQA::Qemu::MutParams', -signatures;

has 'model';
has 'id';

sub gen_cmdline ($self) { ('-device', $self->model . ',id=' . $self->id) }
sub _to_map ($self) { {model => $self->model, id => $self->id} }

1;
