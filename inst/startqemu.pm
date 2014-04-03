#!/usr/bin/perl -w
use strict;

package startqemu;

sub run($) {

    my $backend = shift;

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

    my $iso = $ENV{ISO};
    $ENV{HDDSIZEGB} ||= 10;
    $ENV{HDDMODEL}  ||= "virtio-blk";
    $ENV{NICMODEL}  ||= "virtio";
    $ENV{QEMUVGA}   ||= "cirrus";
    $ENV{QEMUCPUS}  ||= 1;
    $ENV{NUMDISKS}  ||= 2;
    if ( defined( $ENV{RAIDLEVEL} ) ) {
        $ENV{NUMDISKS} = 4;
    }

    $ENV{QEMU_AUDIO_DRV} = "wav";
    $ENV{QEMU_WAV_PATH}  = "/dev/null";

    if ( $ENV{UEFI} && !-e $ENV{UEFI_BIOS} ) {
        die "'$ENV{UEFI_BIOS}' missing, check UEFI_BIOS\n";
    }

    use File::Path qw/mkpath/;
    mkpath($basedir);

    if ( !$ENV{KEEPHDDS} && !$ENV{SKIPTO} ) {

        # fresh HDDs
        for my $i ( 1 .. $ENV{NUMDISKS} ) {
            unlink("$basedir/l$i");
            if ( -e "$basedir/$i.lvm" ) {
                symlink( "$i.lvm", "$basedir/l$i" ) or die "$!\n";
                die "$!\n" unless system( "/bin/dd", "if=/dev/zero", "count=1", "of=$basedir/l1" ) == 0;    # for LVM
            }
            elsif ( $ENV{"HDD_$i"} ) {
                die "$!\n" unless system( $qemuimg, "create", "$basedir/$i", "-f", "qcow2", "-b", $ENV{"HDD_$i"} ) == 0;
                symlink( $i, "$basedir/l$i" ) or die "$!\n";
            }
            else {
                die "$!\n" unless system( $qemuimg, "create", "$basedir/$i", "-f", "qcow2", $ENV{HDDSIZEGB} . "G" ) == 0;
                symlink( $i, "$basedir/l$i" ) or die "$!\n";
            }
        }

        if ( $ENV{AUTO_INST} ) {
            unlink("$basedir/autoinst.img");
            system( "/sbin/mkfs.vfat", "-C", "$basedir/autoinst.img", "1440" );
            system( "/usr/bin/mcopy", "-i", "$basedir/autoinst.img", $ENV{AUTO_INST}, "::/" );

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
        my @params = ( '-m', '1024', '-net', 'user', "-net", "nic,model=$ENV{NICMODEL},macaddr=52:54:00:12:34:56", "-serial", "file:serial0", "-soundhw", "ac97", "-global", "isa-fdc.driveA=", "-vga", $ENV{QEMUVGA}, "-machine", "accel=kvm,kernel_irqchip=on" );

        if ( $ENV{LAPTOP} ) {
            for my $f (<$ENV{LAPTOP}/*.bin>) {
                push @params, '-smbios', "file=$f";
            }
        }

        for my $i ( 1 .. $ENV{NUMDISKS} ) {
            my $boot = "";    #$i==1?",boot=on":""; # workaround bnc#696890
            push( @params, "-drive", "file=$basedir/l$i,cache=unsafe,if=none$boot,id=hd$i" );
            push( @params, "-device", "$ENV{HDDMODEL},drive=hd$i" . ( $ENV{HDDMODEL} =~ /ide-hd/ ? ",bus=ide.@{[$i-1]}" : '' ) );
        }

        if ($iso) {
            if ( $ENV{USBBOOT} ) {
                push( @params, "-drive",  "if=none,id=usbstick,file=$iso,snapshot=on" );
                push( @params, "-device", "usb-ehci,id=ehci" );
                push( @params, "-device", "usb-storage,bus=ehci.0,drive=usbstick,id=devusb" );
            }
            else {
                push( @params, "-cdrom", $iso );
            }
        }

        push( @params, "-boot", "once=d,menu=on,splash-time=5000" );

        if ( $ENV{QEMUCPU} ) {
            push( @params, "-cpu", $ENV{QEMUCPU} );
        }
        if ( $ENV{UEFI} ) {
            push( @params, "-bios", $ENV{UEFI_BIOS} );
        }
        if ( $ENV{MULTINET} ) {
            no warnings 'qw';
            push( @params, qw"-net nic,vlan=1,model=$ENV{NICMODEL},macaddr=52:54:00:12:34:57 -net none,vlan=1" );
        }
        push( @params, "-usb", "-usbdevice", "tablet" );
        push( @params, "-smp", $ENV{QEMUCPUS} );
        push( @params, "-enable-kvm" );

        if ( open( my $cmdfd, '>', 'runqemu' ) ) {
            print $cmdfd "#!/bin/bash\n";
            my @args = map { s,\\,\\\\,g; s,\$,\\\$,g; s,\",\\\",g; s,\`,\\\`,g; "\"$_\"" } @params;
            printf $cmdfd "%s \\\n  %s \\\n  \"\$@\"\n", $qemubin, join( " \\\n  ", @args );
            close $cmdfd;
            chmod 0755, 'runqemu';
        }

        if ( $ENV{VNC} ) {
            if ( $ENV{VNC} !~ /:/ ) {
                $ENV{VNC} = ":$ENV{VNC}";
            }
            push( @params, "-vnc", $ENV{VNC} );
            push( @params, "-k", $ENV{VNCKB} ) if ( $ENV{VNCKB} );
        }

        push @params, '-qmp', "unix:qmp_socket,server,nowait", "-monitor", "unix:hmp_socket,server,nowait", "-S";
        my $port = $ENV{QEMUPORT} + 1;
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

        if ( $ENV{AUTO_INST} ) {
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
