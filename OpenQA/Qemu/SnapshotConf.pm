# Copyright 2018 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

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
has _head => sub ($self) { OpenQA::Qemu::Snapshot->new() };

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

sub gen_cmdline ($self) { $self->_head->sequence > -1 ? qw(-incoming defer) : () }

sub to_map ($self) {
    my @snapshots = ();
    my $snap = $self->_head;

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

sub has_state ($self) { $self->_sequence }

1;
