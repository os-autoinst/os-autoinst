# Copyright © 2017 SUSE LLC
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
use Mojo::Base 'OpenQA::Qemu::MutParams';
use Scalar::Util 'weaken';
use OpenQA::Qemu::SnapshotConf;
use File::Spec;
use bmwqemu 'diag';

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
sub overlay {
    my ($self, $ol) = @_;

    unless (defined $ol) {
        if (defined $self->{overlay}) {
            return $self->{overlay};
        } else {
            return undef;
        }
    }

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
has snapshot => sub { return OpenQA::Qemu::Snapshot->new(); };

# See MutParams.pm
sub gen_cmdline {
    my ($self) = @_;
    my @cmdl = ();

    my $backing = '';
    if (defined $self->backing_file && !$self->backing_file->implicit) {
        push(@cmdl, $self->backing_file->gen_cmdline);
        $backing = $self->backing_file->node_name;
    }

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
                    'cache.no-flush=on',
                    ('backing=' . $backing) x !!$backing))));

    return @cmdl;
}

# The qemu-img -b param treats relative paths as being relative to the image
# being created. Whereas the rest of the universe treats relative paths as
# relative to the CWD. So if the path is relative then we just use the path's
# basename and hope for the best (i.e. we assume the backing file is in the
# same dir as the file being created).
sub _abs_or_basename {
    my $path = shift;

    if (File::Spec->file_name_is_absolute($path)) {
        return $path;
    }
    return (File::Spec->splitpath($path))[2];
}

=head3 gen_qemu_img_cmdlines

Generate the qemu-img command line to create this blockdevice, if it needs
creating. This is a recursive function which returns an array of command lines
for the entire blockdevice chain or an empty array if it does not need
creating.

=cut
sub gen_qemu_img_cmdlines {
    my $self = shift;
    my @cmdlns;

    if (defined $self->backing_file) {
        @cmdlns = $self->backing_file->gen_qemu_img_cmdlines;
    } else {
        @cmdlns = ();
    }

    return @cmdlns unless $self->needs_creating;

    my @params = ('create', '-f', $self->driver);
    # We pass -u so that the backing files are not checked because qemu-img
    # treats the paths as relative to the top overlay, but apparantly
    # blockdev-snapshot-sync does not, so the paths stored in the resulting
    # qcow2 images confuse qemu-img. This means we have to set the sizes of
    # the backing files explicitly because qemu-img can not read them.
    push(@params, ('-u', '-b', _abs_or_basename($self->backing_file->file)))
      if defined $self->backing_file;
    push(@params, $self->file);
    push(@params, $self->size);

    return (@cmdlns, \@params);
}

=head3 gen_qemu_img_rebase

Fixup the backing file paths by removing any relative paths which contain more
than just the backing file's base name. For some reason qemu-img thinks
relative paths are relative to the active layer's location, but when QEMU
creates overlays (i.e. takes a snapshot) it sets paths relative to its CWD.

So applying this method to a backing file chain will allow commands like
'qemu-img convert' to work correctly.

=cut
sub gen_qemu_img_rebase {
    my $self = shift;
    return () unless defined $self->backing_file;

    my @cmdlns = $self->backing_file->gen_qemu_img_rebase();

    return @cmdlns
      if File::Spec->file_name_is_absolute($self->backing_file->file);

    return (@cmdlns, ['rebase', '-u', '-b',
            _abs_or_basename($self->backing_file->file), $self->file]);
}

=head 3 gen_unlink_list

If any image file in the chain is marked as needs_creating, but already exists
this will return it in an array so that the caller can unlink it.

=cut
sub gen_unlink_list {
    my $self = shift;

    return () unless $self->needs_creating;

    if (defined $self->backing_file) {
        return ($self->file, $self->backing_file->gen_unlink_list());
    }
    return ($self->file);
}

sub _to_map {
    my $self = shift;

    return {driver => $self->driver,
        file           => $self->file,
        node_name      => $self->node_name,
        size           => $self->size,
        needs_creating => $self->needs_creating,
        implicit       => $self->implicit,
        snapshot       => $self->snapshot->sequence};
}

sub _from_map {
    my ($self, $drives, $snap_conf) = @_;
    my ($this, @rest) = @$drives;

    if (@rest > 0) {
        $self->backing_file(OpenQA::Qemu::BlockDev->new()->_from_map(\@rest, $snap_conf));
    }

    return $self->driver($this->{driver})
      ->file($this->{file})
      ->node_name($this->{node_name})
      ->size($this->{size})
      ->needs_creating($this->{needs_creating})
      ->implicit($this->{implicit})
      ->snapshot($snap_conf->get_snapshot(sequence => $this->{snapshot}));
}

sub CARP_TRACE {
    return 'OpenQA::Qemu::BlockDev(' . (shift->node_name || '') . ')';
}


=head2 OpenQA::Qemu::DrivePath

One drive device can be connected via multiple paths (e.g. connected to
multiple SCSI controllers). This represents a single connection from a drive
to a controller.

=cut
package OpenQA::Qemu::DrivePath;
use Mojo::Base -base;
use Mojo::JSON 'encode_json';

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

=head2 OpenQA::Qemu::DriveDevice

The device which the SUT sees. The data on the device depends on the block dev
chain pointed to by 'drive'.

=cut
package OpenQA::Qemu::DriveDevice;
use Mojo::Base 'OpenQA::Qemu::MutParams';
use Mojo::JSON 'encode_json';
use bmwqemu 'diag';

use constant DEVICE_POSTFIX => '-device';

=head3 drive

The 'active layer' block device, that is, the top block device in a block
device chain. It is called 'drive' to reflect QEMU's naming.

=cut
has 'drive';

=head3 model

The type of device QEMU should emulate e.g. scsi-hd. See 'qemu-kvm -device
help'.

=cut
has 'model';

=head3 paths

The connections to this device (multipath). Should be of type
OpenQA::Qemu::DrivePath. If left empty, QEMU will decide what to do.

=cut
has paths => sub { return []; };

=head3 bootindex

The boot priority of this device. Zero has highest priority. Bootindex is not
supported by some firmwares and settings.

=cut
has 'bootindex';

=head3 serial

The serial number of the drive

=cut
has 'serial';
has 'id';
has last_overlay_id => 0;

sub new_overlay_id {
    my $self = shift;

    return $self->last_overlay_id($self->last_overlay_id + 1)
      ->last_overlay_id;
}

sub node_name {
    return shift->id . DEVICE_POSTFIX;
}

# For multipath
sub _gen_node_name {
    my ($self, $pcount, $pid) = @_;

    if ($pcount > 1) {
        return $self->node_name . '-' . $pid;
    }
    return $self->node_name;
}

sub gen_cmdline {
    my ($self) = @_;
    my @cmdln = ();
    my $paths = @{$self->paths} < 1 ? [OpenQA::Qemu::DrivePath->new()] : $self->paths;
    my $pathn = scalar @$paths;

    # First create params which tell QEMU where the drive content is and what
    # format it is using
    push(@cmdln, $self->drive->gen_cmdline());

    # Then tell QEMU how to emulate the drive device
    for my $path (@$paths) {
        my @params = ($self->model,
            'id=' . $self->_gen_node_name($pathn, $path->id),
            'drive=' . $self->drive->node_name);

        push(@params, 'share-rw=true') if $pathn > 1;

        if (defined $path->controller) {
            push(@params, 'bus=' . $path->controller->id . '.0');
        }
        $self->_push_ifdef(\@params, 'bootindex=', $self->bootindex);
        $self->_push_ifdef(\@params, 'serial=',    $self->serial);
        push(@cmdln, ('-device', join(',', @params)));
    }

    return @cmdln;
}

sub gen_qemu_img_cmdlines {
    my $self = shift;

    return $self->drive->gen_qemu_img_cmdlines();
}

sub gen_qemu_img_rebase {
    my $self = shift;

    return $self->drive->gen_qemu_img_rebase();
}

sub gen_qemu_img_convert($$$) {
    my ($self, $img_dir, $name) = @_;

    return ['convert', '-c', '-O', 'qcow2', $self->drive->file, "$img_dir/$name"];
}

sub gen_unlink_list {
    my $self = shift;

    return $self->drive->gen_unlink_list();
}

sub for_each_overlay {
    my ($self, $sub) = @_;
    my $overlay = $self->drive;

    while (defined $overlay) {
        $sub->($overlay);
        $overlay = $overlay->backing_file;
    }
}

sub _to_map {
    my $self     = shift;
    my @overlays = ();
    my @paths    = map { $_->_to_map() } @{$self->paths};

    $self->for_each_overlay(sub {
            my $ol = shift;

            push(@overlays, $ol->_to_map());
    });

    return {drives => \@overlays,
        model     => $self->model,
        paths     => \@paths,
        bootindex => $self->bootindex,
        serial    => $self->serial,
        id        => $self->id};
}

sub _from_map {
    my ($self, $map, $cont_conf, $snap_conf) = @_;
    my $drive = OpenQA::Qemu::BlockDev->new()->_from_map($map->{drives}, $snap_conf);
    my @paths = map {
        OpenQA::Qemu::DrivePath->new()->_from_map($_, $cont_conf)
    } @{$map->{paths}};

    return $self->drive($drive)
      ->model($map->{model})
      ->paths(\@paths)
      ->bootindex($map->{bootindex})
      ->serial($map->{serial})
      ->id($map->{id});
}

sub CARP_TRACE {
    return 'OpenQA::Qemu::DriveDevice(' . (shift->id || '') . ')';
}

=head3 OpenQA::Qemu::PFlashDevice

Some storage devices can only be created using the '-drive' parameter in
QEMU. Pflash is one such device (at the time of writing), so we can not use a
standard drive device to represent it. This limits our control over how the
drive device and block device chain are created; we can not set the node id of
the top block device for example nor can we override the backing file AFAIK.

This class is the same as DriveDevice except for a few extra fields and
gen_cmdline has been overriden to use '-drive' instead.

=cut
package OpenQA::Qemu::PFlashDevice;
use Mojo::Base 'OpenQA::Qemu::DriveDevice';

has model => 'pflash';
has 'unit';
has 'readonly';

sub gen_cmdline {
    my ($self) = @_;
    my $drive  = $self->drive;
    my @params = ('id=' . $drive->node_name,
        "if=pflash",
        'file=' . $drive->file);

    $self->_push_ifdef(\@params, 'unit=',     $self->unit);
    $self->_push_ifdef(\@params, 'readonly=', $self->readonly);

    return ('-drive', join(',', @params));
}

=head2 OpenQA::Qemu::BlockDevConf

Configure block devices and drives.

=cut
package OpenQA::Qemu::BlockDevConf;
use Mojo::Base 'OpenQA::Qemu::MutParams';
use Mojo::JSON 'encode_json';
use Storable 'freeze';

use constant OVERLAY_POSTFIX => '-overlay';

has basedir => 'raid';

has _drives => sub { return []; };

=head3 add_existing_base

Add an existing image file at the bottom/start of a block device chain.

=cut
sub add_existing_base {
    my ($self, $id, $file_name, $size) = @_;
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
sub add_new_base {
    my ($self, $id, $file_name, $size) = @_;
    $file_name //= $id;

    return $self->add_existing_base($id, $self->basedir . '/' . $file_name, $size)
      ->needs_creating(1);
}

=head3 add_existing_overlay

Add an existing image file as the overlay of $backing_file.

=cut
sub add_existing_overlay {
    my ($self, $id, $backing_file) = @_;

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
sub add_new_overlay {
    return add_existing_overlay(@_)->needs_creating(1);
}

sub del_overlay {
    my ($self) = @_;
}

sub _push_new_drive_dev {
    my ($self, $id, $drive, $model) = @_;

    die 'PFlash drives are not supported by DriveDevice, use PFlashDevice'
      if $model eq 'pflash';

    my $dd = OpenQA::Qemu::DriveDevice->new()
      ->id($id)
      ->drive($drive)
      ->model($model);
    push(@{$self->_drives}, $dd);

    return $dd;
}

=head3 add_new_drive

Create a new drive device and qcow2 image.

=cut
sub add_new_drive {
    my ($self, $id, $model, $size) = @_;

    my $base_drive = $self->add_new_base($id, $id, $size);

    return $self->_push_new_drive_dev($id, $base_drive, $model);
}

=head3 add_existing_drive

Create a new drive device with an existing qcow2 image as the backing store. A
new overlay is created so that the existing qcow2 image is not modified.

=cut
sub add_existing_drive {
    my ($self, $id, $file_name, $model, $size) = @_;

    my $base_drive = $self->add_existing_base($id, $file_name, $size)->implicit(1);
    my $overlay = $self->add_new_overlay($id . OVERLAY_POSTFIX . '0', $base_drive);

    return $self->_push_new_drive_dev($id, $overlay, $model);
}


=head3 add_iso_drive

Add a cdrom or USB drive with a raw ISO image as the backing store. An overlay
is created, so the test can write to this drive and it won't modify the
underlying image.

=cut
sub add_iso_drive {
    my ($self, $id, $file_name, $model, $size) = @_;

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
sub add_pflash_drive {
    my ($self, $id, $file_name, $size) = @_;
    my $base_drive = $self->add_existing_base($id, $file_name, $size)
      ->implicit(1)
      ->driver($file_name =~ qr/\.qcow2$/ ? 'qcow2' : 'raw');
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
sub add_path_to_drive {
    my ($self, $id, $drive, $controller) = @_;

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
sub add_snapshot_to_drive {
    my ($self, $drive, $snapshot) = @_;
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
sub revert_to_snapshot {
    my ($self, $drive, $snapshot) = @_;
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

sub for_each_drive {
    my ($self, $sub) = @_;

    for my $drive (@{$self->_drives}) {
        $sub->($drive);
    }

    return $self;
}

sub mark_all_created {
    my $self = shift;

    $self->for_each_drive(sub {
            shift->for_each_overlay(sub {
                    shift->needs_creating(0);
            });
    });
}

# See MutParams.pm
sub gen_cmdline {
    my $self = shift;

    return map { $_->gen_cmdline() } @{$self->_drives};
}

=head3 gen_qemu_img_cmdlines

Create qemu-img command lines for all drives that need creating.

=cut
sub gen_qemu_img_cmdlines {
    my $self = shift;

    return map { $_->gen_qemu_img_cmdlines() } @{$self->_drives};
}

=head3 gen_qemu_img_rebase

Create qemu-img command lines for all overlays which need rebasing (See
comments about relative backing file paths).

=cut
sub gen_qemu_img_rebase {
    my ($self, $filter) = @_;

    return
      map  { $_->gen_qemu_img_rebase() }
      grep { $_->id =~ $filter } @{$self->_drives};
}

sub gen_qemu_img_commit {
    my $self = shift;

    return grep { defined $_ } map { $_->gen_qemu_img_commit() } @{$self->_drives};
}

sub gen_qemu_img_convert($$$$) {
    my ($self, $filter, $img_dir, $name) = @_;

    return
      map { $_->gen_qemu_img_convert($img_dir, $name) }
      grep { $_->id =~ $filter } @{$self->_drives};
}

=head3 gen_unlink_list

Generate a list of all files which are marked for creation. So that they can
be safely deleted if they already exist.

=cut
sub gen_unlink_list {
    my $self = shift;

    return map { $_->gen_unlink_list() } @{$self->_drives};
}

# See MutParams.pm
sub to_map {
    my $self = shift;
    my @drives = map { $_->_to_map() } @{$self->_drives};

    return {basedir => $self->basedir, drives => \@drives};
}

# See MutParams.pm
sub from_map {
    my ($self, $map, $cont_conf, $snap_conf) = @_;
    my @drives = map {
        $_->{model} eq 'pflash' ?
          OpenQA::Qemu::PFlashDevice->new()->_from_map($_, $cont_conf, $snap_conf) :
          OpenQA::Qemu::DriveDevice->new()->_from_map($_, $cont_conf, $snap_conf)
    } @{$map->{drives}};

    return $self->basedir($map->{basedir})->_drives(\@drives);
}

# See MutParams.pm
sub has_state {
    return scalar(@{shift->_drives});
}

1;
