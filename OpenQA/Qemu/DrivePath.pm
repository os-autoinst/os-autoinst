# Copyright 2018 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

=head2 OpenQA::Qemu::DrivePath

One drive device can be connected via multiple paths (e.g. connected to
multiple SCSI controllers). This represents a single connection from a drive
to a controller.

=cut

package OpenQA::Qemu::DrivePath;
use Mojo::Base -base;

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
