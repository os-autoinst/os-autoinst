# Copyright 2018 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

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

sub CARP_TRACE ($self) { 'OpenQA::Qemu::DrivePath(' . ($self->id || '') . ')' }

1;
