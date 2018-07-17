# Copyright © 2018 SUSE LLC
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

=head2 OpenQA::Qemu::DriveDevice

The device which the SUT sees. The data on the device depends on the block dev
chain pointed to by 'drive'.

=cut
package OpenQA::Qemu::DriveDevice;
use Mojo::Base 'OpenQA::Qemu::MutParams';
use Mojo::JSON 'encode_json';
use OpenQA::Qemu::DrivePath;
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

sub gen_qemu_img_convert {
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

1;
