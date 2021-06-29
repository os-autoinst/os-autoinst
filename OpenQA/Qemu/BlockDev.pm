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

=head2 OpenQA::Qemu::BlockDev

Represents a QEMU block device in a block device chain. In the diagram below
the letter in brackets is the node_name.

[A] <- [B] <- [C]

If we are node B then backing_file is node A and overlay is node C (the
"active layer"). See qemu/docs/interop/live-block-operations.rst for an
explanation of the terminology used.

The last BlockDev in a chain is associated with a DriveDevice.

The chain is essentially a doubly linked list. To avoid circular reference
between the overlay and backing_file properties, the overlay property is
weakened.

=cut

package OpenQA::Qemu::BlockDev;
use Mojo::Base 'OpenQA::Qemu::MutParams', -signatures;

use Scalar::Util 'weaken';
use OpenQA::Qemu::SnapshotConf;
use File::Spec;

use constant FILE_POSTFIX => '-file';

=head3 driver

The file format and software layer used to power the block device.  Usually we
use qcow2; infact only the backing files for ISOs and firmwares should be in
any other format.

=cut
has driver => 'qcow2';

=head3 file

The file name for the file which holds the block devices data and meta data.
e.g. hd0-overlay0.qcow2. QEMU allows none file like objects to be used as the data
store, including other block devices, but we hide that fact for now.

=cut
has 'file';

=head3 backing_file

A link to another OpenQA::Qemu::BlockDev object which represents the backing
file for this object. Can be undefined in which case this is the base layer.
This is the inverse of overlay.

=cut
has 'backing_file';

=head3 node_name

An alphanumeric ID for this block device which allows us to identify it to
QEMU.

=cut
has 'node_name';
has 'size';

=head3 overlay

A link to another OpenQA::Qemu::BlockDev object which represnts the overlay on
top of this block device. This can be undefined in which case this is the
'active layer', that is, the block device which QEMU is writing to (reads may
still be taken from the backing files in the chain).

To avoid memory leaks we weaken this reference.

=cut
sub overlay ($self, $ol) {
    return $self->{overlay} unless defined $ol;
    $self->{overlay} = $ol;
    weaken($self->{overlay});

    return $self;
}

=head3 needs_creating

If true then the blockdevice's data file does not exist yet and needs to be created
(probably by qemu-img).

=cut
has needs_creating => 0;

=head3 implicit

True if this is a backing file and it can only be referenced by the overlay's
qcow2 image. If set to false then we can explicitly declare it on the command
line for later reference by its node name.

Files inside the factory/hdd folder can't be explicitly referenced because it
results in a permission error.

=cut
has implicit => 0;

=head3 snapshot

The snapshot which this overlay belongs to or was created for.

If this is set to an empty snapshot then this blockdevice does not belong to
any snapshot.

=cut
has snapshot => sub { return OpenQA::Qemu::Snapshot->new() };

# See MutParams.pm
sub gen_cmdline ($self) {
    my @cmdl = ();

    # The first blockdev defines the data store, we only use files, but in
    # theory it could be a http address, ISCSI or a link to an object store
    # item (like Ceph).
    push(@cmdl, ('-blockdev',
            join(',', ('driver=file',
                    'node-name=' . $self->node_name . FILE_POSTFIX,
                    'filename=' . $self->file,
                    'cache.no-flush=on'))));
    # The second blockdev tells QEMU what format we are using i.e. qcow2.
    push(@cmdl, ('-blockdev',
            join(',', ('driver=' . $self->driver,
                    'node-name=' . $self->node_name,
                    'file=' . $self->node_name . FILE_POSTFIX,
                    'cache.no-flush=on'))));

    return @cmdl;
}

=head3 gen_qemu_img_cmdlines

Generate the qemu-img command line to create this blockdevice, if it needs
creating. This is a recursive function which returns an array of command lines
for the entire blockdevice chain or an empty array if it does not need
creating.

=cut
sub gen_qemu_img_cmdlines ($self) {
    my @cmdlns = defined $self->backing_file ? $self->backing_file->gen_qemu_img_cmdlines : ();
    return @cmdlns unless $self->needs_creating;

    my @params = ('create', '-f', $self->driver);
    push(@params, ('-b', $self->backing_file->file))
      if defined $self->backing_file;
    push(@params, $self->file);
    push(@params, $self->size);

    return (@cmdlns, \@params);
}

=head 3 gen_unlink_list

If any image file in the chain is marked as needs_creating, but already exists
this will return it in an array so that the caller can unlink it.

=cut
sub gen_unlink_list ($self) {
    return () unless $self->needs_creating;
    return ($self->file, $self->backing_file->gen_unlink_list())
      if defined $self->backing_file;
    return ($self->file);
}

sub _to_map ($self) {
    return {driver => $self->driver,
        file           => $self->file,
        node_name      => $self->node_name,
        size           => $self->size,
        needs_creating => $self->needs_creating,
        implicit       => $self->implicit,
        snapshot       => $self->snapshot->sequence};
}

sub _from_map ($self, $drives, $snap_conf) {
    my ($this, @rest) = @$drives;

    $self->backing_file(OpenQA::Qemu::BlockDev->new()->_from_map(\@rest, $snap_conf))
      if @rest > 0;

    return $self->driver($this->{driver})
      ->file($this->{file})
      ->node_name($this->{node_name})
      ->size($this->{size})
      ->needs_creating($this->{needs_creating})
      ->implicit($this->{implicit})
      ->snapshot($snap_conf->get_snapshot(sequence => $this->{snapshot}));
}

sub CARP_TRACE { 'OpenQA::Qemu::BlockDev(' . (shift->node_name || '') . ')' }

1;
