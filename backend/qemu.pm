#!/usr/bin/perl -w

package backend::qemu;
use strict;
use base ('backend::vnc_backend');
use threads;
require File::Temp;
use File::Temp ();
use Time::HiRes qw(sleep gettimeofday);
use IO::Select;
use IO::Socket::UNIX qw( SOCK_STREAM );
use IO::Handle;
use POSIX qw/strftime :sys_wait_h/;
use JSON;
use Carp;
use Fcntl;
use bmwqemu qw(fileContent diag save_vars diag);
use backend::VNC;

sub new {
    my $class = shift;
    my $self = bless( { class => $class }, $class );

    $self->{'pid'}         = undef;
    $self->{'pidfilename'} = 'qemu.pid';

    # make sure to set environment variables in the main thread
    # exec uses the %ENV of the main thread
    $ENV{'QEMU_AUDIO_DRV'} = "none";

    return $self;
}

# baseclass virt method overwrite

sub raw_alive() {
    my ($self) = @_;
    return 0 unless $self->{'pid'};
    return kill( 0, $self->{'pid'} );
}

sub start_audiocapture($) {
    my ( $self, $filename ) = @_;
    $self->_send_hmp("wavcapture $filename 44100 16 1");
}

sub stop_audiocapture($) {
    my ( $self, $index ) = @_;
    $self->_send_hmp("stopcapture $index");
}

sub power($) {

    # parameters: acpi, reset, (on), off
    my ( $self, $action ) = @_;
    if ( $action eq 'acpi' ) {
        $self->_send_hmp("system_powerdown");
    }
    elsif ( $action eq 'reset' ) {
        $self->_send_hmp("system_reset");
    }
    elsif ( $action eq 'off' ) {
        $self->handle_qmp_command( { "execute" => "quit" } );
    }
}

sub eject_cd(;$) {
    my $self = shift;
    $self->handle_qmp_command( { "execute" => "eject", "arguments" => { "device" => "ide1-cd0" } } );
}

sub cpu_stat($) {
    my $self = shift;
    my $stat = bmwqemu::fileContent( "/proc/" . $self->{'pid'} . "/stat" );
    my @a    = split( " ", $stat );
    return [ @a[ 13, 14 ] ];
}

sub do_start_vm() {
    my $self = shift;

    # remove backend.crashed
    $self->unlink_crash_file();
    $self->start_qemu();
    return {};
}

sub kill_qemu($) {
    my ($pid) = (@_);

    # already gone?
    my $ret = waitpid($pid, WNOHANG);
    print STDERR "waitpid for $pid returned $ret\n";
    return if ($ret == $pid || $ret == -1);

    printf STDERR "sending TERM to qemu pid: %d\n", $pid;
    kill('TERM', $pid);
    for my $i (1..5) {
        sleep 1;
        $ret = waitpid($pid, WNOHANG);
        print STDERR "waitpid for $pid returned $ret\n";
        return if ($ret == $pid);
    }
    kill( "KILL", $pid);
    # now we have to wait
    waitpid($pid, 0);
}

sub do_stop_vm($) {
    my $self = shift;

    return unless $self->{'pid'};
    kill_qemu($self->{'pid'});
    $self->{'pid'} = undef;
    unlink( $self->{'pidfilename'} );
}

sub do_savevm($) {
    my ( $self, $args ) = @_;
    my $vmname = $args->{name};
    my $rsp = $self->_send_hmp("savevm $vmname");
    bmwqemu::diag "SAVED $vmname $rsp";
    die unless ( $rsp eq "savevm $vmname" );
}

sub do_loadvm($) {
    my ( $self, $args ) = @_;
    my $vmname = $args->{name};
    my $rsp = $self->_send_hmp("loadvm $vmname");
    bmwqemu::diag "LOAD $vmname '$rsp'\n";
    die unless ( $rsp eq "loadvm $vmname" );
    $rsp = $self->handle_qmp_command({"execute" => "stop"});
    bmwqemu::diag "stop $rsp\n";
    $rsp = $self->handle_qmp_command({"execute" => "cont"});
    bmwqemu::diag "cont $rsp\n";
    return $rsp;
}

# baseclass virt method overwrite end

sub start_qemu() {

    my $self = shift;
    my $vars = \%bmwqemu::vars;

    my $basedir = "raid";
    my $qemuimg = "/usr/bin/kvm-img";
    if ( !-e $qemuimg ) {
        $qemuimg = "/usr/bin/qemu-img";
    }

    my $qemubin = $ENV{'QEMU'};
    unless ($qemubin) {
        my @candidates = $vars->{QEMU}?('qemu-system-'.$vars->{QEMU}):qw/kvm qemu-kvm qemu qemu-system-x86_64 qemu-system-ppc64/;
        for my $bin ( map { '/usr/bin/' . $_ } @candidates ) {
            next unless -x $bin;
            $qemubin = $bin;
            last;
        }
        die "no Qemu/KVM found\n" unless $qemubin;
    }

    if ( $vars->{BIOS} && !-e '/usr/share/qemu/'.$vars->{BIOS} ) {
        die "'$vars->{BIOS}' missing, check BIOS\n";
    }

    if ( $vars->{LAPTOP} ) {
        if ($vars->{LAPTOP} =~ /\/|\.\./) {
            die "invalid characters in LAPTOP\n";
        }
        $vars->{LAPTOP} = 'dell_e6330' if $vars->{LAPTOP} eq '1';
        die "no dmi data for '$vars->{LAPTOP}'\n" unless -d "$bmwqemu::scriptdir/dmidata/$vars->{LAPTOP}";
    }

    my $iso = $vars->{ISO};
    # disk settings
    $vars->{NUMDISKS}  ||= 1;
    $vars->{HDDSIZEGB} ||= 10;
    $vars->{HDDMODEL}  ||= "virtio-blk";
    if ($vars->{MULTIPATH}) {
        $vars->{HDDMODEL} = "virtio-scsi-pci";
        $vars->{PATHCNT} ||= 2;
    }
    # network settings
    $vars->{NICMODEL}  ||= "virtio-net";
    $vars->{NICTYPE}   ||= "user";
    $vars->{NICMAC}    ||= "52:54:00:12:34:56";
    # misc
    my $arch_supports_boot_order = 1;
    my $use_usb_kbd;
    my @vgaoptions;
    if ($vars->{ARCH} eq 'aarch64') {
        push @vgaoptions, '-device', 'VGA';
        $arch_supports_boot_order = 0;
        $use_usb_kbd = 1;
    }
    elsif ($vars->{OFW}) {
        $vars->{QEMUVGA} ||= "std";
        push(@vgaoptions, '-g', '1024x768' );
        #$use_usb_kbd = 1; # implicit on ppc
    }
    else {
        $vars->{QEMUVGA} ||= "cirrus";
    }
    push(@vgaoptions, "-vga", $vars->{QEMUVGA}) if $vars->{QEMUVGA};

    $vars->{QEMUCPUS}  ||= 1;
    if ( defined( $vars->{RAIDLEVEL} ) ) {
        $vars->{NUMDISKS} = 4;
    }
    bmwqemu::save_vars(); # update variables

    use File::Path qw/mkpath/;
    mkpath($basedir);

    if ( !$vars->{KEEPHDDS} && !$vars->{SKIPTO} ) {

        # fresh HDDs
        for my $i ( 1 .. $vars->{NUMDISKS} ) {
            unlink("$basedir/l$i");
            if ( -e "$basedir/$i.lvm" ) {
                symlink( "$i.lvm", "$basedir/l$i" ) or die "$!\n";
                die "$!\n" unless system( "/bin/dd", "if=/dev/zero", "count=1", "of=$basedir/l1" ) == 0;    # for LVM
            }
            elsif ( $vars->{"HDD_$i"} ) {
                die "$!\n" unless system( $qemuimg, "create", "$basedir/$i", "-f", "qcow2", "-b", $vars->{"HDD_$i"} ) == 0;
                symlink( $i, "$basedir/l$i" ) or die "$!\n";
            }
            else {
                die "$!\n" unless system( $qemuimg, "create", "$basedir/$i", "-f", "qcow2", $vars->{HDDSIZEGB} . "G" ) == 0;
                symlink( $i, "$basedir/l$i" ) or die "$!\n";
            }
        }

        if ( $vars->{AUTO_INST} ) {
            unlink("$basedir/autoinst.img");
            system( "/sbin/mkfs.vfat", "-C", "$basedir/autoinst.img", "1440" );
            system( "/usr/bin/mcopy", "-i", "$basedir/autoinst.img", $vars->{AUTO_INST}, "::/" );

            #system("/usr/bin/mdir","-i","$basedir/autoinst.img");
        }
    }

    for my $i ( 1 .. 4 ) {    # create missing symlinks
        next if -e "$basedir/l$i";
        next unless -e "$basedir/$i";
        symlink( $i, "$basedir/l$i" ) or die "$!\n";
    }

    pipe(my $reader, my $writer);
    my $pid = fork();
    die "fork failed" unless defined($pid);
    if ( $pid == 0 ) {
        $SIG{__DIE__} = undef; # overwrite the default - just exit
        my @params = ( "-serial", "file:serial0", "-soundhw", "ac97", "-global", "isa-fdc.driveA=", @vgaoptions);

        push( @params, '-m', $vars->{QEMURAM} || '1024' );

        if ( $vars->{QEMUMACHINE} ) {
            push( @params, "-machine", $vars->{QEMUMACHINE});
        }

        if ( $vars->{QEMUCPU} ) {
            push( @params, "-cpu", $vars->{QEMUCPU} );
        }

        if ( $vars->{NICTYPE} eq "user" ) {
            push( @params, '-netdev', 'user,id=qanet0');
        }
        elsif ( $vars->{NICTYPE} eq "tap" ) {
            if (!$vars->{TAPDEV}) {
                die "TAPDEV variable is required for NICTYPE==tap\n";
            }
            push( @params, '-netdev', "tap,id=qanet0,ifname=$vars->{TAPDEV},script=no,downscript=no");
        }
        else {
            die "uknown NICTYPE $vars->{NICTYPE}\n";
        }
        push( @params, '-device', "$vars->{NICMODEL},netdev=qanet0,mac=$vars->{NICMAC}");

        if ( $vars->{LAPTOP} ) {
            my $laptop_path = "$bmwqemu::scriptdir/dmidata/$vars->{LAPTOP}";
            for my $f (<$laptop_path/*.bin>) {
                push @params, '-smbios', "file=$f";
            }
        }

        if ( $vars->{HDDMODEL} =~ /virtio-scsi.*/ ) {
            # scsi devices need SCSI controller, then change to scsi-hd device
            push( @params, "-device", "$vars->{HDDMODEL},id=scsi0" );
            if ($vars->{MULTIPATH}) {
                # add the second HBA
                push( @params, "-device", "$vars->{HDDMODEL},id=scsi1" );
            }
            $vars->{HDDMODEL} = "scsi-hd";
        }
        for my $i ( 1 .. $vars->{NUMDISKS} ) {
            my $boot = "";    #$i==1?",boot=on":""; # workaround bnc#696890
            if ($vars->{MULTIPATH}) {
                for my $c ( 1 .. $vars->{PATHCNT} ) {
                    # pathname is a .. d
                    my $pathname = chr(96 + $c);
                    push( @params, "-drive", "file=$basedir/l$i,cache=unsafe,if=none$boot,id=hd${i}${pathname},serial=mpath$i" );
                    push( @params, "-device", "$vars->{HDDMODEL},drive=hd${i}${pathname},bus=scsi" . ($c % 2 ? "1" : "0") . ".0" );
                }
            }
            else {
                push( @params, "-device", "$vars->{HDDMODEL},drive=hd$i" . ( $vars->{HDDMODEL} =~ /ide-hd/ ? ",bus=ide.@{[$i-1]}" : '' ) );
                push( @params, "-drive", "file=$basedir/l$i,cache=unsafe,if=none$boot,id=hd$i" );
            }
        }

        if ($iso) {
            if ( $vars->{USBBOOT} ) {
                push( @params, "-drive",  "if=none,id=usbstick,file=$iso,snapshot=on" );
                push( @params, "-device", "usb-ehci,id=ehci" );
                push( @params, "-device", "usb-storage,bus=ehci.0,drive=usbstick,id=devusb" );
            }
            elsif ($vars->{CDMODEL}) {
                push(@params, '-drive', "media=cdrom,if=none,id=cd0,format=raw,file=$iso");
                push(@params, '-device', "$vars->{CDMODEL},drive=cd0");
            }
            else {
                push( @params, "-cdrom", $iso );
            }
        }

        for my $i ( 1 .. 6 ) {  # check for up to 6 ADDON ISOs
            if ( $vars->{"ISO_$i"} && $vars->{"ADDONS"}) {
                my $addoniso = $vars->{"ISO_$i"};
                push( @params, "-drive", "if=scsi,id=addon_$i,file=$addoniso,media=cdrom" );
            }
        }

        if ($arch_supports_boot_order) {
            if ( $vars->{PXEBOOT} ) {
                push( @params, "-boot", "n");
            }
            elsif ( $vars->{BOOTFROM} ) {
                push( @params, "-boot", "order=$vars->{BOOTFROM},menu=on,splash-time=5000" );
            }
            else {
                push( @params, "-boot", "once=d,menu=on,splash-time=5000" );
            }
        }

        if ( $vars->{UEFI} ) {
            # XXX: compat with old deployment
            $vars->{BIOS} //= $vars->{UEFI_BIOS};
            $vars->{BIOS} //= 'ovmf-x86_64-ms.bin' if $vars->{ARCH} eq 'x86_64';
        }
        if ( $vars->{BIOS} ) {
            push( @params, "-bios", '/usr/share/qemu/'.$vars->{BIOS} );
        }
        if ( $vars->{MULTINET} ) {
            if ( $vars->{NICTYPE} eq "tap" ) {
                die "MULTINET is not supported with NICTYPE==tap\n";
            }
            no warnings 'qw';
            push( @params, qw"-net nic,vlan=1,model=$vars->{NICMODEL},macaddr=52:54:00:12:34:57 -net none,vlan=1" );
        }
        push(@params, qw/-device usb-ehci -device usb-tablet/);
        if ($use_usb_kbd) {
            push(@params, qw/-device usb-kbd/);
        }
        push( @params, "-smp", $vars->{QEMUCPUS} );
        push( @params, "-enable-kvm" ) unless $vars->{QEMU_NO_KVM};
        push( @params, "-no-shutdown" );

        if ( open( my $cmdfd, '>', 'runqemu' ) ) {
            print $cmdfd "#!/bin/bash\n";
            my @args = map { s,\\,\\\\,g; s,\$,\\\$,g; s,\",\\\",g; s,\`,\\\`,g; "\"$_\"" } @params;
            printf $cmdfd "%s \\\n  %s \\\n  \"\$@\"\n", $qemubin, join( " \\\n  ", @args );
            close $cmdfd;
            chmod 0755, 'runqemu';
        }

        if ( $vars->{VNC} ) {
            if ( $vars->{VNC} !~ /:/ ) {
                $vars->{VNC} = ":$vars->{VNC}";
            }
            push( @params, "-vnc", "$vars->{VNC},share=force-shared" );
            push( @params, "-k", $vars->{VNCKB} ) if ( $vars->{VNCKB} );
        }

        push @params, '-qmp', "unix:qmp_socket,server,nowait", "-monitor", "unix:hmp_socket,server,nowait", "-S";
        my $port = $vars->{QEMUPORT};
        push @params, "-monitor", "telnet:127.0.0.1:$port,server,nowait";

        unshift( @params, $qemubin );
        unshift( @params, "/usr/bin/eatmydata" ) if ( -e "/usr/bin/eatmydata" );

        # easter egg can be quite annoying and happens in December
        # and January. February next year ...
        my @date = gmtime;
        if ( $date[4] == 0 || $date[4] == 11 ) {
            $date[5]++ if $date[4] == 11;
            $date[4] = 1;
            push @params, '-rtc', POSIX::strftime( "base=%Y-%m-%dT%H%M%S", @date );
        }

        if ( $vars->{AUTO_INST} ) {
            push( @params, "-drive", "file=$basedir/autoinst.img,index=0,if=floppy" );
        }
        bmwqemu::diag( "starting: " . join( " ", @params ) );

        # redirect qemu's output to the parent pipe
        open(STDOUT, ">&", $writer) || die "can't dup stdout: $!";
        open(STDERR, ">&", $writer) || die "can't dup stderr: $!";
        close($reader);
        exec(@params);
        die "failed to exec qemu";
    }
    else {
        $self->{'pid'} = $pid;
    }
    close $writer;
    $self->{'qemupipe'} = $reader;
    open( my $pidf, ">", $self->{'pidfilename'} ) or die "can not write " . $self->{'pidfilename'};
    print $pidf $self->{'pid'}, "\n";
    close $pidf;

    $self->{'vnc'} = backend::VNC->new({hostname => 'localhost', port => 5900 + $bmwqemu::vars{VNC} });

    # the real timeout is the 7 below
    for my $i (1..10) {
        eval {
            # we sure don't want to stop the vm in case this fails
            local $SIG{'__DIE__'};
            $self->{'vnc'}->login;
        };
        if ($@) {
            if ($i > 7) {
                $self->close_pipes();
                die $@;
            }
            else {
                sleep 1;
            }
        }
        else {
            last;
        }
    }

    $self->{'hmpsocket'} = IO::Socket::UNIX->new(
        Type     => IO::Socket::UNIX::SOCK_STREAM,
        Peer     => "hmp_socket",
        Blocking => 0
    ) or die "can't open hmp";

    $self->{'hmpsocket'}->autoflush(1);
    binmode $self->{'hmpsocket'};
    my $flags = fcntl( $self->{'hmpsocket'}, Fcntl::F_GETFL, 0 ) or die "can't getfl(): $!\n";
    $flags = fcntl( $self->{'hmpsocket'}, Fcntl::F_SETFL, $flags | Fcntl::O_NONBLOCK ) or die "can't setfl(): $!\n";

    $self->{'qmpsocket'} = IO::Socket::UNIX->new(
        Type     => IO::Socket::UNIX::SOCK_STREAM,
        Peer     => "qmp_socket",
        Blocking => 0
    ) or die "can't open qmp";

    $self->{'qmpsocket'}->autoflush(1);
    binmode $self->{'qmpsocket'};
    $flags = fcntl( $self->{'qmpsocket'}, Fcntl::F_GETFL, 0 ) or die "can't getfl(): $!\n";
    $flags = fcntl( $self->{'qmpsocket'}, Fcntl::F_SETFL, $flags | Fcntl::O_NONBLOCK ) or die "can't setfl(): $!\n";

    STDERR->printf("$$: hmpsocket %d, qmpsocket %d\n",fileno($self->{'hmpsocket'}),fileno($self->{'qmpsocket'}));

    fcntl( $self->{'qemupipe'}, Fcntl::F_SETFL, Fcntl::O_NONBLOCK ) or die "can't setfl(): $!\n";

    # retrieve welcome
    my $line = $self->_read_hmp;
    print "WELCOME $line\n";

    my $init = backend::driver::_read_json($self->{'qmpsocket'});
    syswrite( $self->{'qmpsocket'}, "{'execute': 'qmp_capabilities'}\n" );
    my $hash = backend::driver::_read_json($self->{'qmpsocket'});
    if (0) {
        syswrite( $self->{'qmpsocket'}, "{'execute': 'query-commands'}\n" );
        $hash = backend::driver::_read_json($self->{'qmpsocket'});
        die "no commands!" unless ($hash);
        print "COMMANDS " . JSON::to_json( $hash, { pretty => 1 } ) . "\n";
    }

    my $cnt = bmwqemu::fileContent("$ENV{HOME}/.autotestvncpw");
    if ($cnt) {
        $self->send($cnt);
    }

    $self->handle_qmp_command({"execute" => "cont"});

    $self->{'select'}->add($self->{'qemupipe'});

    $self->capture_screenshot();
}

sub _read_hmp($) {
    my ($self) = @_;

    my $rsp = '';
    my $s   = IO::Select->new();
    $s->add($self->{'hmpsocket'});

    while ( my @ready = $s->can_read(60) ) {
        my $buffer;
        my $bytes = sysread( $self->{'hmpsocket'}, $buffer, 1000 );
        last unless ($bytes);
        $rsp .= $buffer;
        my @rsp2 = unpack( "C*", $rsp );
        my $line = '';
        for my $c (@rsp2) {
            if ( $c == 13 ) {

                # skip
            }
            elsif ( $c == 10 ) {
                $line .= "\n";
            }
            elsif ( $c == 27 ) {
                $line .= "^";
            }
            elsif ( $c < 32 ) {
                $line .= "C$c ";
            }
            else {
                $line .= chr($c);
            }
        }

        # remove nop
        $line =~ s/\^\[K//g;

        # remove "cursor back"
        while ( $line =~ m/.\^\[D/ ) {
            $line =~ s/.\^\[D//;
        }
        if ( $line =~ m/\n\(qemu\) *$/ ) {
            $line =~ s/\n\(qemu\) *$//;
            return $line;
        }
    }

    backend::baseclass::write_crash_file;
    die "ERROR: timeout reading hmp socket\n";
}

sub special_socket($) {
    my ($self, $fh);
    if ($fh == $self->{'qemupipe'}) {
        $self->read_qemupipe();
        return 1;
    }
    return $self->SUPER::special_socket($fh);
}

sub select_for_vnc {
    my ($self) = @_;

    my $s = $self->SUPER::select_for_vnc;
    $s->add($self->{'qemupipe'});
    return $s;
}

# runs in the thread to bounce QMP
sub handle_qmp_command($) {

    my ($self, $cmd) = @_;

    my $line = JSON::to_json($cmd);
    my $wb = syswrite( $self->{'qmpsocket'}, "$line\n" );
    die "syswrite failed $!" unless ( $wb == length($line) + 1 );

    #print STDERR "wrote $wb\n";
    my $hash;
    while ( !$hash ) {
        $hash = backend::driver::_read_json($self->{'qmpsocket'});
        if ( $hash->{event} ) {
            print STDERR "EVENT " . JSON::to_json($hash) . "\n";

            # ignore
            $hash = undef;
        }
    }

    return $hash;
}

sub read_qemupipe() {
    my ($self) = @_;
    my $buffer;
    my $bytes = sysread( $self->{'qemupipe'}, $buffer, 1000 );
    chomp $buffer;
    for my $line (split(/\n/, $buffer)) {
        bmwqemu::diag "QEMU: $line";
    }
    return $bytes;
}

sub close_pipes() {
    my ($self) = @_;

    $self->do_stop_vm();

    if ($self->{'qemupipe'}) {
        # one last word?
        fcntl( $self->{'qemupipe'}, Fcntl::F_SETFL, Fcntl::O_NONBLOCK );
        $self->read_qemupipe();
        close($self->{'qemupipe'});
        $self->{'qemupipe'} = undef;
    }

    if ($self->{'qmpsocket'}) {
        close($self->{'qmpsocket'}) || die "close $!\n";
        $self->{'qmpsocket'} = undef;
    }
    if ($self->{'hmpsocket'}) {
        close($self->{'hmpsocket'}) || die "close $!\n";
        $self->{'hmpsocket'} = undef;
    }
    $self->SUPER::close_pipes();
}

sub _send_hmp {
    my ($self, $hmp) = @_;

    my $wb = syswrite( $self->{'hmpsocket'}, "$hmp\n" );

    #print STDERR "wrote HMP $wb $cmd->{hmp}\n";
    die "syswrite failed $!" unless ( $wb == length($hmp) + 1 );

    return $self->_read_hmp;
}

sub handle_hmp_command {
    my ($self, $hmp) = @_;

    my $line = $self->_send_hmp($hmp);
    $self->{'rsppipe'}->print(JSON::to_json( { "rsp" => $line }));
}

# this is called for all sockets ready to read from. return 1 if socket
# detected and -1 if there was an error
sub check_socket {
    my ($self, $fh) = @_;

    if ( $self->{'qemupipe'} && $fh == $self->{'qemupipe'}) {
        $self->close_pipes() unless $self->read_qemupipe();
        return 1;
    }
    return $self->SUPER::check_socket($fh);
}

1;

# vim: set sw=4 et:
