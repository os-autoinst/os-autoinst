# Copyright © 2016 SUSE LLC
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

package backend::null;
use strict;
use base ('backend::virt');
use File::Path qw/mkpath/;
use File::Temp ();
use Time::HiRes qw(sleep gettimeofday);
use IO::Select;
use IO::Socket::UNIX qw( SOCK_STREAM );
use IO::Handle;
use POSIX qw/strftime :sys_wait_h/;
use JSON;
use Carp;
use Fcntl;
use Net::DBus;
use bmwqemu qw(fileContent diag save_vars);
require IPC::System::Simple;
use autodie qw(:all);

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
}

sub start_audiocapture {
    my ($self, $args) = @_;
}

sub stop_audiocapture {
    my ($self, $args) = @_;
}

sub power {
    my ($self, $args) = @_;
}

sub eject_cd {
    my $self = shift;
    $self->handle_qmp_command({execute => 'eject', arguments => {device => 'cd0'}});
}

sub cpu_stat {
    my $self = shift;
}

sub do_start_vm {
    my $self = shift;
    $self->start_qemu();
    return {};
}

sub kill_qemu {
    my ($self) = (@_);
}

sub do_stop_vm {
    my $self = shift;
}

sub can_handle {
    my ($self, $args) = @_;
    if ($args->{function} eq 'snapshots') {
        return {ret => 1};
    }
    return;
}

sub save_snapshot {
    my ($self, $args) = @_;
    return;
}

sub load_snapshot {
    my ($self, $args) = @_;
    return;
}

sub runcmd {
    diag "running " . join(' ', @_);
}

sub do_extract_assets {
    my ($self, $args) = @_;
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
        my @candidates = $vars->{QEMU} ? ('qemu-system-' . $vars->{QEMU}) : qw/kvm qemu-kvm qemu qemu-system-x86_64 qemu-system-ppc64/;
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

    foreach my $attribute (qw/BIOS KERNEL INITRD/) {
        if ($vars->{$attribute} && $vars->{$attribute} !~ /^\//) {
            # Non-absolute paths are assumed relative to /usr/share/qemu
            $vars->{$attribute} = '/usr/share/qemu/' . $vars->{$attribute};
        }
        if ($vars->{$attribute} && !-e $vars->{$attribute}) {
            die "'$vars->{$attribute}' missing, check $attribute\n";
        }
    }

    if ($vars->{UEFI} && $vars->{ARCH} eq 'x86_64' && !$vars->{BIOS}) {
        # We have to try and find a firmware for UEFI. These are known
        # locations for openSUSE and Fedora (respectively).
        my @known = ('/usr/share/qemu/ovmf-x86_64-ms.bin', '/usr/share/edk2.git/ovmf-x64/OVMF_CODE-pure-efi.fd');
        foreach my $firmware (@known) {
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

    if ($vars->{BOOT_HDD_IMAGE}) {
        # skip dvd boot menu and boot directly from hdd
        $vars->{BOOTFROM} //= 'c';
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
    for my $var (qw/HDDMODEL CDMODEL/) {
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
    $vars->{QEMUVGA} ||= "cirrus";
    push(@vgaoptions, "-vga", $vars->{QEMUVGA}) if $vars->{QEMUVGA};
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
    bmwqemu::save_vars();                 # update variables

    mkpath($basedir);

    my $keephdds = $vars->{KEEPHDDS} || $vars->{SKIPTO};

    # fresh HDDs
    for my $i (1 .. $vars->{NUMDISKS}) {
        # skip HDD refresh when HDD exists and KEEPHDDS or SKIPTO is set
        next if ($keephdds && (-e "$basedir/$i.lvm" || -e "$basedir/$i"));
        no autodie qw(unlink);
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
            my $nictype_user_options = '';
            push(@params, '-netdev', "user,id=qanet$i$nictype_user_options");
            push(@params, '-device', "$vars->{NICMODEL},netdev=qanet$i,mac=$nicmac[$i]");
        }

        for my $i (1 .. $vars->{NUMDISKS}) {
            push(@params, "-device", "$vars->{HDDMODEL},drive=hd$i");
            push(@params, "-drive",  "file=$basedir/l$i,cache=unsafe,if=none,id=hd$i,format=$vars->{HDDFORMAT}");
        }

        my $cdbus = $vars->{CDMODEL} ne 'ide-cd' ? ',bus=scsi0.0' : '';
        if ($iso) {
            push(@params, '-drive', "media=cdrom,if=none,id=cd0,format=raw,file=$iso");
            # XXX: workaround for OVMF wanting to write NVvars into first FAT partition
            # we need to replace -bios with proper pflash drive specification
            $params[-1] .= ',snapshot=on' if $vars->{UEFI};
            push(@params, '-device', "$vars->{CDMODEL},drive=cd0" . $cdbus);
        }

        for my $k (sort grep { /^ISO_\d+$/ } keys %$vars) {
            my $addoniso = $vars->{$k};
            my $i        = $k;
            $i =~ s/^ISO_//;
            push(@params, '-drive',  "media=cdrom,if=none,id=cd$i,format=raw,file=$addoniso");
            push(@params, '-device', "$vars->{CDMODEL},drive=cd$i" . $cdbus);
        }

        push(@params, qw/-device usb-ehci -device usb-tablet/);
        if ($use_usb_kbd) {
            push(@params, qw/-device usb-kbd/);
        }
        if ($vars->{QEMUTHREADS}) {
            push(@params, "-smp", $vars->{QEMUCPUS} . ",threads=" . $vars->{QEMUTHREADS});
        }
        else {
            push(@params, "-smp", $vars->{QEMUCPUS});
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
        unshift(@params, $qemubin);

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
}

sub handle_qmp_command {
    my ($self, $cmd) = @_;
    return {};
}

sub read_qemupipe {
    my ($self) = @_;
    return 0;
}

sub is_shutdown {
    my ($self) = @_;
    return 1;
}

sub handle_hmp_command {
    my ($self, $hmp) = @_;
}

sub check_socket {
    my ($self, $fh, $write) = @_;
    return $self->SUPER::check_socket($fh);
}

sub wait_idle {
    my ($self, $args) = @_;
    return;
}

sub freeze_vm {
    my ($self) = @_;
    return $self->handle_qmp_command({execute => 'stop'});
}

sub cont_vm {
    my ($self) = @_;
    return $self->handle_qmp_command({execute => 'cont'});
}

1;

# vim: set sw=4 et:
