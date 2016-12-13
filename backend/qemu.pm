# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2015 SUSE LLC
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

package backend::qemu;
use strict;
use base 'backend::virt';
use File::Path 'mkpath';
use Time::HiRes qw(sleep gettimeofday);
use IO::Select;
use IO::Socket::UNIX 'SOCK_STREAM';
use IO::Handle;
use POSIX qw(strftime :sys_wait_h);
use JSON;
use Carp;
use Fcntl;
use Net::DBus;
use bmwqemu qw(fileContent diag save_vars);
require IPC::System::Simple;
use autodie ':all';

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new;

    $self->{pid}         = undef;
    $self->{children}    = [];
    $self->{pidfilename} = 'qemu.pid';

    return $self;
}

# baseclass virt method overwrite

sub raw_alive {
    my ($self) = @_;
    return 0 unless $self->{pid};
    return kill(0, $self->{pid});
}

sub start_audiocapture {
    my ($self, $args) = @_;

    $self->_send_hmp("wavcapture $args->{filename} 44100 16 1");
}

sub stop_audiocapture {
    my ($self, $args) = @_;
    $self->_send_hmp("stopcapture 0");
}

sub power {

    # parameters: acpi, reset, (on), off
    my ($self, $args) = @_;
    my $action = $args->{action};
    if ($action eq 'acpi') {
        $self->_send_hmp("system_powerdown");
    }
    elsif ($action eq 'reset') {
        $self->_send_hmp("system_reset");
    }
    elsif ($action eq 'off') {
        $self->handle_qmp_command({execute => 'quit'});
    }
}

sub eject_cd {
    my $self = shift;
    $self->handle_qmp_command({execute => 'eject', arguments => {device => 'cd0'}});
}

sub cpu_stat {
    my $self = shift;
    my $stat = bmwqemu::fileContent("/proc/" . $self->{pid} . "/stat");
    my @a    = split(" ", $stat);
    return [@a[13, 14]];
}

sub do_start_vm {
    my $self = shift;

    # remove backend.crashed
    $self->unlink_crash_file();
    $self->start_qemu();
    return {};
}

sub kill_qemu {
    my ($self) = (@_);
    my $pid = $self->{pid};

    # already gone?
    my $ret = waitpid($pid, WNOHANG);
    diag "waitpid for $pid returned $ret";
    return if ($ret == $pid || $ret == -1);

    diag "sending TERM to qemu pid: $pid";
    kill('TERM', $pid);
    for my $i (1 .. 5) {
        sleep 1;
        $ret = waitpid($pid, WNOHANG);
        diag "waitpid for $pid returned $ret";
        last if ($ret == $pid);
    }
    unless ($ret == $pid) {
        kill("KILL", $pid);
        # now we have to wait
        waitpid($pid, 0);
    }

    for my $pid (@{$self->{children}}) {
        diag("killing child $pid");
        kill('TERM', $pid);
        for my $i (1 .. 5) {
            $ret = waitpid($pid, WNOHANG);
            diag "waitpid for $pid returned $ret";
            last if ($ret == $pid);
            sleep 1;
        }
    }
}

sub do_stop_vm {
    my $self = shift;

    return unless $self->{pid};
    kill_qemu($self);
    $self->{pid} = undef;
    unlink($self->{pidfilename});
}

sub can_handle {
    my ($self, $args) = @_;
    my $vars = \%bmwqemu::vars;
    if ($args->{function} eq 'snapshots' && $vars->{HDDFORMAT} ne 'raw') {
        return {ret => 1};
    }
    return;
}

sub save_memory_dump {
    my ($self, $args) = @_;
    my $rsp = 0;

    bmwqemu::diag("Migrating the machine.");

    mkpath("ulogs");

    $rsp = $self->handle_qmp_command(
        {
            execute   => "migrate",
            arguments => {
                uri => sprintf("exec:gzip -c > ulogs/%s-vm-memory-dump.gz", $args->{filename}),
            }});

    die(sprintf("Migration failed: desc: %s, class: %s, stopped", $rsp->{error}->{desc}, $rsp->{error}->{class})) if ($rsp->{error});


    do {

        sleep 0.5;    #We want to wait a decent amount of time, a file of 1GB will be
                      # migrated in about 40secs with an ssd drive. and no heavy load.
        $rsp = $self->handle_qmp_command({execute => "query-migrate"});

        diag "Migrating total bytes:     \t" . $rsp->{return}->{ram}->{total};
        diag "Migrating remaining bytes:   \t" . $rsp->{return}->{ram}->{remaining};

    } until ($rsp->{return}->{status} eq "completed");

    diag "Migration completed.";
    return;
}

sub save_storage_drives {
    my ($self, $args) = @_;

    diag "Attemping to extract disk #%d.", $args->{disk};

    $self->do_extract_assets(
        {
            hdd_num => $args->{disk},
            name    => sprintf("%s-%d-vm_disk_file.qcow2", $args->{filename}, $args->{disk}),
            dir     => "ulogs",
            format  => "qcow2"
        });

    diag "Sucessfully extracted disk #%d.", $args->{disk};
    return;
}

sub save_snapshot {
    my ($self, $args) = @_;
    my $vmname = $args->{name};
    my $rsp    = $self->_send_hmp("savevm $vmname");
    diag "SAVED $vmname $rsp";
    die "Could not save snapshot \'$vmname\'" unless ($rsp eq "savevm $vmname");
    return;
}

sub load_snapshot {
    my ($self, $args) = @_;
    my $vmname = $args->{name};
    my $rsp    = $self->_send_hmp("loadvm $vmname");
    die "Could not load snapshot \'$vmname\'" unless ($rsp eq "loadvm $vmname");
    $rsp = $self->handle_qmp_command({execute => 'stop'});
    $rsp = $self->handle_qmp_command({execute => 'cont'});
    sleep(10);
    return $rsp;
}

sub runcmd {
    diag "running " . join(' ', @_);
    local $SIG{CHLD} = 'IGNORE';
    return CORE::system(@_);
}

sub do_extract_assets {
    my ($self, $args) = @_;
    my $hdd_num = $args->{hdd_num};
    my $name    = $args->{name};
    my $img_dir = $args->{dir};
    my $format  = $args->{format};
    if (!$format || $format !~ /^(raw|qcow2)$/) {
        bmwqemu::diag "do_extract_assets: only raw and qcow2 formats supported $name $format";
    }
    elsif (-f "raid/l$hdd_num") {
        bmwqemu::diag "preparing hdd $hdd_num for upload as $name in $format";
        mkpath($img_dir);
        my @cmd = ('nice', 'ionice', 'qemu-img', 'convert', '-O', $format, "raid/l$hdd_num", "$img_dir/$name");
        if ($format eq 'raw') {
            runcmd(@cmd);
        }
        elsif ($format eq 'qcow2') {
            push @cmd, '-c' if $bmwqemu::vars{QEMU_COMPRESS_QCOW2};
            # including all snapshots is prohibitively big
            if ($bmwqemu::vars{MAKETESTSNAPSHOTS} || $bmwqemu::vars{QEMU_COMPRESS_QCOW2}) {
                runcmd(@cmd);
            }
            else {
                symlink("../raid/l$hdd_num", "$img_dir/$name");
            }
        }
    }
    else {
        bmwqemu::diag "do_extract_assets: hdd $hdd_num does not exist";
    }
}


# baseclass virt method overwrite end

