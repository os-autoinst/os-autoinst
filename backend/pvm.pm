# Copyright © 2016-2021 SUSE LLC
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

package backend::pvm;

use Mojo::Base -strict, -signatures;
use autodie ':all';

use base 'backend::baseclass';

use bmwqemu qw(diag);
use File::Path 'mkpath';
require IPC::System::Simple;
use File::Basename;
use Digest::MD5 'md5_hex';
use osutils qw(dd_gen_params gen_params runcmd);

# this backend relies on NovaLink tools being around on the worker
# host. It supports HDD_1 and publishing assets

# the spvm backend will only support the basics, but generally through
# ssh to a novalink installation (so you only need ssh and terminal on worker)

sub new ($class) {
    my $self       = $class->SUPER::new;
    my $masterlpar = qx{cat /proc/device-tree/ibm,partition-name};
    $self->{pid}         = undef;
    $self->{children}    = [];
    $self->{pidfilename} = 'pvm.pid';
    $self->{pvmctl}      = '/usr/bin/pvmctl';
    $self->{masterlpar}  = substr($masterlpar, 0, -1);
    die "pvmctl not found" unless -x $self->{pvmctl};

    return $self;
}

sub do_start_vm ($self) {
    $self->start_lpar();
    return {};
}

sub do_extract_assets ($self, $args) {
    my $vars    = \%bmwqemu::vars;
    my $hdd_num = $args->{hdd_num};
    my $name    = $args->{name};
    my $img_dir = $args->{dir};
    my $format  = $args->{format};
    my $disk    = $vars->{"HDD_$hdd_num"};
    my $lpar    = $self->{masterlpar};
    my $cmd     = "pvmctl scsi list -w";
    $cmd = $cmd . " VirtualDisk.name=$disk";
    $cmd = $cmd . " -d VirtualDisk.udid --hide-label";
    #attach disk
    diag "Attaching $disk to $lpar";
    $self->pvmctl("scsi", "create", "lv", $disk, $lpar);

    my $prefix = "/dev/disk/by-id/scsi-SAIX_VDASD_";
    my $id     = qx{$cmd};
    chomp($id);
    my $device = $prefix . substr($id, 2);

    if (!$format || $format !~ /^raw$/) {
        diag "do_extract_assets: Image will be saved as raw eitherway";
    }

    #rescan scsi for newly attached disk
    qx{sudo rescan-scsi-bus.sh -a};
    #wait until udev creates a link
    until (-l $device) {
        sleep 1;
    }
    mkpath($img_dir);
    runcmd("sudo", "dd", "if=$device", "of=$img_dir/$name.$format", "bs=8096", "conv=sparse");

    #detach disk
    $self->pvmctl("scsi", "delete", "lv", $disk, $lpar);
    qx/sudo rescan-scsi-bus.sh -r/;
}

sub pvmctl ($self, $type, $action) {
    my $vars = \%bmwqemu::vars;

    die "pvmctl: Not enough arguments (at least you should supply a type and an action)" unless ($type && $action);

    push(my @cmd, $self->{pvmctl}, $type, $action);
    my $lpar = $vars->{LPAR};

    if ($type =~ /lpar/) {
        gen_params @cmd, "i", "name=$lpar" if ($lpar && $action =~ /power|restart|delete/);
        if ($action =~ /create/) {
            my ($cpu, $memory) = @_;
            dd_gen_params @cmd, "proc-type",    "shared";
            dd_gen_params @cmd, "sharing-mode", "uncapped";
            dd_gen_params @cmd, "type",         "AIX/Linux";
            dd_gen_params @cmd, "proc",         $cpu        if $cpu;
            dd_gen_params @cmd, "mem",          $memory     if $memory;
            dd_gen_params @cmd, "name",         $lpar       if $lpar;
            dd_gen_params @cmd, "proc-unit",    $cpu * 0.05 if $cpu;
        }
    }
    elsif ($type =~ /scsi/) {
        my ($kind, $file, $target) = @_;
        die "pvmctl: scsi type needs at least both kind and file" unless ($kind && $file);

        #so far only disks are reatachable to the master LPAR
        #set it back to default if argument is omited
        $lpar = $target if $target;
        dd_gen_params @cmd, "type",    $kind;
        dd_gen_params @cmd, "stor-id", $file;
        dd_gen_params @cmd, "lpar",    "name=$lpar"  if $lpar;
        dd_gen_params @cmd, "vg",      "name=rootvg" if ($type =~ /lv/);
    }
    elsif ($type =~ /lv/) {
        my ($name, $size) = @_;
        dd_gen_params @cmd, "name", $name if $name;
        dd_gen_params @cmd, "size", $size if $size;
    }
    elsif ($type =~ /eth/) {
        my ($vlan, $vswitch) = @_;
        dd_gen_params @cmd, "pvid",    $vlan        if $vlan;
        dd_gen_params @cmd, "vswitch", $vswitch     if $vswitch;
        gen_params @cmd,    "p",       "name=$lpar" if $lpar;
    }
    else {
        die "Unrecognized command $type";
    }
    runcmd(@cmd);
}
sub attach_console ($vars) {
    my $vncport = qx{sudo /usr/sbin/mkvtermutil --id $vars->{LPARID} --vnc --local --log serial0 2>/dev/null};
    $vncport =~ /([0-9]+)/;
    chomp($vncport);
    $vars->{VNC} = $vncport;
    diag "VNC is $vars->{VNC}";
}

sub image_exists ($img, $size) {
    #lv already exists?
    my @cmd;
    my $pvmctlcmd = "pvmctl lv list -w LogicalVolume.name=$img -d LogicalVolume.name LogicalVolume.capacity -f , --hide-label";
    my ($name, $capacity) = split(",", qx/$pvmctlcmd/);
    return if !($name =~ /$img/);
    if (($img =~ /$name/) && ($size =~ /$capacity/)) {
        push(@cmd, "sudo viosvrcmd --id 1 -r -c \"dd if=/dev/zero bs=1024 count=1 of=/dev/r$name\"");
    }
    else {
        push(@cmd, "sudo viosvrcmd --id 1 -c\"rmbdsp -sp rootvg -bd $name\"");
    }
    runcmd(@cmd);
}
sub start_lpar ($self) {
    my $vars = \%bmwqemu::vars;
    #general settiings
    $vars->{LPAR} = "osauto" . $vars->{WORKER_ID};
    $vars->{CPUS} ||= 1;
    $vars->{MEM}  ||= "2048";
    #disk settings
    $vars->{NUMDISKS} //= 1;
    $vars->{HDDSIZEGB} ||= 15;
    #network settings
    $vars->{NIC}     ||= "sea";
    $vars->{NICVLAN} ||= 1;
    $vars->{VSWITCH} ||= "ETHERNET0";
    #unfortunately NovaLink can't take files longer than 38 chars. So we need to shorten ISO name here
    $vars->{VIOISO} = md5_hex(basename($vars->{ISO})) . ".iso";
    my $iso = $vars->{VIOISO};
    die "$iso exceeds 37 characters\n" if (length($iso) > 37);

    if (!($vars->{ARCH} =~ /ppc64/)) {
        die "arch $vars->{ARCH} is not allowed on pvm backend";
    }
    #create lpar
    $self->pvmctl("lpar", "create", $vars->{CPUS}, $vars->{MEM});

    my $id = substr(qx/pvmctl lpar list -d LogicalPartition.id --where LogicalPartition.name=$vars->{LPAR}/, 3);
    chomp($id);
    $vars->{LPARID} = $id;
    bmwqemu::save_vars();

    #we copy isos from nfs mount on VIO side to VMLibrary
    my $source_iso = '/iso/' . basename($vars->{ISO});
    diag "source_iso: $source_iso, vio iso: $iso";
    my $iso_present = qx/pvmctl media list -d VirtualOpticalMedia.media_name --where VirtualOpticalMedia.name=$iso/;
    if ($iso_present !~ /$iso/) {
        #copy over from nfs to VMLibrary
        my @viocmd = ("sudo viosvrcmd --id 1 -r -c\"cp $source_iso /var/vio/VMLibrary/$iso\"");
        push(@viocmd, "sudo viosvrcmd --id 1 -r -c\"chown padmin:staff /var/vio/VMLibrary/$iso\"");
        push(@viocmd, "sudo viosvrcmd --id 1 -c\"chvopt -name $iso -access ro\"");
        foreach my $viocmd (@viocmd) {
            runcmd($viocmd);
        }
    }
    $self->pvmctl('scsi', 'create', 'vopt', $iso);

    for my $i (1 .. $vars->{NUMDISKS}) {
        my $name = $vars->{LPAR} . "_" . $i;
        $vars->{"HDD_$i"} = $name;
        my $size = $vars->{HDDSIZEGB};
        $self->pvmctl("lv",   "create", $name, $size) if !image_exists($name, $size);
        $self->pvmctl("scsi", "create", "lv",  $name);
    }

    $self->pvmctl("eth", "create", $vars->{NICVLAN}, $vars->{VSWITCH});
    $self->pvmctl("lpar", "power-on");
    bmwqemu::save_vars();

    attach_console;
    bmwqemu::save_vars();

    my $vnc = $testapi::distri->add_console(
        'sut',
        'vnc-base',
        {
            hostname => 'localhost',
            port     => $vars->{VNC}});
    $vnc->backend($self);
    $self->select_console({testapi_console => 'sut'});
}

sub _status ($self) {
    my $id = $bmwqemu::vars{LPARID};
    return qx{pvmctl lpar list -i id=$id -d LogicalPartition.state --hide-label};
}

sub is_shutdown ($self) {
    return $self->_status =~ /running/;
}

sub do_stop_vm ($self) {
    my $vars = \%bmwqemu::vars;
    $self->pvmctl("lpar", "power-off") if (!$self->is_shutdown);
    runcmd("rmvterm", "--id", $vars->{LPARID});
    for my $i (1 .. $vars->{NUMDISKS}) {
        my $disk = $vars->{LPAR} . "_" . $i;
        $self->pvmctl("scsi", "delete", "lv", $disk);
    }
    $self->pvmctl("scsi", "delete", "vopt", $vars->{VIOISO});
    $self->pvmctl("lpar", "delete");
}
