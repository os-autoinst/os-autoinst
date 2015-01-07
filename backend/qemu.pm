#!/usr/bin/perl -w

package backend::qemu;
use strict;
use base ('backend::baseclass');
use threads;
require File::Temp;
use File::Temp ();
use Time::HiRes qw(sleep gettimeofday);
use IO::Select;
use IO::Socket::UNIX qw( SOCK_STREAM );
use IO::Handle;
use Data::Dumper;
use POSIX qw/strftime :sys_wait_h/;
use JSON;
use Carp;
use Carp::Always;
use Fcntl;
use bmwqemu qw(fileContent diag save_vars diag);
use backend::VNC;

my $MAGIC_PIPE_CLOSE_STRING = 'xxxQUITxxx';

sub new {
    my $class = shift;
    my $self = bless( { class => $class }, $class );

    $self->{'pid'}         = undef;
    $self->{'pidfilename'} = 'qemu.pid';

    return $self;
}

# baseclass virt method overwrite

sub raw_alive($) {
    my $self = shift;
    return 0 unless $self->{'pid'};
    return kill( 0, $self->{'pid'} );
}

sub start_audiocapture($) {
    my ( $self, $filename ) = @_;
    $self->send("wavcapture $filename 44100 16 1");
}

sub stop_audiocapture($) {
    my ( $self, $index ) = @_;
    $self->send("stopcapture $index");
}

sub power($) {

    # parameters: acpi, reset, (on), off
    my ( $self, $action ) = @_;
    if ( $action eq 'acpi' ) {
        $self->send("system_powerdown");
    }
    elsif ( $action eq 'reset' ) {
        $self->send("system_reset");
    }
    elsif ( $action eq 'off' ) {
        $self->send("quit");
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
    print "do_start_vm\n";
    my $self = shift;
    die "startqemu failed: $@" if $@;

    # remove backend.crashed
    $self->unlink_crash_file();
    $self->start_qemu();
}

sub do_stop_vm($) {
    my $self = shift;

    $self->{mgmt}->stop() if $self->{mgmt};
    $self->{mgmt} = undef;

    sleep(0.1);
    waitpid($self->{pid}, WNOHANG);
    my $n;
    for (my $i = 0; $i < 3; ++$i) {
        # dead meanwhile?
        $n = kill(0, $self->{'pid'});
        last if ($n == 0);
        printf STDERR "sending TERM to %d\n", $self->{'pid'};
        $n = kill( "TERM", $self->{'pid'} );
        last if ($n == 0); # we're done when qemu is gone
        sleep 1;
        waitpid($self->{pid}, WNOHANG);
    }
    if ($n != 0) {
        printf STDERR "sending KILL to %d\n", $self->{'pid'};
        $n = kill( "KILL", $self->{'pid'} );
        sleep 1;
        waitpid($self->{pid}, WNOHANG);
        $n = kill(0, $self->{'pid'});
        warn "ERROR: qemu still not dead. wtf?" if $n;
    }
    unlink( $self->{'pidfilename'} );
}

sub do_savevm($) {
    my ( $self, $vmname ) = @_;
    my $rsp = $self->send("savevm $vmname")->{return};
    bmwqemu::diag "SAVED $vmname $rsp";
    die unless ( $rsp eq "savevm $vmname" );
}

sub do_loadvm($) {
    my ( $self, $vmname ) = @_;
    my $rsp = $self->send("loadvm $vmname")->{return};
    bmwqemu::diag "LOAD $vmname '$rsp'\n";
    die unless ( $rsp eq "loadvm $vmname" );
    $rsp = $self->send("stop")->{return};
    bmwqemu::diag "stop $rsp\n";
    $rsp = $self->send("cont")->{return};
    bmwqemu::diag "cont $rsp\n";
}

sub do_delvm($) {
    my ( $self, $vmname ) = @_;
    $self->send("delvm $vmname");
}

# baseclass virt method overwrite end

# only valid in management thread
our $vnc;
my $mouse_xpos = 0;
my $mouse_ypos = 0;
my ( $screenshot_sec, $screenshot_usec );

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
        for my $bin ( map { '/usr/bin/' . $_ } qw/kvm qemu-kvm qemu qemu-system-x86_64 qemu-system-ppc64/ ) {
            next unless -x $bin;
            $qemubin = $bin;
            last;
        }
        die "no Qemu/KVM found\n" unless $qemubin;
    }

    my $iso = $vars->{ISO};
    # disk settings
    $vars->{NUMDISKS}  ||= 1;
    $vars->{HDDSIZEGB} ||= 10;
    $vars->{HDDMODEL}  ||= "virtio-blk";
    # network settings
    $vars->{NICMODEL}  ||= "virtio-net";
    $vars->{NICTYPE}   ||= "user";
    $vars->{NICMAC}    ||= "52:54:00:12:34:56";
    # misc
    if (!$vars->{OFW}) {
        $vars->{QEMUVGA} ||= "cirrus";
    }
    else {
        $vars->{QEMUVGA} ||= "std -g 1024x768";
    }
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
    $self->{'pid'} = fork();
    die "fork failed" if ( !defined( $self->{'pid'} ) );
    if ( $self->{'pid'} == 0 ) {
        $ENV{QEMU_AUDIO_DRV} = "none";
        my @params = ( '-m', '1024', "-serial", "file:serial0", "-soundhw", "ac97", "-global", "isa-fdc.driveA=", "-vga", $vars->{QEMUVGA});

        my $qemu_machine = '';
        if ( $vars->{QEMUMACHINE} ) {
            $qemu_machine = sprintf("type=%s,", $vars->{QEMUMACHINE});
        }
        push( @params, "-machine", "${qemu_machine}accel=kvm,kernel_irqchip=on"  );

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
            else {
                push( @params, "-cdrom", $iso );
            }
        }

        for my $i ( 1 .. 6 ) {  # check for up to 6 ADDON ISOs
            if ( $vars->{"ISO_$i"} && $vars->{"ADDONS"}) {
                my $addoniso = $vars->{"ISO_$i"};
                push( @params, "-drive", "if=ide,id=addon_$i,file=$addoniso,media=cdrom" );
            }
        }

        if ( $vars->{PXEBOOT} ) {
            push( @params, "-boot", "n");
        }
        else {
            push( @params, "-boot", "once=d,menu=on,splash-time=5000" );
        }

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
        die "exec $qemubin failed";
    }
    close $writer;
    $self->{'qemupipe'} = $reader;
    open( my $pidf, ">", $self->{'pidfilename'} ) or die "can not write " . $self->{'pidfilename'};
    print $pidf $self->{'pid'}, "\n";
    close $pidf;
    sleep 3;    # time to let qemu start

    $vnc = backend::VNC->new({hostname => 'localhost', port => 5900 + $bmwqemu::vars{VNC} });
    eval { $vnc->login; };
    if ($@) {
        $self->close_pipes();
        die $@;
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

    syswrite( $self->{'hmpsocket'}, "cont\n" );

    $self->{'select'}->add($vnc->socket);
    $self->{'select'}->add($self->{'qemupipe'});

    $vnc->send_update_request;
}

sub translate_cmd($) {
    my $cmd = shift;
    for my $knowncmd (qw(quit stop cont)) {
        if ( $cmd eq $knowncmd ) {
            return { "execute" => $cmd };
        }
    }
    return { "hmp" => $cmd };
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

use Time::HiRes qw(gettimeofday);

sub wait_for_screen_stall($) {
    my ($self, $s) = @_;

    $vnc->send_update_request;
    my ( $s1, $ms1 ) = gettimeofday;
    while (1) {
        my @ready = $s->can_read(.1);
        last unless @ready;
        for my $fh (@ready) {
            if ($fh == $self->{'qemupipe'}) {
                $self->read_qemupipe();
            }
            else {
                $vnc->receive_message();
                $self->enqueue_screenshot;
                $vnc->send_update_request;
            }
        }
        my ( $s2, $usec2 ) = gettimeofday;
        my $diff = ( $s2 - $s1 ) + ( $usec2 - $ms1 ) / 1e6;
        #bmwqemu::diag "diff $diff";
        # we can't wait longer - in password prompts there is no screen update
        last if ($diff > .8);
    }
    #my ( $s2, $usec2 ) = gettimeofday;
    #my $diff = ( $s2 - $s1 ) + ( $usec2 - $ms1 ) / 1e6;
    #bmwqemu::diag "done $diff";
    $self->enqueue_screenshot;
}

sub type_string($$) {
    my ($self, $args) = @_;
    my @letters = split( "", $args->{text} );
    my $s = IO::Select->new();
    $s->add($vnc->socket);
    $s->add($self->{'qemupipe'});

    for my $letter (@letters) {
        $letter = $self->map_letter($letter);
        $vnc->send_mapped_key($letter);
        $self->wait_for_screen_stall($s);
    }
}

sub send_key($) {
    my ($self, $args) = @_;

    bmwqemu::diag "send_mapped_key '" . $args->{key} . "'";
    $vnc->send_mapped_key($args->{key});
    my $s = IO::Select->new();
    $s->add($vnc->socket);
    $self->wait_for_screen_stall($s);
    return {};
}

sub mouse_hide {
    my ($self, $args) = @_;

    $mouse_xpos = $vnc->width - 1;
    $mouse_ypos = $vnc->height - 1;

    my $border_offset = int($args->{border_offset});
    $mouse_xpos -= $border_offset;
    $mouse_ypos -= $border_offset;

    bmwqemu::diag "mouse_move $mouse_xpos, $mouse_ypos";
    $vnc->mouse_move_to($mouse_xpos, $mouse_ypos);
    return { 'absolute' => $vnc->absolute };

}

sub mouse_set {
    my ($self, $args) = @_;

    # TODO: for framebuffers larger than 1024x768, we need to upscale
    $mouse_xpos = int($args->{x});
    $mouse_ypos = int($args->{y});

    bmwqemu::diag "mouse_set $mouse_xpos, $mouse_ypos";
    $vnc->mouse_move_to($mouse_xpos, $mouse_ypos);
    return {};
}

sub mouse_button {
    my ($self, $args) = @_;

    my $button = $args->{button};
    my $bstate = $args->{bstate};

    my $mask = 0;
    if ($button eq 'left') {
        $mask = $bstate;
    }
    elsif ($button eq 'right') {
        $mask = $bstate << 2;
    }
    elsif ($button eq 'middle') {
        $mask = $bstate << 1;
    }
    bmwqemu::diag "pointer_event $mask $mouse_xpos, $mouse_ypos";
    $vnc->send_pointer_event( $mask, $mouse_xpos, $mouse_ypos );
    return {};
}


# runs in the thread to deserialize VNC commands
sub handle_command($) {

    my ($self, $cmd) = @_;

    my $func = $cmd->{'cmd'};
    unless ($self->can($func)) {
        die "not supported command: $func";
    }
    return $self->$func($cmd->{'arguments'});
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

sub enqueue_screenshot() {
    my ($self, $image) = @_;

    $self->SUPER::enqueue_screenshot($vnc->_framebuffer);
    $vnc->send_update_request();
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

    close($vnc->socket) if ($vnc->socket);

    # one last word?
    fcntl( $self->{'qemupipe'}, Fcntl::F_SETFL, Fcntl::O_NONBLOCK );
    $self->read_qemupipe();
    close($self->{'qemupipe'});
    $self->{'qemupipe'} = undef;

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

sub do_run() {
    my ($self) = @_;

    ( $screenshot_sec, $screenshot_usec ) = gettimeofday();
    my $interval = screenshot_interval();

  SELECT: while (1) {
        my ( $s2, $usec2 ) = gettimeofday();
        my $rest = $interval - ( $s2 - $screenshot_sec ) - ( $usec2 - $screenshot_usec ) / 1e6;

        my @ready = $self->{'select'}->can_read($rest);

        if ($vnc) {
            # vnc is non-blocking so just try
            eval { $vnc->receive_message(); };
            if ($@) {
                bmwqemu::diag "VNC failed $@";
                last SELECT;
            }
            $self->enqueue_screenshot;
        }

        for my $fh (@ready) {
            my $buffer;

            if ( $fh == $self->{'cmdpipe'} ) {
                my $cmd = backend::driver::_read_json($self->{'cmdpipe'});

                #print STDERR "cmd ". JSON::to_json($cmd) . "\n";

                if ( $cmd->{hmp} ) {
                    die "HMP is obsolete";
                    my $wb = syswrite( $self->{'hmpsocket'}, "$cmd->{hmp}\n" );

                    #print STDERR "wrote HMP $wb $cmd->{hmp}\n";
                    die "syswrite failed $!" unless ( $wb == length( $cmd->{hmp} ) + 1 );

                    my $line = $self->_read_hmp;
                    print $self->{'rsppipe'},
                      JSON::to_json(
                        {
                            "hmp" => $cmd->{hmp},
                            "rsp" => { "return" => $line }
                        }
                      );
                }
                elsif ( $cmd->{cmd} ) {
                    my $rsp = $self->handle_command($cmd);
                    $self->{'rsppipe'}->print(JSON::to_json( { "rsp" => $rsp } ));
                    $self->{'rsppipe'}->print("\n");
                }
                else { # qmp

                    my $hash = $self->handle_qmp_command($cmd);
                    if ( !$hash ) {
                        print STDERR "no json from QMP: $!\n";
                        last SELECT;
                    }

                    print $self->{'rsppipe'}, JSON::to_json( { "qmp" => $cmd, "rsp" => $hash } );
                }
            }
            elsif ( $vnc && $fh == $vnc->socket) {
                # already checked
            }
            elsif ( $self->{'qemupipe'} && $fh == $self->{'qemupipe'}) {
                last SELECT unless $self->read_qemupipe();
            }
            else {
                die "huh! $fh\n";
            }
        }
    }

    $self->close_pipes();

    bmwqemu::diag( "management thread exit at " . POSIX::strftime( "%F %T", gmtime ) );
}

1;

# vim: set sw=4 et:
