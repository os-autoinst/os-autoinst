# Copyright 2018-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

=head2 OpenQA::Qemu::BlockDevConf

Configure block devices and drives.

=cut

package OpenQA::Qemu::BlockDevConf;
use Mojo::Base 'OpenQA::Qemu::MutParams', -signatures;

use OpenQA::Qemu::BlockDev;
use OpenQA::Qemu::DriveDevice;
use OpenQA::Qemu::PFlashDevice;
use Storable 'freeze';

use constant OVERLAY_POSTFIX => '-overlay';

has basedir => 'raid';

has _drives => sub ($self) { [] };

=head3 add_existing_base

Add an existing image file at the bottom/start of a block device chain.

=cut
sub add_existing_base ($self, $id, $file_name, $size) {
    $file_name //= $id;

    return OpenQA::Qemu::BlockDev->new()
      ->node_name($id)
      ->file($file_name)
      ->size($size);
}

=head3 add_new_base

Add a new image file at the bottom of a block device chain. The file is not
created by this function, this just updates the object model.

=cut
sub add_new_base ($self, $id, $file_name, $size) {
    $file_name //= $id;

    return $self->add_existing_base($id, $self->basedir . '/' . $file_name, $size)
      ->needs_creating(1);
}

=head3 add_existing_overlay

Add an existing image file as the overlay of $backing_file.

=cut
sub add_existing_overlay ($self, $id, $backing_file) {
    my $ol = OpenQA::Qemu::BlockDev->new()
      ->node_name($id)
      ->backing_file($backing_file)
      ->file($self->basedir . '/' . $id)
      ->size($backing_file->size);
    $backing_file->overlay($ol);

    return $ol;
}

=head3 add_new_overlay

Add an overlay on top of $backing_file, this is equivalent to creating a new
snapshot. This function does not create the file, it just updates the object
model.

=cut
sub add_new_overlay ($self, @args) { $self->add_existing_overlay(@args)->needs_creating(1) }

sub _push_new_drive_dev ($self, $id, $drive, $model, $num_queues = undef) {
    die 'PFlash drives are not supported by DriveDevice, use PFlashDevice'
      if $model eq 'pflash';

    my $dd = OpenQA::Qemu::DriveDevice->new()
      ->id($id)
      ->drive($drive)
      ->model($model)
      ->num_queues($num_queues);
    push(@{$self->_drives}, $dd);

    return $dd;
}

=head3 add_new_drive

Create a new drive device and qcow2 image.

=cut
sub add_new_drive ($self, $id, $model, $size, $num_queues = undef) {
    my $base_drive = $self->add_new_base($id, $id, $size);
    return $self->_push_new_drive_dev($id, $base_drive, $model, $num_queues);
}

=head3 add_existing_drive

Create a new drive device with an existing qcow2 image as the backing store. A
new overlay is created so that the existing qcow2 image is not modified.

=cut
sub add_existing_drive ($self, $id, $file_name, $model, $size, $num_queues = undef) {
    my $base_drive = $self->add_existing_base($id, $file_name, $size)->implicit(1)->deduce_driver;
    my $overlay = $self->add_new_overlay($id . OVERLAY_POSTFIX . '0', $base_drive);

    return $self->_push_new_drive_dev($id, $overlay, $model, $num_queues);
}


=head3 add_iso_drive

Add a cdrom or USB drive with a raw ISO image as the backing store. An overlay
is created, so the test can write to this drive and it won't modify the
underlying image.

=cut
sub add_iso_drive ($self, $id, $file_name, $model, $size) {
    my $base_drive = $self->add_existing_base($id, $file_name, $size)
      ->implicit(1)
      ->driver('raw');
    my $overlay = $self->add_new_overlay($id . OVERLAY_POSTFIX . '0', $base_drive);

    return $self->_push_new_drive_dev($id, $overlay, $model);
}

=head3 add_pflash_drive

Add a pflash drive which is generally used for UEFI firmware code and
variables. See the OpenQA::Qemu::PFlashDevice class.

=cut
sub add_pflash_drive ($self, $id, $file_name, $size) {
    my $base_drive = $self->add_existing_base($id, $file_name, $size)->implicit(1)->deduce_driver;
    my $overlay = $self->add_new_overlay($id . OVERLAY_POSTFIX . '0', $base_drive);
    my $pflash = OpenQA::Qemu::PFlashDevice->new()
      ->id($id)
      ->drive($overlay);

    push(@{$self->_drives}, $pflash);
    return $pflash;
}

=head3 add_path_to_drive

Add a connection between a drive device and a controller device. You can add
multiple connections to simulate multipath.

=cut
sub add_path_to_drive ($self, $id, $drive, $controller) {
    my $dp = OpenQA::Qemu::DrivePath->new()
      ->controller($controller)
      ->id($id);
    push(@{$drive->paths}, $dp);

    return $dp;
}

=head3 add_snapshot_to_drive

Add an overlay to the block device chain for a given drive. Snapshots are
added at runtime by a QEMU QMP command which creates the overlay, so this
function will not mark the overlay for creation by qemu-img.

=cut
sub add_snapshot_to_drive ($self, $drive, $snapshot) {
    my $id = $drive->id . OVERLAY_POSTFIX . $drive->new_overlay_id;

    my $snap = $self->add_existing_overlay($id, $drive->drive)
      ->snapshot($snapshot);
    $drive->drive($snap);

    return $snap;
}

=head3 revert_to_snapshot

Revert to a snapshot/overlay in the blockdev chain which is specified by the
snapshot object. This returns a list of the overlay files which were created
after the snapshot. These should be deleted to prevent QEMU from doing
something unexpected. Also init_blockdev_images needs to be run after this.

=cut
sub revert_to_snapshot ($self, $drive, $snapshot) {
    my @del_files = ();

    my $snap = $drive->drive;
    while (defined $snap && !$snap->snapshot->equals($snapshot)) {
        push(@del_files, $snap->file);
        $snap = $snap->backing_file;
        $drive->drive($snap);
    }

    die 'Block dev chain for ' . $drive->id . ' does not contain snapshot ' . $snap->name
      unless defined $snap;
    die 'The last block device in ' . $drive->id . "'s block device chain is a snapshot"
      unless defined $snap->backing_file;

    # Will cause the snapshot overlay to be recreated when init_blockdev_images is run
    $snap->needs_creating(1);

    return \@del_files;
}

sub for_each_drive ($self, $sub) {
    $sub->($_) for @{$self->_drives};
    return $self;
}

sub mark_all_created ($self) {
    $self->for_each_drive(sub {
            shift->for_each_overlay(sub {
                    shift->needs_creating(0);
            });
    });
}

# See MutParams.pm
sub gen_cmdline ($self) { map { $_->gen_cmdline() } @{$self->_drives} }

=head3 gen_qemu_img_cmdlines

Create qemu-img command lines for all drives that need creating.

=cut
sub gen_qemu_img_cmdlines ($self) { map { $_->gen_qemu_img_cmdlines() } @{$self->_drives} }

sub gen_qemu_img_convert ($self, $filter, $img_dir, $name, $qemu_compress_qcow) {
    map { $_->gen_qemu_img_convert($img_dir, $name, $qemu_compress_qcow) }
    grep { $_->id =~ $filter } @{$self->_drives};
}

=head3 gen_unlink_list

Generate a list of all files which are marked for creation. So that they can
be safely deleted if they already exist.

=cut
sub gen_unlink_list ($self) { map { $_->gen_unlink_list() } @{$self->_drives} }

# See MutParams.pm
sub to_map ($self) {
    my @drives = map { $_->_to_map() } @{$self->_drives};
    return {basedir => $self->basedir, drives => \@drives};
}

# See MutParams.pm
sub from_map ($self, $map, $cont_conf, $snap_conf) {
    my @drives = map {
        $_->{model} eq 'pflash' ?
          OpenQA::Qemu::PFlashDevice->new()->_from_map($_, $cont_conf, $snap_conf) :
          OpenQA::Qemu::DriveDevice->new()->_from_map($_, $cont_conf, $snap_conf)
    } @{$map->{drives}};

    return $self->basedir($map->{basedir})->_drives(\@drives);
}

# See MutParams.pm
sub has_state ($self) { scalar(@{$self->_drives}) }

1;
