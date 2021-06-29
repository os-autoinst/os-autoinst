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

=head2 OpenQA::Qemu::Snapshot

Represents the state of a virtual machine at a particular point in time. Not
much information about the snapshot is stored within this class itself, it is
used mainly as a reference to identify disperate objects as belonging to a
single snapshot.

We only consider snapshots which form a linear chain. Branching snapshots are
not supported.

=cut

package OpenQA::Qemu::Snapshot;
use Mojo::Base 'OpenQA::Qemu::MutParams', -signatures;

has sequence => sub { return -1; };
has name     => sub { return 'none'; };
has 'previous';

sub equals ($self, $other) { $self->sequence == $other->sequence }

sub _to_map ($self) { {sequence => $self->sequence, name => $self->name} }

sub CARP_TRACE ($self) { 'OpenQA::Qemu::Snapshot(' . $self->sequence . '|' . $self->name . ')' }

1;
