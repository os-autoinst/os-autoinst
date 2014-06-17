#!/usr/bin/perl -w
use strict;

package startqemu;

sub run($$) {

    my $backend = shift;
    my $vars = shift;

    my $basedir = "raid";
    my $qemuimg = "/usr/bin/kvm-img";
    if ( !-e $qemuimg ) {
        $qemuimg = "/usr/bin/qemu-img";
    }

    my $qemubin = $ENV{'QEMU'};
    unless ($qemubin) {
        for my $bin ( map { '/usr/bin/' . $_ } qw/kvm qemu-kvm qemu qemu-system-x86_64/ ) {
            next unless -x $bin;
            $qemubin = $bin;
            last;
        }
        die "no Qemu/KVM found\n" unless $qemubin;
    }

    my $iso = $vars->{ISO};
    # disk settings
    $vars->{NUMDISKS}  ||= 2;
    $vars->{HDDSIZEGB} ||= 10;
    $vars->{HDDMODEL}  ||= "virtio-blk";
    # network settings
    $vars->{NICMODEL}  ||= "virtio-net";
    $vars->{NICTYPE}   ||= "user";
    $vars->{NICMAC}    ||= "52:54:00:12:34:56";
    # misc
    $vars->{QEMUVGA}   ||= "cirrus";
    $vars->{QEMUCPUS}  ||= 1;
    if ( defined( $vars->{RAIDLEVEL} ) ) {
        $vars->{NUMDISKS} = 4;
    }

    $ENV{QEMU_AUDIO_DRV} = "wav";
    $ENV{QEMU_WAV_PATH}  = "/dev/null";

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

    $backend->{'pid'} = fork();
    die "fork failed" if ( !defined( $backend->{'pid'} ) );
    if ( $backend->{'pid'} == 0 ) {
        my @params = ( '-m', '1024', "-serial", "file:serial0", "-soundhw", "ac97", "-global", "isa-fdc.driveA=", "-vga", $vars->{QEMUVGA}, "-machine", "accel=kvm,kernel_irqchip=on" );

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
            push( @params, "-device", "$vars->{HDDMODEL},id=scsi" );
            $vars->{HDDMODEL} = "scsi-hd";
        }
        for my $i ( 1 .. $vars->{NUMDISKS} ) {
            my $boot = "";    #$i==1?",boot=on":""; # workaround bnc#696890
            push( @params, "-drive", "file=$basedir/l$i,cache=unsafe,if=none$boot,id=hd$i" );
            push( @params, "-device", "$vars->{HDDMODEL},drive=hd$i" . ( $vars->{HDDMODEL} =~ /ide-hd/ ? ",bus=ide.@{[$i-1]}" : '' ) );
        }

        if ($iso) {
            if ( $vars->{USBBOOT} ) {
                push( @params, "-drive",  "if=none,id=usbstick,file=$iso,snapshot=on" );
                push( @params, "-device", "usb-ehci,id=ehci" );
                push( @params, "-device", "usb-storage,bus=ehci.0,drive=usbstick,id=devusb" );
            }
            elsif ( $vars->{PXEBOOT} ) {
                push( @params, "-boot", "n");
            }
            else {
                push( @params, "-cdrom", $iso );
            }
        }

        push( @params, "-boot", "once=d,menu=on,splash-time=5000" );

        if ( $vars->{QEMUCPU} ) {
            push( @params, "-cpu", $vars->{QEMUCPU} );
        }
        if ( $vars->{UEFI} ) {
            push( @params, "-bios", '/usr/share/qemu/'.$vars->{UEFI_BIOS} );
        }
        if ( $vars->{MULTINET} ) {
            if ( $vars->{NICTYPE} eq "tap" ) {
                die "MULTINET is not supported with NICTYPE==tap\n";
            }
            no warnings 'qw';
            push( @params, qw"-net nic,vlan=1,model=$vars->{NICMODEL},macaddr=52:54:00:12:34:57 -net none,vlan=1" );
        }
        push( @params, "-usb", "-usbdevice", "tablet" );
        push( @params, "-smp", $vars->{QEMUCPUS} );
        push( @params, "-enable-kvm" );

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
            push( @params, "-vnc", $vars->{VNC} );
            push( @params, "-k", $vars->{VNCKB} ) if ( $vars->{VNCKB} );
        }

        push @params, '-qmp', "unix:qmp_socket,server,nowait", "-monitor", "unix:hmp_socket,server,nowait", "-S";
        my $port = $vars->{QEMUPORT} + 1;
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

        exec(@params);
        die "exec $qemubin failed";
    }
    open( my $pidf, ">", $backend->{'pidfilename'} ) or die "can not write " . $backend->{'pidfilename'};
    print $pidf $backend->{'pid'}, "\n";
    close $pidf;
    sleep 6;    # time to let qemu start

}

1;
# vim: set sw=4 et:
