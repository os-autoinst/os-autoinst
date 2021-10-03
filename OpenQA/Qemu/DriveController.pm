# Copyright 2018 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

=head2 OpenQA::Qemu::DriveController

A device which provides at least one bus for the drive devices to attach
to. Buses are documented in <qemu source>/docs/qdev-device-use.txt.

=cut

package OpenQA::Qemu::DriveController;
use Mojo::Base 'OpenQA::Qemu::MutParams';

has 'model';
has 'id';

sub gen_cmdline {
    my $self = shift;

    return ('-device', $self->model . ',id=' . $self->id);
}

sub _to_map {
    my $self = shift;

    return {model => $self->model,
        id => $self->id};
}

1;