sub start_qemu {

    my $self = shift;
    my $vars = \%bmwqemu::vars;

    my $basedir = "raid";
    my $qemuimg = "/usr/bin/kvm-img";
    if (!-e $qemuimg) {
        $qemuimg = "/usr/bin/qemu-img";
    }

    my $qemubin = $ENV{QEMU};
    unless ($qemubin) {
        my @candidates = $vars->{QEMU} ? ('qemu-system-' . $vars->{QEMU}) : qw(kvm qemu-kvm qemu qemu-system-x86_64 qemu-system-ppc64);
        for my $bin (map { '/usr/bin/' . $_ } @candidates) {
            next unless -x $bin;
            $qemubin = $bin;
            last;
        }
        die "no Qemu/KVM found\n" unless $qemubin;
    }

    if ($vars->{UEFI}) {
        # XXX: compat with old deployment
        $vars->{BIOS} //= $vars->{UEFI_BIOS};
    }

    if ($vars->{UEFI_PFLASH}) {
        $vars->{UEFI} = 1;
    }

    foreach my $attribute (qw(BIOS KERNEL INITRD)) {
        if ($vars->{$attribute} && $vars->{$attribute} !~ /^\//) {
            # Non-absolute paths are assumed relative to /usr/share/qemu
            $vars->{$attribute} = '/usr/share/qemu/' . $vars->{$attribute};
        }
        if ($vars->{$attribute} && !-e $vars->{$attribute}) {
            die "'$vars->{$attribute}' missing, check $attribute\n";
        }
    }

    if ($vars->{UEFI} && $vars->{ARCH} eq 'x86_64' && !$vars->{BIOS}) {
        foreach my $firmware (@bmwqemu::ovmf_locations) {
            if (-e $firmware) {
                $vars->{BIOS} = $firmware;
                last;
            }
        }
        if (!$vars->{BIOS}) {
            # We know this won't go well.
            die "No UEFI firmware can be found! Please specify BIOS or UEFI_BIOS or install an appropriate package";
        }
    }

    if ($vars->{LAPTOP}) {
        if ($vars->{LAPTOP} =~ /\/|\.\./) {
            die "invalid characters in LAPTOP\n";
        }
        $vars->{LAPTOP} = 'dell_e6330' if $vars->{LAPTOP} eq '1';
        die "no dmi data for '$vars->{LAPTOP}'\n" unless -d "$bmwqemu::scriptdir/dmidata/$vars->{LAPTOP}";
    }

    my $bootfrom = '';    # branch by "disk" or "cdrom", not "c" or "d"
    if ($vars->{BOOT_HDD_IMAGE}) {
        # skip dvd boot menu and boot directly from hdd
        $vars->{BOOTFROM} //= 'c';
    }
    if (my $bootfrom_var = $vars->{BOOTFROM}) {
        if ($bootfrom_var eq 'd' || $bootfrom_var eq 'cdrom') {
            $bootfrom = 'cdrom';
            $vars->{BOOTFROM} = 'd';
        }
        elsif ($bootfrom_var eq 'c' || $bootfrom_var eq 'disk') {
            $bootfrom = 'disk';
            $vars->{BOOTFROM} = 'c';
        }
        else {
            die "unknown/unsupported boot order: $bootfrom_var";
        }
    }

    my $iso = $vars->{ISO};
    # disk settings
    $vars->{NUMDISKS}  ||= 1;
    $vars->{HDDSIZEGB} ||= 10;
    $vars->{CDMODEL}   ||= "scsi-cd";
    if ($vars->{MULTIPATH}) {
        $vars->{HDDMODEL}  ||= "scsi-hd";
        $vars->{HDDFORMAT} ||= "raw";
        $vars->{PATHCNT}   ||= 2;
    }
    $vars->{HDDMODEL}  ||= "virtio-blk";
    $vars->{HDDFORMAT} ||= "qcow2";

    # Deprecated behaviour: set scsi controller using the value of the HDD or CD Model.
    # Then set the HDD or CD model to an actual drive type.
    for my $var (qw(HDDMODEL CDMODEL)) {
        if ($vars->{$var} =~ /virtio-scsi.*/) {
            $vars->{SCSICONTROLLER} = $vars->{$var};
            $vars->{$var} = sprintf "scsi-%sd", lc substr $var, 0, 1;
        }
    }

    # New behaviour: create default scsi controller for common scsi devices or use the
    # controller type specified by the user.
    if ($vars->{CDMODEL} eq 'scsi-cd' || $vars->{HDDMODEL} eq 'scsi-hd') {
        $vars->{SCSICONTROLLER} ||= "virtio-scsi-pci";
    }

    # network settings
    $vars->{NICMODEL} ||= "virtio-net";
    $vars->{NICTYPE}  ||= "user";
    $vars->{NICMAC}   ||= "52:54:00:12:34:56" if $vars->{NICTYPE} eq 'user';
    if ($vars->{NICTYPE} eq "vde") {
        $vars->{VDE_SOCKETDIR} ||= '.';
        # use consistent port. port 1 is slirpvde so add + 2.
        # *2 to have another slot for slirpvde. Default number
        # of ports is 32 so enough for 14 workers per host.
        $vars->{VDE_PORT} ||= ($vars->{WORKER_ID} // 0) * 2 + 2;
    }
    # misc
    my $arch_supports_boot_order = 1;
    my $use_usb_kbd;
    my @vgaoptions;
    if ($vars->{UEFI}) {    # UEFI/OVMF supports ",bootindex=N", but not "-boot order=X"
        $arch_supports_boot_order = 0;
    }
    if ($vars->{ARCH} eq 'aarch64' || $vars->{ARCH} eq 'arm') {
        push @vgaoptions, '-device', 'VGA';
        $arch_supports_boot_order = 0;
        $use_usb_kbd              = 1;
    }
    elsif ($vars->{OFW}) {
        $vars->{QEMUVGA} ||= "std";
        $vars->{QEMUMACHINE} = "usb=off";
        push(@vgaoptions, '-g', '1024x768');
        $use_usb_kbd = 1;
    }
    else {
        $vars->{QEMUVGA} ||= "cirrus";
    }
    push(@vgaoptions, "-vga", $vars->{QEMUVGA}) if $vars->{QEMUVGA};

    if (defined($vars->{RAIDLEVEL})) {
        $vars->{NUMDISKS} = 4;
    }

    my @nicmac;
    my @nicvlan;
    my @tapdev;
    my @tapscript;
    my @tapdownscript;

    @nicmac        = split /\s*,\s*/, $vars->{NICMAC}        if $vars->{NICMAC};
    @nicvlan       = split /\s*,\s*/, $vars->{NICVLAN}       if $vars->{NICVLAN};
    @tapdev        = split /\s*,\s*/, $vars->{TAPDEV}        if $vars->{TAPDEV};
    @tapscript     = split /\s*,\s*/, $vars->{TAPSCRIPT}     if $vars->{TAPSCRIPT};
    @tapdownscript = split /\s*,\s*/, $vars->{TAPDOWNSCRIPT} if $vars->{TAPDOWNSCRIPT};

    my $num_networks = 1;
    $num_networks = @nicmac  if $num_networks < @nicmac;
    $num_networks = @nicvlan if $num_networks < @nicvlan;
    $num_networks = @tapdev  if $num_networks < @tapdev;

    for (my $i = 0; $i < $num_networks; $i++) {
        # ensure MAC addresses differ globally
        # and allow MAC addresses for more than 256 workers (up to 16384)
        my $workerid = $vars->{WORKER_ID};
        $nicmac[$i] //= sprintf('52:54:00:12:%02x:%02x', int($workerid / 256) + $i * 64, $workerid % 256);

        # always set proper TAPDEV for os-autoinst when using tap network mode
        my $instance = ($vars->{WORKER_INSTANCE} || 'manual') eq 'manual' ? 255 : $vars->{WORKER_INSTANCE};
        # use $instance for tap name so it is predicable, network is still configured staticaly
        $tapdev[$i] //= 'tap' . ($instance - 1 + $i * 64);

        $nicvlan[$i] //= 0;
    }
    push @tapscript,     "no" until @tapscript >= $num_networks;        #no TAPSCRIPT by default
    push @tapdownscript, "no" until @tapdownscript >= $num_networks;    #no TAPDOWNSCRIPT by default

    # put it back to the vars for save_vars()
    $vars->{NICMAC}        = join ',', @nicmac;
    $vars->{NICVLAN}       = join ',', @nicvlan;
    $vars->{TAPDEV}        = join ',', @tapdev if $vars->{NICTYPE} eq "tap";
    $vars->{TAPSCRIPT}     = join ',', @tapscript if $vars->{NICTYPE} eq "tap";
    $vars->{TAPDOWNSCRIPT} = join ',', @tapdownscript if $vars->{NICTYPE} eq "tap";


    if ($vars->{NICTYPE} eq "vde") {
        my $mgmtsocket = $vars->{VDE_SOCKETDIR} . '/vde.mgmt';
        my $port       = $vars->{VDE_PORT};
        my $vlan       = $nicvlan[0];
        # XXX: no useful return value from those commands
        runcmd('vdecmd', '-s', $mgmtsocket, 'port/remove', $port);
        runcmd('vdecmd', '-s', $mgmtsocket, 'port/create', $port);
        if ($vlan) {
            runcmd('vdecmd', '-s', $mgmtsocket, 'vlan/create', $vlan);
            runcmd('vdecmd', '-s', $mgmtsocket, 'port/setvlan', $port, $vlan);
        }

        if ($vars->{VDE_USE_SLIRP}) {
            # TODO: move infrastructure to fork and monitor children to baseclass
            my $pid = fork();
            die "fork failed" unless defined($pid);

            my @cmd = ('slirpvde', '--dhcp', '-s', "$vars->{VDE_SOCKETDIR}/vde.ctl", '--port', $port + 1);
            if ($pid == 0) {
                $SIG{__DIE__} = undef;    # overwrite the default - just exit
                exec(@cmd);
                die "failed to exec slirpvde";
            }
            diag join(' ', @cmd) . " started with pid $pid";
            push @{$self->{children}}, $pid;
            runcmd('vdecmd', '-s', $mgmtsocket, 'port/setvlan', $port + 1, $vlan) if $vlan;
        }
    }

    bmwqemu::save_vars();                 # update variables

    mkpath($basedir);

    my $keephdds = $vars->{KEEPHDDS} || $vars->{SKIPTO};

    # fresh HDDs
    for my $i (1 .. $vars->{NUMDISKS}) {
        # skip HDD refresh when HDD exists and KEEPHDDS or SKIPTO is set
        next if ($keephdds && (-e "$basedir/$i.lvm" || -e "$basedir/$i"));
        no autodie 'unlink';
        unlink("$basedir/l$i");
        if (-e "$basedir/$i.lvm") {
            symlink("$i.lvm", "$basedir/l$i") or die "$!\n";
            runcmd("/bin/dd", "if=/dev/zero", "count=1", "of=$basedir/l1");    # for LVM
        }
        elsif ($vars->{"HDD_$i"}) {
            # default: same size as the original image
            my @sizeopt = ();
            # HDD_$i specific size
            @sizeopt = ($vars->{"HDDSIZEGB_$i"} . "G") if $vars->{"HDDSIZEGB_$i"};
            runcmd($qemuimg, "create", "$basedir/$i", "-f", "qcow2", "-b", $vars->{"HDD_$i"}, @sizeopt);
            symlink($i, "$basedir/l$i") or die "$!\n";
        }
        else {
            # default: generic hdd size
            my @sizeopt = ($vars->{HDDSIZEGB} . "G");
            # HDD_$i specific size
            @sizeopt = ($vars->{"HDDSIZEGB_$i"} . "G") if $vars->{"HDDSIZEGB_$i"};
            runcmd($qemuimg, "create", "$basedir/$i", "-f", $vars->{HDDFORMAT}, @sizeopt);
            symlink($i, "$basedir/l$i") or die "$!\n";
        }
    }

    if ($vars->{AUTO_INST} && !$keephdds) {
        unlink("$basedir/autoinst.img");
        runcmd("/sbin/mkfs.vfat", "-C", "$basedir/autoinst.img", "1440");
        runcmd("/usr/bin/mcopy", "-i", "$basedir/autoinst.img", $vars->{AUTO_INST}, "::/");
    }

    for my $i (1 .. 4) {    # create missing symlinks
        next if -e "$basedir/l$i";
        next unless -e "$basedir/$i";
        symlink($i, "$basedir/l$i") or die "$!\n";
    }

    pipe(my $reader, my $writer);
    my $pid = fork();
    die "fork failed" unless defined($pid);
    if ($pid == 0) {
        $SIG{__DIE__} = undef;    # overwrite the default - just exit
        my @params = ("-serial", "file:serial0", "-soundhw", "ac97", "-global", "isa-fdc.driveA=", @vgaoptions);

        push(@params, '-m', $vars->{QEMURAM});

        if ($vars->{QEMUMACHINE}) {
            push(@params, "-machine", $vars->{QEMUMACHINE});
        }

        if ($vars->{QEMUCPU}) {
            push(@params, "-cpu", $vars->{QEMUCPU});
        }

        if ($vars->{QEMU_VIRTIO_RNG}) {
            push(@params, '-device', 'virtio-rng-pci');
        }

        for (my $i = 0; $i < $num_networks; $i++) {
            if ($vars->{NICTYPE} eq "user") {
                my $nictype_user_options = $vars->{NICTYPE_USER_OPTIONS} ? ',' . $vars->{NICTYPE_USER_OPTIONS} : '';
                push(@params, '-netdev', "user,id=qanet$i$nictype_user_options");
            }
            elsif ($vars->{NICTYPE} eq "tap") {
                push(@params, '-netdev', "tap,id=qanet$i,ifname=$tapdev[$i],script=$tapscript[$i],downscript=$tapdownscript[$i]");
            }
            elsif ($vars->{NICTYPE} eq "vde") {
                push(@params, '-netdev', "vde,id=qanet0,sock=$vars->{VDE_SOCKETDIR}/vde.ctl,port=$vars->{VDE_PORT}");
            }
            else {
                die "unknown NICTYPE $vars->{NICTYPE}\n";
            }
            push(@params, '-device', "$vars->{NICMODEL},netdev=qanet$i,mac=$nicmac[$i]");
        }

        if ($vars->{LAPTOP}) {
            my $laptop_path = "$bmwqemu::scriptdir/dmidata/$vars->{LAPTOP}";
            for my $f (glob "$laptop_path/*.bin") {
                push @params, '-smbios', "file=$f";
            }
        }

        if ($vars->{NBF}) {
            push(@params, '-kernel', '/usr/share/qemu/ipxe.lkrn');
            push(@params, '-append', "dhcp && sanhook iscsi:$vars->{WORKER_HOSTNAME}::3260:1:$vars->{NBF}");
        }

        if ($vars->{SCSICONTROLLER}) {
            # scsi devices need SCSI controller
            push(@params, "-device", "$vars->{SCSICONTROLLER},id=scsi0");
            if ($vars->{MULTIPATH}) {
                # add the second HBA
                push(@params, "-device", "$vars->{SCSICONTROLLER},id=scsi1");
            }
        }

        for my $i (1 .. $vars->{NUMDISKS}) {
            if ($vars->{MULTIPATH}) {
                for my $c (1 .. $vars->{PATHCNT}) {
                    # pathname is a .. d
                    my $bus = sprintf "scsi%d.0", ($c - 1) % 2;    # alternate between scsi0 and scsi1
                    my $id = sprintf 'hd%d%c', $i, 96 + $c;
                    # when booting from disk on UEFI, first connected disk gets ",bootindex=0"
                    my $bootindex = ($i == 1 && $c == 1 && $vars->{UEFI} && $bootfrom eq "disk") ? ",bootindex=0" : "";
                    push(@params, "-device", "$vars->{HDDMODEL},drive=$id,bus=$bus" . $bootindex);
                    push(@params, "-drive",  "file=$basedir/l$i,cache=none,if=none,id=$id,serial=mpath$i,format=$vars->{HDDFORMAT}");
                }
            }
            else {
                # when booting from disk on UEFI, first connected disk gets ",bootindex=0"
                my $bootindex = ($i == 1 && $vars->{UEFI} && $bootfrom eq "disk") ? ",bootindex=0" : "";
                push(@params, "-device", "$vars->{HDDMODEL},drive=hd$i" . $bootindex);
                push(@params, "-drive",  "file=$basedir/l$i,cache=unsafe,if=none,id=hd$i,format=$vars->{HDDFORMAT}");
            }
        }

        my $cdbus = $vars->{CDMODEL} ne 'ide-cd' ? ',bus=scsi0.0' : '';
        if ($iso) {
            if ($vars->{USBBOOT}) {
                push(@params, "-drive",  "if=none,id=usbstick,file=$iso,snapshot=on");
                push(@params, "-device", "usb-ehci,id=ehci");
                # when USBBOOT is defined on UEFI, it gets ",bootindex=0"
                my $bootindex = ($vars->{UEFI} && $bootfrom ne "disk") ? ",bootindex=0" : "";
                push(@params, "-device", "usb-storage,bus=ehci.0,drive=usbstick,id=devusb" . $bootindex);
            }
            else {
                push(@params, '-drive', "media=cdrom,if=none,id=cd0,format=raw,file=$iso");
                # XXX: workaround for OVMF wanting to write NVvars into first FAT partition
                # we need to replace -bios with proper pflash drive specification
                $params[-1] .= ',snapshot=on' if $vars->{UEFI};
                # when booting from cdrom on UEFI, first connected CD gets ",bootindex=0"
                my $bootindex = ($vars->{UEFI} && $bootfrom eq "cdrom") ? ",bootindex=0" : "";
                push(@params, '-device', "$vars->{CDMODEL},drive=cd0" . $cdbus . $bootindex);
            }
        }

        my $is_first = 1;
        for my $k (sort grep { /^ISO_\d+$/ } keys %$vars) {
            my $addoniso = $vars->{$k};
            my $i        = $k;
            $i =~ s/^ISO_//;
            # first connected cdrom gets ",bootindex=0" on UEFI when booting from cdrom and there wasn't `ISO` defined
            my $bootindex = "";
            if ($is_first && $vars->{UEFI} && $bootfrom eq "cdrom" && !$iso) {
                $is_first  = 0;
                $bootindex = ",bootindex=0";
            }
            push(@params, '-drive',  "media=cdrom,if=none,id=cd$i,format=raw,file=$addoniso");
            push(@params, '-device', "$vars->{CDMODEL},drive=cd$i" . $cdbus . $bootindex);
        }

        if ($arch_supports_boot_order) {
            if ($vars->{PXEBOOT}) {
                push(@params, "-boot", "n");
            }
            elsif ($vars->{BOOTFROM}) {
                push(@params, "-boot", "order=$vars->{BOOTFROM},menu=on,splash-time=5000");
            }
            else {
                push(@params, "-boot", "once=d,menu=on,splash-time=5000");
            }
        }

        if ($vars->{UEFI_PFLASH}) {
            # Convert the firmware file into qcow2 format or savevm would fail
            runcmd('qemu-img', 'convert', '-O', 'qcow2', $vars->{BIOS}, 'ovmf.bin');
            push(@params, "-drive", "if=pflash,format=qcow2,file=ovmf.bin");
        }
        elsif ($vars->{BIOS}) {
            push(@params, "-bios", $vars->{BIOS});
        }
        foreach my $attribute (qw(KERNEL INITRD APPEND)) {
            if ($vars->{$attribute}) {
                push(@params, "-" . lc($attribute), $vars->{$attribute});
            }
        }
        if ($vars->{MULTINET}) {
            if ($vars->{NICTYPE} eq "tap") {
                die "MULTINET is not supported with NICTYPE==tap\n";
            }
            push(@params, ('-net', "nic,vlan=1,model=$vars->{NICMODEL},macaddr=52:54:00:12:34:57", '-net', 'none,vlan=1'));
        }
        if ($vars->{OFW}) {
            no warnings 'qw';
            push(@params, qw(-device nec-usb-xhci -device usb-tablet));
        }
        elsif ($vars->{ARCH} eq 'aarch64') {
            push(@params, qw(-device nec-usb-xhci -device usb-tablet));
        }
        else {
            push(@params, qw(-device usb-ehci -device usb-tablet));
        }
        if ($use_usb_kbd) {
            push(@params, qw(-device usb-kbd));
        }
        if ($vars->{QEMUTHREADS}) {
            push(@params, "-smp", $vars->{QEMUCPUS} . ",threads=" . $vars->{QEMUTHREADS});
        }
        else {
            push(@params, "-smp", $vars->{QEMUCPUS});
        }
        if ($vars->{QEMU_NUMA}) {
            for my $i (0 .. ($vars->{QEMUCPUS} - 1)) {
                push(@params, '-numa', "node,nodeid=$i");
            }
        }

        push(@params, "-enable-kvm") unless $vars->{QEMU_NO_KVM};
        push(@params, "-no-shutdown");

        open(my $cmdfd, '>', 'runqemu');
        print $cmdfd "#!/bin/bash\n";
        my @args;
        for my $arg (@params) {
            $arg =~ s,\\,\\\\,g;
            $arg =~ s,\$,\\\$,g;
            $arg =~ s,\",\\\",g;
            $arg =~ s,\`,\\\`,;
            push(@args, "\"$arg\"");
        }
        printf $cmdfd "%s \\\n  %s \\\n  \"\$@\"\n", $qemubin, join(" \\\n  ", @args);
        close $cmdfd;
        chmod 0755, 'runqemu';

        if ($vars->{VNC}) {
            if ($vars->{VNC} !~ /:/) {
                $vars->{VNC} = ":$vars->{VNC}";
            }
            push(@params, "-vnc", "$vars->{VNC},share=force-shared");
            push(@params, "-k", $vars->{VNCKB}) if ($vars->{VNCKB});
        }

        if ($vars->{VIRTIO_CONSOLE}) {
            my $id = 'virtio_console';
            push(@params, '-device',  'virtio-serial');
            push(@params, '-chardev', "socket,path=$id,server,nowait,id=$id,logfile=$id.log");
            push(@params, '-device',  "virtconsole,chardev=$id,name=org.openqa.console.$id");
        }

        push @params, '-qmp', "unix:qmp_socket,server,nowait", "-monitor", "unix:hmp_socket,server,nowait", "-S";
        my $port = $vars->{QEMUPORT};
        push @params, "-monitor", "telnet:127.0.0.1:$port,server,nowait";

        unshift(@params, $qemubin);

        if ($vars->{AUTO_INST}) {
            push(@params, "-drive", "file=$basedir/autoinst.img,index=0,if=floppy");
        }
        bmwqemu::diag(`$qemubin -version`);
        bmwqemu::diag("starting: " . join(" ", @params));

        # don't try to talk to the host's PA
        $ENV{QEMU_AUDIO_DRV} = "none";

        # redirect qemu's output to the parent pipe
        open(STDOUT, ">&", $writer);
        open(STDERR, ">&", $writer);
        close($reader);
        exec(@params);
        die "failed to exec qemu";
    }
    else {
        $self->{pid} = $pid;
    }
    close $writer;
    $self->{qemupipe} = $reader;
    open(my $pidf, ">", $self->{pidfilename});
    print $pidf $self->{pid}, "\n";
    close $pidf;

    my $vnc = $testapi::distri->add_console(
        'sut',
        'vnc-base',
        {
            hostname => 'localhost',
            port     => 5900 + $bmwqemu::vars{VNC}});

    $vnc->backend($self);
    $self->select_console({testapi_console => 'sut'});

    $self->{hmpsocket} = IO::Socket::UNIX->new(
        Type     => IO::Socket::UNIX::SOCK_STREAM,
        Peer     => "hmp_socket",
        Blocking => 0
    ) or die "can't open hmp";

    $self->{hmpsocket}->autoflush(1);
    binmode $self->{hmpsocket};
    my $flags = fcntl($self->{hmpsocket}, Fcntl::F_GETFL, 0) or die "can't getfl(): $!\n";
    $flags = fcntl($self->{hmpsocket}, Fcntl::F_SETFL, $flags | Fcntl::O_NONBLOCK) or die "can't setfl(): $!\n";

    $self->{qmpsocket} = IO::Socket::UNIX->new(
        Type     => IO::Socket::UNIX::SOCK_STREAM,
        Peer     => "qmp_socket",
        Blocking => 0
    ) or die "can't open qmp: $!";

    $self->{qmpsocket}->autoflush(1);
    binmode $self->{qmpsocket};
    $flags = fcntl($self->{qmpsocket}, Fcntl::F_GETFL, 0) or die "can't getfl(): $!\n";
    $flags = fcntl($self->{qmpsocket}, Fcntl::F_SETFL, $flags | Fcntl::O_NONBLOCK) or die "can't setfl(): $!\n";

    diag sprintf("hmpsocket %d, qmpsocket %d", fileno($self->{hmpsocket}), fileno($self->{qmpsocket}));

    fcntl($self->{qemupipe}, Fcntl::F_SETFL, Fcntl::O_NONBLOCK) or die "can't setfl(): $!\n";

    # retrieve welcome
    my $line = $self->_read_hmp;
    print "WELCOME $line\n";

    my $init = myjsonrpc::read_json($self->{qmpsocket});
    my $hash = $self->handle_qmp_command({execute => 'qmp_capabilities'});
    if (0) {
        $hash = $self->handle_qmp_command({execute => 'query-commands'});
        die "no commands!" unless ($hash);
        print "COMMANDS " . JSON::to_json($hash, {pretty => 1}) . "\n";
    }

    my $cnt = bmwqemu::fileContent("$ENV{HOME}/.autotestvncpw");
    if ($cnt) {
        $self->send($cnt);
    }

    if ($vars->{NICTYPE} eq "tap") {
        eval {
            # do not die on unconfigured service
            local $SIG{__DIE__};

            my $bus     = Net::DBus->system;
            my $service = $bus->get_service("org.opensuse.os_autoinst.switch");
            my $object  = $service->get_object("/switch", "org.opensuse.os_autoinst.switch");

            for (my $i = 0; $i < $num_networks; $i++) {
                $object->set_vlan($tapdev[$i], $nicvlan[$i]);
            }
        };
        if ($@) {
            print "$@\n";
            print "WARNING: Can't switch NICVLAN number, independent tests may be running on the same network.\n\n";
        }
    }

    print "Start CPU";
    $self->handle_qmp_command({execute => 'cont'});

    $self->{select}->add($self->{qemupipe});
}

sub _read_hmp {
    my ($self) = @_;

    my $rsp = '';
    my $s   = IO::Select->new();
    $s->add($self->{hmpsocket});

    # the timeout is actually pretty insane, but savevm is quite
    # heavy on IO and after this timeout we die anyway, so if we
    # waited one minute or 5 doesn't really matter
    while (my @ready = $s->can_read(300)) {
        my $buffer;
        my $bytes = sysread($self->{hmpsocket}, $buffer, 1000);
        last unless ($bytes);
        $rsp .= $buffer;
        my @rsp2 = unpack("C*", $rsp);
        my $line = '';
        for my $c (@rsp2) {
            if ($c == 13) {

                # skip
            }
            elsif ($c == 10) {
                $line .= "\n";
            }
            elsif ($c == 27) {
                $line .= "^";
            }
            elsif ($c < 32) {
                $line .= "C$c ";
            }
            else {
                $line .= chr($c);
            }
        }

        # remove nop
        $line =~ s/\^\[K//g;

        # remove "cursor back"
        while ($line =~ m/.\^\[D/) {
            $line =~ s/.\^\[D//;
        }
        if ($line =~ m/\n\(qemu\) *$/) {
            $line =~ s/\n\(qemu\) *$//;
            return $line;
        }
    }

    backend::baseclass::write_crash_file;
    die "ERROR: timeout reading hmp socket\n";
}

# runs in the thread to bounce QMP
sub handle_qmp_command {

    my ($self, $cmd) = @_;

    my $line = JSON::to_json($cmd);
    my $wb = syswrite($self->{qmpsocket}, "$line\n");
    die "syswrite failed $!" unless ($wb == length($line) + 1);

    my $hash;
    while (!$hash) {
        $hash = myjsonrpc::read_json($self->{qmpsocket});
        if ($hash->{event}) {
            bmwqemu::diag "EVENT " . JSON::to_json($hash);
            # ignore
            $hash = undef;
        }
    }

    return $hash;
}

sub read_qemupipe {
    my ($self) = @_;
    my $buffer;
    my $bytes = sysread($self->{qemupipe}, $buffer, 1000);
    chomp $buffer;
    for my $line (split(/\n/, $buffer)) {
        bmwqemu::diag "QEMU: $line";
    }
    return $bytes;
}

sub close_pipes {
    my ($self) = @_;

    $self->do_stop_vm();

    if ($self->{qemupipe}) {
        # one last word?
        fcntl($self->{qemupipe}, Fcntl::F_SETFL, Fcntl::O_NONBLOCK);
        $self->read_qemupipe();
        close($self->{qemupipe});
        $self->{qemupipe} = undef;
    }

    if ($self->{qmpsocket}) {
        close($self->{qmpsocket}) || die "close $!\n";
        $self->{qmpsocket} = undef;
    }
    if ($self->{hmpsocket}) {
        close($self->{hmpsocket}) || die "close $!\n";
        $self->{hmpsocket} = undef;
    }
    $self->SUPER::close_pipes();
}

sub _send_hmp {
    my ($self, $hmp) = @_;

    my $wb = syswrite($self->{hmpsocket}, "$hmp\n");

    die "syswrite failed $!" unless ($wb == length($hmp) + 1);

    return $self->_read_hmp;
}

sub is_shutdown {
    my ($self) = @_;
    my $ret = $self->handle_qmp_command({execute => 'query-status'});
    return ($ret->{return}->{status} || '') eq 'shutdown';
}

sub handle_hmp_command {
    my ($self, $hmp) = @_;

    my $line = $self->_send_hmp($hmp);
    $self->{rsppipe}->print(JSON::to_json({rsp => $line}));
}

# this is called for all sockets ready to read from. return 1 if socket
# detected and -1 if there was an error
sub check_socket {
    my ($self, $fh, $write) = @_;

    if ($self->{qemupipe} && $fh == $self->{qemupipe}) {
        if (!$write) {
            $self->close_pipes() unless $self->read_qemupipe();
        }
        return 1;
    }
    return $self->SUPER::check_socket($fh);
}

sub wait_idle {
    my ($self, $args) = @_;
    my $timeout       = $args->{timeout};
    my $idlethreshold = $args->{threshold};
    my $prev;
    my $timesidle       = 0;
    my $timesidleneeded = 1;

    for my $n (1 .. $timeout) {
        my ($stat, $systemstat) = @{$self->cpu_stat()};
        $self->run_capture_loop(undef, 1, .19);
        next unless $stat;
        $stat += $systemstat;
        if ($prev) {
            my $diff = $stat - $prev;
            bmwqemu::diag("wait_idle $timesidle d=$diff");
            if ($diff < $idlethreshold) {
                if (++$timesidle > $timesidleneeded) {    # idle for $x sec
                                                          #if($diff<2000000) # idle for one sec
                    return {idle => 1};
                }
            }
            else { $timesidle = 0 }
        }
        $prev = $stat;
    }
    return;
}

sub freeze_vm {
    my ($self) = @_;
    # qemu specific - all other backends will crash
    return $self->handle_qmp_command({execute => 'stop'});
}

sub cont_vm {
    my ($self) = @_;
    return $self->handle_qmp_command({execute => 'cont'});
}

1;

# vim: set sw=4 et:
