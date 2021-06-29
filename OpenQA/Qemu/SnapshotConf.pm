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

=head3 OpenQA::Qemu::SnapshotConf

Modify and query our snapshot model. Note that adding or reverting to a
snapshot here needs to be combined with calls to BlockDevConf and QEMU itself
to actually perform the snapshot operations and keep the entire object model
consistent. This is done by the Proc class.

=cut

package OpenQA::Qemu::SnapshotConf;
use Mojo::Base 'OpenQA::Qemu::MutParams', -signatures;

use OpenQA::Qemu::Snapshot;

has _sequence => 0;
has _head     => sub { return OpenQA::Qemu::Snapshot->new(); };

sub add_snapshot ($self, $name) {
    $self->_sequence($self->_sequence + 1);
    my $new = OpenQA::Qemu::Snapshot->new()
      ->sequence($self->_sequence)
      ->name($name);

    $new->previous($self->_head);
    $self->_head($new);

    return $new;
}

sub get_snapshot ($self, %nargs) {
    my $snap = $self->_head;

    while (defined $snap && $snap->sequence != $nargs{sequence}) {
        $snap = $snap->previous;
    }

    die "Could not find snapshot with sequence $nargs{sequence}"
      unless defined $snap;

    return $snap;
}

sub revert_to_snapshot ($self, $name) {
    my $snap = $self->_head;

    while (defined $snap && $snap->name ne $name) {
        $snap = $snap->previous;
    }

    die "Could not find snapshot '$name'" unless defined $snap;
    $self->_head($snap);

    return $snap;
}

sub gen_cmdline ($self) {
    if ($self->_head->sequence > -1) {
        return qw(-incoming defer);
    }
    return ();
}

sub to_map ($self) {
    my @snapshots = ();
    my $snap      = $self->_head;

    while ($snap->sequence > -1) {
        push(@snapshots, $snap->_to_map());
        $snap = $snap->previous;
    }

    @snapshots = reverse(@snapshots);
    return {snapshots => \@snapshots};
}

sub from_map ($self, $map) {
    for my $s (@{$map->{snapshots}}) {
        my $snap = $self->add_snapshot($s->{name});
        die "Sequence mismatch while loading '$s->{name}' snapshot state: $s->{sequence} != " . $snap->sequence
          if $s->{sequence} != $snap->sequence;
    }

    return $self;
}

sub has_state { shift->_sequence }

1;
