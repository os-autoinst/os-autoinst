# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2017 SUSE LLC
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
use File::Which;
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
use Try::Tiny;
use osutils qw(find_bin gen_params qv runcmd);
use List::Util 'max';
use Data::Dumper;

# The maximum value of the system's native signed integer. Which will probably
# be 2^64 - 1.
use constant LONG_MAX => (~0 >> 1);

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new;
    # By compressing we are making the images self contained, i.e. they are
    # portable by not requiring backing files referencing the openQA instance.
    # Compressing takes longer but the transfer takes shorter amount of time.
    $bmwqemu::vars{QEMU_COMPRESS_QCOW2} //= 1;

    $self->{pid}         = undef;
    $self->{pidfilename} = 'qemu.pid';

    return $self;
}

# baseclass virt method overwrite

sub raw_alive {
    my ($self) = @_;
    return 0 unless $self->{pid};
    return kill(0, $self->{pid});
}

sub _wrap_hmc {
    my $cmdline = shift;
    return {
        execute   => 'human-monitor-command',
        arguments => {'command-line' => $cmdline}};
}
sub start_audiocapture {
    my ($self, $args) = @_;

    $self->handle_qmp_command(_wrap_hmc("wavcapture $args->{filename} 44100 16 1"));
}

sub stop_audiocapture {
    my ($self, $args) = @_;

    $self->handle_qmp_command(_wrap_hmc("stopcapture 0"));
}

sub power {

    # parameters: acpi, reset, (on), off
    my ($self, $args) = @_;
    my $action = $args->{action};
    if ($action eq 'acpi') {
        $self->handle_qmp_command({excecute => 'system_powerdown'});
    }
    elsif ($action eq 'reset') {
        $self->handle_qmp_command({execute => 'system_reset'});
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

    $self->_kill_children_processes;
}

sub _dbus_call {
    my $self = shift;
    my $fn   = shift;
    my @args = @_;

    my ($rt, $message);
    eval {
        # do not die on unconfigured service
        local $SIG{__DIE__};

        $self->{dbus}         ||= Net::DBus->system;
        $self->{dbus_service} ||= $self->{dbus}->get_service("org.opensuse.os_autoinst.switch");
        $self->{dbus_object}  ||= $self->{dbus_service}->get_object("/switch", "org.opensuse.os_autoinst.switch");

        ($rt, $message) = $self->{dbus_object}->$fn(@args);
        chomp $message;
        if ($rt != 0) {
            bmwqemu::diag "Failed to run dbus command '$fn' with arguments '@args'" . " : " . $message;
        }
    };
    print "$@\n" if ($@);

    return ($rt, $message, ($@) x !!($@));
}

sub do_stop_vm {
    my $self = shift;

    return unless $self->{pid};
    kill_qemu($self);
    $self->{pid} = undef;
    unlink($self->{pidfilename});

    # Free allocated vlans - if any -
    return unless $self->{allocated_networks} && $self->{allocated_tap_devices} && $self->{allocated_vlan_tags};

    for (my $i = 0; $i < $self->{allocated_networks}; $i++) {
        $self->_dbus_call('unset_vlan', (@{$self->{allocated_tap_devices}})[$i], (@{$self->{allocated_vlan_tags}})[$i]);
    }
}

sub can_handle {
    my ($self, $args) = @_;
    my $vars = \%bmwqemu::vars;

    if ($args->{function} eq 'snapshots') {
        # raw HDD format does not support snapshots
        return if $vars->{HDDFORMAT} eq 'raw';

        # virtio-gpu does not support saving yet
        return if ($vars->{QEMUVGA} || '') eq 'virtio';

        # XXX: Temporary (hopefully) workaround for nvme, since snapshots fails.
        # See also https://github.com/os-autoinst/os-autoinst/pull/781
        return if $vars->{HDDMODEL} eq 'nvme';

        return if $vars->{QEMU_DISABLE_SNAPSHOTS};

        for my $i (1 .. $vars->{NUMDISKS}) {
            return if (defined $vars->{"HDDMODEL_$i"} && $vars->{"HDDMODEL_$i"} eq 'nvme');
        }

        return {ret => 1};
    }
    return;
}

sub open_file_and_send_fd_to_qemu {
    my ($self, $path, $fdname) = @_;
    my $rsp;

    my $fd = POSIX::open($path, &POSIX::O_CREAT | &POSIX::O_RDWR);
    die "Failed to open $path: $!" unless (defined $fd);

    $rsp = $self->handle_qmp_command(
        {execute => 'getfd', arguments => {fdname => $fdname}},
        send_fd => $fd,
        fatal   => 1
    );
    POSIX::close($fd);
}

sub set_migrate_capability {
    my ($self, $name, $state) = @_;

    $self->handle_qmp_command(
        {
            execute   => 'migrate-set-capabilities',
            arguments => {
                capabilities => [
                    {
                        capability => $name,
                        state      => $state ? JSON::true : JSON::false,
                    }]}
        },
        fatal => 1
    );
}

sub save_memory_dump {
    my ($self, $args) = @_;
    my $fdname          = 'dumpfd';
    my $vars            = \%bmwqemu::vars;
    my $compress_method = $vars->{QEMU_COMPRESS_METHOD} || 'xz';
    my $compress_level  = $vars->{QEMU_COMPRESS_LEVEL} || 6;
    my $filename        = $args->{filename} . '-vm-memory-dump';

    my $rsp = $self->handle_qmp_command({execute => 'query-status'}, fatal => 1);
    bmwqemu::diag("Migrating the machine (Current VM state is $rsp->{return}->{status}).");
    my $was_running = $rsp->{return}->{status} eq 'running';

    # Internally compressed dumps can't be opened by crash. They need to be
    # fed back into QEMU as an incoming migration.
    $self->set_migrate_capability('compress', 1) if $compress_method eq 'internal';
    $self->set_migrate_capability('events', 1);

    $self->handle_qmp_command(
        {
            execute   => 'migrate-set-parameters',
            arguments => {
                # This is ignored if the compress capability is not set
                'compress-level' => $compress_level,
                # Ensure slow dump times are not due to a transfer rate cap
                'max-bandwidth' => $vars->{QEMU_MAX_BANDWIDTH} || LONG_MAX
            }
        },
        fatal => 1
    );

    mkpath("ulogs");
    $self->open_file_and_send_fd_to_qemu("ulogs/$filename", $fdname);

    # QEMU will freeze the VM when the RAM migration reaches a low water
    # mark. However it is easier for QEMU if the VM is already frozen.
    $self->freeze_vm();
    # migrate consumes the file descriptor, so we do not need to call closefd
    $self->handle_qmp_command(
        {
            execute   => 'migrate',
            arguments => {uri => "fd:$fdname"}
        },
        fatal => 1
    );

    my $migration_starttime = gettimeofday;
    my $execution_time      = gettimeofday;
    # We need to wait for qemu, since it will not honor timeouts
    my $max_execution_time = 240;

    do {
        #We want to wait a decent amount of time, a file of 1GB will be
        # migrated in about 40secs with an ssd drive. and no heavy load.
        sleep 0.5;

        $execution_time = gettimeofday - $migration_starttime;
        $rsp = $self->handle_qmp_command({execute => "query-migrate"});

        if ($rsp->{return}->{status} eq "failed") {
            die "Memory dump failed";
        }

        diag "Migrating total bytes:     \t" . $rsp->{return}->{ram}->{total};
        diag "Migrating remaining bytes:   \t" . $rsp->{return}->{ram}->{remaining};

        # 240 seconds should be ok for 4GB
        if ($execution_time > $max_execution_time) {
            # migrate_cancel returns an empty hash, so there is no need to check.
            $rsp = $self->handle_qmp_command({execute => "migrate_cancel"});
            die "Memory dump failed, it has been running for more than $max_execution_time";
        }

    } until ($rsp->{return}->{status} eq "completed");

    diag "Memory dump completed.";

    $self->cont_vm() if $was_running;

    if ($compress_method eq 'xz') {
        if (defined which('xz')) {
            system(('xz', '-T', '2', "-v$compress_level", "ulogs/$filename"));
        }
        else {
            bmwqemu::fctwarn('xz not found; falling back to bzip2');
            $compress_method = 'bzip2';
        }
    }

    if ($compress_method eq 'bzip2') {
        system(('bzip2', "-v$compress_level", "ulogs/$filename"));
    }

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
    my $rsp    = $self->handle_qmp_command(_wrap_hmc("savevm $vmname"));
    if (!$rsp || $rsp->{return} ne '') {
        die "Could not save snapshot \'$vmname\' " . Dumper($rsp);
    }
    return;
}

sub load_snapshot {
    my ($self, $args) = @_;
    my $vmname = $args->{name};
    my $rsp    = $self->handle_qmp_command(_wrap_hmc("loadvm $vmname"));
    if (!$rsp || $rsp->{return} ne '') {
        die "Could not load snapshot \'$vmname\': " . Dumper($rsp);
    }
    return $rsp;
}

sub do_extract_assets {
    my ($self, $args) = @_;
    my $hdd_num = $args->{hdd_num};
    my $name    = $args->{name};
    my $img_dir = $args->{dir};
    my $format  = $args->{format};
    if (!$format || $format !~ /^(raw|qcow2)$/) {
        die "do_extract_assets: only raw and qcow2 formats supported $name $format";
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
        die "do_extract_assets: hdd $hdd_num does not exist";
    }
}


# baseclass virt method overwrite end

sub start_qemu {

    my $self = shift;
    my $vars = \%bmwqemu::vars;

    my $basedir = "raid";
    my $qemubin = $ENV{QEMU};

    my $qemuimg = find_bin('/usr/bin/', qw(kvm-img qemu-img));

    unless ($qemubin) {
        if ($vars->{QEMU}) {
            $qemubin = find_bin('/usr/bin/', 'qemu-system-' . $vars->{QEMU});
        }
        else {
            (my $class = $vars->{WORKER_CLASS} || '') =~ s/qemu_/qemu-system\-/g;
            my @execs = qw(kvm qemu-kvm qemu qemu-system-x86_64 qemu-system-ppc64);
            my %allowed = map { $_ => 1 } @execs;
            for (split(/\s*,\s*/, $class)) {
                if ($allowed{$_}) {
                    $qemubin = find_bin('/usr/bin/', $_);
                    last;
                }
            }
            $qemubin = find_bin('/usr/bin/', @execs) unless $qemubin;
        }
    }

    die "no kvm-img/qemu-img found\n" unless $qemuimg;
    die "no Qemu/KVM found\n"         unless $qemubin;
    die "MULTINET is not supported with NICTYPE==tap\n" if ($vars->{MULTINET} && $vars->{NICTYPE} eq "tap");

    $vars->{BIOS} //= $vars->{UEFI_BIOS} if ($vars->{UEFI});    # XXX: compat with old deployment
    $vars->{UEFI} = 1 if ($vars->{UEFI_PFLASH});

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

    foreach my $attribute (qw(BIOS KERNEL INITRD)) {
        if ($vars->{$attribute} && $vars->{$attribute} !~ /^\//) {
            # Non-absolute paths are assumed relative to /usr/share/qemu
            $vars->{$attribute} = '/usr/share/qemu/' . $vars->{$attribute};
        }
        if ($vars->{$attribute} && !-e $vars->{$attribute}) {
            die "'$vars->{$attribute}' missing, check $attribute\n";
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
    if ($vars->{MULTIPATH}) {
        $vars->{HDDMODEL}  ||= "scsi-hd";
        $vars->{HDDFORMAT} ||= "raw";
        $vars->{PATHCNT}   ||= 2;
    }
    $vars->{NUMDISKS} ||= defined($vars->{RAIDLEVEL}) ? 4 : 1;
    $vars->{HDDSIZEGB} ||= 10;
    $vars->{CDMODEL}   ||= "scsi-cd";
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
    my $arch_supports_boot_order = $vars->{UEFI} ? 0 : 1;    # UEFI/OVMF supports ",bootindex=N", but not "-boot order=X"
    my $use_usb_kbd;
    my @vgaoptions;

    if ($vars->{ARCH} eq 'aarch64' || $vars->{ARCH} eq 'arm') {
        my $video_device = ($vars->{QEMU_OVERRIDE_VIDEO_DEVICE_AARCH64}) ? 'VGA' : 'virtio-gpu-pci';
        gen_params @vgaoptions, 'device', $video_device;
        $arch_supports_boot_order = 0;
        $use_usb_kbd              = 1;
    }
    elsif ($vars->{OFW}) {
        $vars->{QEMUVGA} ||= "std";
        $vars->{QEMUMACHINE} = "usb=off";
        gen_params @vgaoptions, 'g', '1024x768';
        $use_usb_kbd = 1;
    }
    else {
        $vars->{QEMUVGA} ||= "cirrus";
    }

    gen_params @vgaoptions, 'vga', $vars->{QEMUVGA} if $vars->{QEMUVGA};

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
    $num_networks = max($num_networks, scalar @nicmac, scalar @nicvlan, scalar @tapdev);

    if ($vars->{OFFLINE_SUT}) {
        $num_networks = 0;
    }

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

            my @cmd = ('slirpvde', '--dhcp', '-s', "$vars->{VDE_SOCKETDIR}/vde.ctl", '--port', $port + 1);

            my $child_pid = $self->_child_process(
                sub {
                    $SIG{__DIE__} = undef;    # overwrite the default - just exit
                    exec(@cmd);
                    die "failed to exec slirpvde";
                });
            diag join(' ', @cmd) . " started with pid $child_pid";

            runcmd('vdecmd', '-s', $mgmtsocket, 'port/setvlan', $port + 1, $vlan) if $vlan;
        }
    }

    bmwqemu::save_vars();                     # update variables

    mkpath($basedir);
    # do not use runcmd or autodie here, it can fail on tmpfs, xfs, ...
    CORE::system('/usr/bin/chattr', '-f', '+C', $basedir);

    my $keephdds = $vars->{KEEPHDDS} || $vars->{SKIPTO};

    # fresh HDDs
    for my $i (1 .. $vars->{NUMDISKS}) {
        # skip HDD refresh when HDD exists and KEEPHDDS or SKIPTO is set
        next if ($keephdds && (-e "$basedir/$i.lvm" || -e "$basedir/$i"));
        no autodie 'unlink';
        unlink("$basedir/l$i") if -e "$basedir/l$i";
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
        unlink("$basedir/autoinst.img") if -e "$basedir/autoinst.img";
        runcmd("/sbin/mkfs.vfat", "-C", "$basedir/autoinst.img", "1440");
        runcmd("/usr/bin/mcopy", "-i", "$basedir/autoinst.img", $vars->{AUTO_INST}, "::/");
    }

    for my $i (1 .. 4) {    # create missing symlinks
        next if -e "$basedir/l$i";
        next unless -e "$basedir/$i";
        symlink($i, "$basedir/l$i") or die "$!\n";
    }

    my @params = ("-serial", "file:serial0", "-soundhw", "ac97");
    {
        push(@params, @vgaoptions);

        # Avoid qemu's error message about floppy controller when using arm/aarch64:
        unless ($vars->{ARCH} eq 'aarch64' || $vars->{ARCH} eq 'arm' || $vars->{QEMU_NO_FDC_SET}) {
            gen_params @params, "global", "isa-fdc.driveA=";
        }
        gen_params @params, 'm',       $vars->{QEMURAM}     if $vars->{QEMURAM};
        gen_params @params, 'machine', $vars->{QEMUMACHINE} if $vars->{QEMUMACHINE};
        gen_params @params, 'cpu',     $vars->{QEMUCPU}     if $vars->{QEMUCPU};
        gen_params @params, 'device',  'virtio-rng-pci'     if $vars->{QEMU_VIRTIO_RNG};
        gen_params @params, 'net',     'none'               if $vars->{OFFLINE_SUT};

        for (my $i = 0; $i < $num_networks; $i++) {
            if ($vars->{NICTYPE} eq "user") {
                my $nictype_user_options = $vars->{NICTYPE_USER_OPTIONS} ? ',' . $vars->{NICTYPE_USER_OPTIONS} : '';
                gen_params @params, 'netdev', [qv "user id=qanet$i$nictype_user_options"];
            }
            elsif ($vars->{NICTYPE} eq "tap") {
                gen_params @params, 'netdev', [qv "tap id=qanet$i ifname=$tapdev[$i] script=$tapscript[$i] downscript=$tapdownscript[$i]"];
            }
            elsif ($vars->{NICTYPE} eq "vde") {
                gen_params @params, 'netdev', [qv "vde id=qanet0 sock=$vars->{VDE_SOCKETDIR}/vde.ctl port=$vars->{VDE_PORT}"];
            }
            else {
                die "unknown NICTYPE $vars->{NICTYPE}\n";
            }
            gen_params @params, 'device', [qv "$vars->{NICMODEL} netdev=qanet$i mac=$nicmac[$i]"];
        }

        gen_params @params, 'smbios', $vars->{QEMU_SMBIOS} if $vars->{QEMU_SMBIOS};

        if ($vars->{LAPTOP}) {
            my $laptop_path = "$bmwqemu::scriptdir/dmidata/$vars->{LAPTOP}";
            for my $f (glob "$laptop_path/*.bin") {
                gen_params @params, 'smbios', "file=$f";
            }
        }
        if ($vars->{NBF}) {
            die "Need variable WORKER_HOSTNAME\n" unless $vars->{WORKER_HOSTNAME};
            gen_params @params, 'kernel', '/usr/share/qemu/ipxe.lkrn';
            gen_params @params, 'append', "dhcp && sanhook iscsi:$vars->{WORKER_HOSTNAME}::3260:1:$vars->{NBF}", no_quotes => 1;
        }
        gen_params @params, 'device', [qv "$vars->{SCSICONTROLLER} id=scsi0"] if $vars->{SCSICONTROLLER};
        gen_params @params, 'device', [qv "$vars->{SCSICONTROLLER} id=scsi1"] if ($vars->{SCSICONTROLLER} && $vars->{MULTIPATH});
        gen_params @params, 'device', [qv "$vars->{ATACONTROLLER} id=ahci0"]  if $vars->{ATACONTROLLER};

        for my $i (1 .. $vars->{NUMDISKS}) {
            if ($vars->{MULTIPATH}) {
                for my $c (1 .. $vars->{PATHCNT}) {
                    # pathname is a .. d
                    my $bus = sprintf "scsi%d.0", ($c - 1) % 2;    # alternate between scsi0 and scsi1
                    my $id = sprintf 'hd%d%c', $i, 96 + $c;
                    # when booting from disk on UEFI, first connected disk gets ",bootindex=0"
                    my $bootindex = ($i == 1 && $c == 1 && $vars->{UEFI} && $bootfrom eq "disk") ? "bootindex=0" : "";
                    gen_params @params, 'device', [qv "$vars->{HDDMODEL} drive=$id bus=$bus $bootindex"];
                    gen_params @params, 'drive',  [qv "file=$basedir/l$i cache=none if=none id=$id serial=mpath$i format=$vars->{HDDFORMAT} discard=on"];
                }
            }
            else {
                my $diskmodel;
                if (defined $vars->{"HDDMODEL_$i"}) {
                    $diskmodel = $vars->{"HDDMODEL_$i"};
                }
                else {
                    $diskmodel = $vars->{HDDMODEL};
                }
                # when booting from disk on UEFI, first connected disk gets ",bootindex=0"
                my $bootindex = ($i == 1 && $vars->{UEFI} && $bootfrom eq "disk") ? "bootindex=0" : "";
                my $serial = "serial=$i";
                gen_params @params, 'device', [qv "$diskmodel drive=hd$i $bootindex $serial"];
                gen_params @params, 'drive',  [qv "file=$basedir/l$i cache=unsafe if=none id=hd$i format=$vars->{HDDFORMAT} discard=on"];
            }
        }

        my $cdbus = $vars->{CDMODEL} eq 'scsi-cd' ? 'bus=scsi0.0' : '';
        if ($iso) {
            if ($vars->{USBBOOT}) {
                gen_params @params, 'drive',  [qv "if=none id=usbstick file=$iso snapshot=on"];
                gen_params @params, 'device', [qv "usb-ehci id=ehci"];
                # when USBBOOT is defined on UEFI, it gets ",bootindex=0"
                my $bootindex = ($vars->{UEFI} && $bootfrom ne "disk") ? "bootindex=0" : "";
                gen_params @params, "device", [qv "usb-storage bus=ehci.0 drive=usbstick id=devusb $bootindex"];
            }
            else {
                gen_params @params, "drive", [qv "media=cdrom if=none id=cd0 format=raw file=$iso"];
                # XXX: workaround for OVMF wanting to write NVvars into first FAT partition
                # we need to replace -bios with proper pflash drive specification
                $params[-1] .= ',snapshot=on' if $vars->{UEFI};
                # when booting from cdrom on UEFI, first connected CD gets ",bootindex=0"
                my $bootindex = ($vars->{UEFI} && $bootfrom eq "cdrom") ? "bootindex=0" : "";
                gen_params @params, "device", [qv "$vars->{CDMODEL} drive=cd0 $cdbus $bootindex"];
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
                $bootindex = "bootindex=0";
            }
            gen_params @params, "drive",  [qv "media=cdrom if=none id=cd$i format=raw file=$addoniso"];
            gen_params @params, "device", [qv "$vars->{CDMODEL} drive=cd$i $cdbus $bootindex"];
        }

        if ($arch_supports_boot_order) {
            if ($vars->{PXEBOOT}) {
                gen_params @params, "boot", "n";
            }
            elsif ($vars->{BOOTFROM}) {
                gen_params @params, "boot", [qv "order=$vars->{BOOTFROM} menu=on splash-time=5000"];
            }
            else {
                gen_params @params, "boot", [qw(once=d menu=on splash-time=5000)];
            }
        }

        if ($vars->{UEFI_PFLASH}) {
            # Convert the firmware file into qcow2 format or savevm would fail
            runcmd('qemu-img', 'convert', '-O', 'qcow2', $vars->{BIOS}, 'ovmf.bin');
            gen_params @params, "drive", [qw(if=pflash format=qcow2 file=ovmf.bin)];
        }
        elsif ($vars->{BIOS}) {
            gen_params @params, "bios", $vars->{BIOS};
        }

        foreach my $attribute (qw(KERNEL INITRD APPEND)) {
            gen_params @params, lc($attribute), $vars->{$attribute} if $vars->{$attribute};
        }

        if ($vars->{MULTINET}) {
            gen_params @params, 'net', [qv "nic vlan=1 model=$vars->{NICMODEL} macaddr=52:54:00:12:34:57"];
            gen_params @params, 'net', [qw(none vlan=1)];
        }

        unless ($vars->{QEMU_NO_TABLET}) {
            if ($vars->{OFW} || $vars->{ARCH} eq 'aarch64') {
                gen_params @params, 'device', 'nec-usb-xhci';
            }
            else {
                gen_params @params, 'device', 'usb-ehci';
            }
            gen_params @params, 'device', 'usb-tablet';
        }

        gen_params @params, 'device', 'usb-kbd' if $use_usb_kbd;

        if ($vars->{QEMUTHREADS}) {
            gen_params @params, 'smp', [qv "$vars->{QEMUCPUS} threads=$vars->{QEMUTHREADS}"];
        }
        else {
            gen_params @params, 'smp', $vars->{QEMUCPUS};
        }
        if ($vars->{QEMU_NUMA}) {
            for my $i (0 .. ($vars->{QEMUCPUS} - 1)) {
                gen_params @params, 'numa', [qv "node nodeid=$i"];
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
            my $vncport = $vars->{VNC} !~ /:/ ? ":$vars->{VNC}" : $vars->{VNC};
            gen_params @params, 'vnc', [qv "$vncport share=force-shared"];
            gen_params @params, 'k', $vars->{VNCKB} if $vars->{VNCKB};
        }

        if ($vars->{VIRTIO_CONSOLE}) {
            my $id = 'virtio_console';
            gen_params @params, 'device', 'virtio-serial';
            gen_params @params, 'chardev', [qv "socket path=$id server nowait id=$id logfile=$id.log"];
            gen_params @params, 'device',  [qv "virtconsole chardev=$id name=org.openqa.console.$id"];
        }

        gen_params @params, 'qmp',     [qw(unix:qmp_socket server nowait)];
        gen_params @params, 'monitor', [qw(unix:hmp_socket server nowait)];
        push(@params, "-S");

        gen_params @params, 'monitor', [qv "telnet:127.0.0.1:$vars->{QEMUPORT} server nowait"];
        gen_params @params, 'drive', [qv "file=$basedir/autoinst.img index=0 if=floppy"] if $vars->{AUTO_INST};
        unshift(@params, $qemubin);
    }

    pipe(my $reader, my $writer);
    my $pid = fork();
    die "fork failed" unless defined($pid);
    if ($pid == 0) {
        $SIG{__DIE__} = undef;    # overwrite the default - just exit

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
            hostname        => 'localhost',
            connect_timeout => 3,
            port            => 5900 + $bmwqemu::vars{VNC}});

    $vnc->backend($self);
    try {
        local $SIG{__DIE__} = undef;
        $self->select_console({testapi_console => 'sut'});
    }
    catch {
        if (!raw_alive) {
            bmwqemu::diag "qemu didn't start";
            $self->read_qemupipe;
            exit(1);
        }
    };

    $self->{qmpsocket} = IO::Socket::UNIX->new(
        Type     => IO::Socket::UNIX::SOCK_STREAM,
        Peer     => "qmp_socket",
        Blocking => 0
    ) or die "can't open qmp: $!";

    $self->{qmpsocket}->autoflush(1);
    binmode $self->{qmpsocket};
    my $flags = fcntl($self->{qmpsocket}, Fcntl::F_GETFL, 0) or die "can't getfl(): $!\n";
    $flags = fcntl($self->{qmpsocket}, Fcntl::F_SETFL, $flags | Fcntl::O_NONBLOCK) or die "can't setfl(): $!\n";

    diag sprintf("qmpsocket %d", fileno($self->{qmpsocket}));

    fcntl($self->{qemupipe}, Fcntl::F_SETFL, Fcntl::O_NONBLOCK) or die "can't setfl(): $!\n";

    my $init = myjsonrpc::read_json($self->{qmpsocket});
    my $hash = $self->handle_qmp_command({execute => 'qmp_capabilities'});

    my $cnt = bmwqemu::fileContent("$ENV{HOME}/.autotestvncpw");
    if ($cnt) {
        $self->send($cnt);
    }

    if ($vars->{NICTYPE} eq "tap") {
        $self->{allocated_networks}    = $num_networks;
        $self->{allocated_tap_devices} = \@tapdev;
        $self->{allocated_vlan_tags}   = \@nicvlan;
        for (my $i = 0; $i < $num_networks; $i++) {
            $self->_dbus_call('set_vlan', $tapdev[$i], $nicvlan[$i]);
        }
        if (exists $vars->{OVS_DEBUG} && $vars->{OVS_DEBUG} == 1) {
            my (undef, $output) = $self->_dbus_call('show');
            bmwqemu::diag "Open vSwitch networking status:";
            bmwqemu::diag $output;
        }
    }

    if ($bmwqemu::vars{DELAYED_START}) {
        print "DELAYED_START set, not starting CPU, waiting for resume_vm() call\n";
    }
    else {
        print "Start CPU\n";
        $self->handle_qmp_command({execute => 'cont'});
    }

    $self->{select}->add($self->{qemupipe});
}

=head2 handle_qmp_command

Send a QMP command and wait for the result

Pass fatal => 1 to die on failure.
Pass send_fd => $fd to send $fd to QEMU using SCM rights. Probably only useful
with the getfd command.

=cut
sub handle_qmp_command {
    my ($self, $cmd) = @_[0, 1];
    my %optargs = @_[2 .. $#_];
    $optargs{fatal} ||= 0;
    my $wb;
    my $sk = $self->{qmpsocket};

    my $line = JSON::to_json($cmd) . "\n";
    if (defined $optargs{send_fd}) {
        $wb = tinycv::send_with_fd($sk, $line, $optargs{send_fd});
    }
    else {
        $wb = syswrite($sk, $line);
    }
    die "syswrite failed $!" unless ($wb == length($line));

    my $hash;
    while (!$hash) {
        $hash = myjsonrpc::read_json($sk);
        if ($hash->{event}) {
            bmwqemu::diag "EVENT " . JSON::to_json($hash);
            # ignore
            $hash = undef;
        }
    }

    if ($optargs{fatal} && defined($hash->{error})) {
        die "QMP command $cmd->{execute} failed: $hash->{error}->{class}; $hash->{error}->{desc}";
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
        die "QEMU: Shutting down the job" if $line =~ m/key event queue full/;
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
    $self->SUPER::close_pipes();
}

sub is_shutdown {
    my ($self) = @_;
    my $ret = $self->handle_qmp_command({execute => 'query-status'});
    return ($ret->{return}->{status} || '') eq 'shutdown';
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

sub freeze_vm {
    my ($self) = @_;
    # qemu specific - all other backends will crash
    my $ret = $self->handle_qmp_command({execute => 'stop'});
    # once we stopped, there is no point in querying VNC
    if (!defined $self->{_qemu_saved_request_interval}) {
        $self->{_qemu_saved_request_interval} = $self->update_request_interval;
        $self->update_request_interval(1000);
    }
    return $ret;
}

sub cont_vm {
    my ($self) = @_;
    $self->update_request_interval(delete $self->{_qemu_saved_request_interval}) if $self->{_qemu_saved_request_interval};
    return $self->handle_qmp_command({execute => 'cont'});
}

1;

# vim: set sw=4 et:
