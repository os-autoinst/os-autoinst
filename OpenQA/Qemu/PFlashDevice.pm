# Copyright 2018 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

=head3 OpenQA::Qemu::PFlashDevice

Some storage devices can only be created using the '-drive' parameter in
QEMU. Pflash is one such device (at the time of writing), so we can not use a
standard drive device to represent it. This limits our control over how the
drive device and block device chain are created; we can not set the node id of
the top block device for example nor can we override the backing file AFAIK.

This class is the same as DriveDevice except for a few extra fields and
gen_cmdline has been overridden to use '-drive' instead.

=cut

package OpenQA::Qemu::PFlashDevice;
use Mojo::Base 'OpenQA::Qemu::DriveDevice', -signatures;

has model => 'pflash';
has 'unit';
has 'readonly';

sub gen_cmdline ($self) {
    my $drive = $self->drive;
    my @params = ('id=' . $drive->node_name,
        "if=pflash",
        'file=' . $drive->file);

    $self->_push_ifdef(\@params, 'unit=', $self->unit);
    $self->_push_ifdef(\@params, 'readonly=', $self->readonly);

    return ('-drive', join(',', @params));
}

1;
