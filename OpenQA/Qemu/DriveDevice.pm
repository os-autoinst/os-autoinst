# Copyright 2018-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

=head2 OpenQA::Qemu::DriveDevice

The device which the SUT sees. The data on the device depends on the block dev
chain pointed to by 'drive'.

=cut

package OpenQA::Qemu::DriveDevice;
use Mojo::Base 'OpenQA::Qemu::MutParams', -signatures;

use OpenQA::Qemu::DrivePath;

use constant DEVICE_POSTFIX => '-device';
use constant QEMU_IMAGE_FORMAT => 'qcow2';

use Exporter 'import';
our @EXPORT_OK = qw(QEMU_IMAGE_FORMAT);

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

=head3 logical_block_size

WIP - The logical block size of the drive

=cut
has 'logical_block_size';

=head physical_block_size

The physical block size of the drive

=cut
has 'physical_block_size';

=head3 num_queues

The number of I/O queues of the drive, esp. for NVMe devices

=cut
has 'num_queues';

sub new_overlay_id ($self) { $self->last_overlay_id($self->last_overlay_id + 1)->last_overlay_id }

sub node_name ($self) { $self->id . DEVICE_POSTFIX }

# For multipath
sub _gen_node_name ($self, $pcount, $pid) { $pcount > 1 ? $self->node_name . '-' . $pid : $self->node_name }

sub gen_cmdline ($self) {
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
        # Configure bootindex only for first path
        $self->_push_ifdef(\@params, 'bootindex=', $self->bootindex) if (!$path->id || $path->id eq 'path0');
        $self->_push_ifdef(\@params, 'serial=', $self->serial);
        $self->_push_ifdef(\@params, 'num_queues=', $self->num_queues) if (($self->num_queues // -1) != -1);
        # logical_block_size=4096,physical_block_size=4096
        $self->(_push_ifdef(\@params, 'logical_block_size=', $self->drive->logical_block_size));
        $self->(_push_ifdef(\@params, 'physical_block_size=', $self->drive->physical_block_size));
        push(@cmdln, ('-device', join(',', @params)));
    }

    return @cmdln;
}

sub gen_qemu_img_cmdlines ($self) { $self->drive->gen_qemu_img_cmdlines() }

sub gen_qemu_img_convert ($self, $img_dir, $name, $qemu_compress_qcow) {
    # By compressing we are making the images self contained, i.e. they are
    # portable by not requiring backing files referencing the openQA instance.
    # Compressing takes longer but the transfer takes shorter amount of time.
    my $compress = $qemu_compress_qcow;
    my @cmd = qw(convert);
    push @cmd, qw(-c -W) if $compress;
    push @cmd, ('-O', QEMU_IMAGE_FORMAT, $self->drive->file, "$img_dir/$name");
    return \@cmd;
}

sub gen_unlink_list ($self) { $self->drive->gen_unlink_list() }

sub for_each_overlay ($self, $sub) {
    my $overlay = $self->drive;

    while (defined $overlay) {
        $sub->($overlay);
        $overlay = $overlay->backing_file;
    }
}

sub _to_map ($self) {
    my @overlays = ();
    my @paths = map { $_->_to_map() } @{$self->paths};

    $self->for_each_overlay(sub ($ol) {
            push(@overlays, $ol->_to_map());
    });

    return {drives => \@overlays,
        model => $self->model,
        paths => \@paths,
        bootindex => $self->bootindex,
        serial => $self->serial,
        logical_block_size => $self->logical_block_size,
        physical_block_size => $self->physical_block_size,
        id => $self->id,
        num_queues => $self->num_queues};
}

sub _from_map ($self, $map, $cont_conf, $snap_conf) {
    my $drive = OpenQA::Qemu::BlockDev->new()->_from_map($map->{drives}, $snap_conf);
    my @paths = map {
        OpenQA::Qemu::DrivePath->new()->_from_map($_, $cont_conf)
    } @{$map->{paths}};

    return $self->drive($drive)
      ->model($map->{model})
      ->paths(\@paths)
      ->bootindex($map->{bootindex})
      ->serial($map->{serial})
      ->logical_block_size($map->logical_block_size),
      ->physical_block_size($map->physical_block_size),
      ->id($map->{id}),
      ->num_queues($map->{num_queues});
}

sub CARP_TRACE ($self) { 'OpenQA::Qemu::DriveDevice(' . ($self->id || '') . ')' }

1;
