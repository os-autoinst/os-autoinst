#!/usr/bin/perl -w

# this module provides a testing backend using the Epiphan kvm2usb device
# to capture VGA from another physical machine and PS2/USB keyboard
# to send keystrokes for automated actions
# with some power switch integration

# needs EDID uploaded once to the kvm2usb using
# cd epiphan_sdk-3.28.0.0009/epiphan/samples/v2u_edid && make &&
# build/release/v2u_edid /PATHTO/os-autoinst/backend/extras/edid_1024x768.edid

package backend::kvm2usb;
use strict;

#use FindBin;
#use lib "$FindBin::Bin/backend";
use YAML;
use POSIX ":sys_wait_h";    # for WNOHANG in waitpid()
use IO::Socket::SSL;
use File::Temp;
use constant { SCHAR_MAX => 127, SCHAR_MIN => -127 };
use base ( 'backend::helper::scancodes', 'backend::baseclass' );

use bmwqemu qw(diag);

sub init() {
    my $self = shift;
    $self->{'hardware'} = YAML::LoadFile("/etc/os-autoinst/kvm2usb.yml")->{ $bmwqemu::vars{'HWSLOT'} };
    unless ( defined $self->{'hardware'} ) {
        die "Error: Hardware slot '" . $bmwqemu::vars{'HWSLOT'} . "' is not defined!\n";
    }
    $self->{'isalive'}        = 0;
    $self->{'isscreenactive'} = 0;
    $self->{'mousebutton'}    = { 'left' => 0, 'right' => 0 };
    $self->backend::helper::scancodes::init();
}

sub post_start_hook($) {
    my $self = shift; # ignored in base
    inst::screenshot::start_screenshot_thread($self);
}

# scancode virt method overwrite

sub keycode_down($) {
    my $self     = shift;
    my $key      = shift;
    my $scancode = $self->{'keymaps'}->{'kvm2usb'}->{$key};

    # first element str
    if ( ( $scancode >> 8 ) != 0 ) {
        return ( 0x02, $scancode >> 8, $scancode & 0xFF );
    }
    return ( 0x01, $scancode );
}

sub keycode_up($) {
    my $self     = shift;
    my $key      = shift;
    my $scancode = $self->{'keymaps'}->{'kvm2usb'}->{$key};
    if ( ( $scancode >> 8 ) != 0 ) {
        return ( 0x03, $scancode >> 8, 0xF0, $scancode & 0xFF );
    }
    return ( 0x02, 0xF0, $scancode );
}

sub raw_keyboard_io($) {
    my $self = shift;
    my $data = shift;
    $self->raw_ps2_io( 1, $data );
}

# scancode virt method overwrite end

sub raw_mouse_io($) {
    my $self = shift;

    # delta value for cursor movement
    # button l&r - 1=pressed
    # oh and: 0x0 is top left, in here
    # and the bottom right is 512x384
    # RELATIVE to 0x0 (at least in yast with 1024x768)
    my ( $dx, $dy, $bl, $br ) = @_;

    # upper left should be 0x0
    $dy = -$dy;
    my $data = [
        3,      # number of bytes in PS/2 packet
        0x08    #bit3 must be set
          | ( $dx >= 0 ? 0    : 0x10 ) | ( $dy >= 0 ? 0    : 0x20 )    # signs for dx,dy
          | ( $bl      ? 0x01 : 0 ) |    ( $br      ? 0x02 : 0 ),      # left, right buttons flags
        $dx > SCHAR_MAX ? SCHAR_MAX : ( $dx < SCHAR_MIN ? SCHAR_MIN : $dx ),
        $dy > SCHAR_MAX ? SCHAR_MAX : ( $dy < SCHAR_MIN ? SCHAR_MIN : $dy )
    ];

    #print join(',', @$data)."\n";
    $self->raw_ps2_io( 2, $data );
}

# baseclass virt method overwrite

sub mouse_move($$) {
    my ( $self, $dx, $dy ) = @_;
    while ( $dx ne 0 or $dy ne 0 ) {
        my $dx_jump = $dx > SCHAR_MAX ? SCHAR_MAX : ( $dx < SCHAR_MIN ? SCHAR_MIN : $dx );
        my $dy_jump = $dy > SCHAR_MAX ? SCHAR_MAX : ( $dy < SCHAR_MIN ? SCHAR_MIN : $dy );
        $self->raw_mouse_io( $dx_jump, $dy_jump, $self->{'mousebutton'}->{'left'}, $self->{'mousebutton'}->{'right'} );
        $dx -= $dx_jump;
        $dy -= $dy_jump;
    }
}

sub mouse_set($$) {
    my ( $self, $x, $y ) = @_;

    # let's see how far this will work...
    # ... assuming bottom right is 0x0 + 512x384
    # set cursor to 0x0
    $self->mouse_move( -1000, -1000 );
    my ( $rx, $ry, undef ) = $self->raw_get_videomode();
    my $dx = int( $x / $rx * 512 );
    my $dy = int( $y / $ry * 384 );
    $self->mouse_move( $dx, $dy );
}

sub mouse_hide(;$) {
    my $self = shift;
    my $border_offset = shift || 0;
    $self->mouse_move( 2000, 2000 );
    if ($border_offset) {

        # not completely in the corner to not trigger hover actions
        $self->mouse_move( -20, -20 );
    }
}

sub screendump($) {
    my $self = shift;
    my $tmp = File::Temp->new( UNLINK => 0, SUFFIX => '.ppm', OPEN => 0 );

    # streamer -q -c /dev/video0 -o out.ppm
    my $pid = fork();
    if ( $pid == 0 ) {
        open( STDERR, ">/dev/null" );
        exec( 'streamer', '-q', '-c', $self->{'hardware'}->{'video'}, '-o', $tmp ) or die;
    }
    else {
        waitpid( $pid, 0 );
        $self->{'isscreenactive'} = ( ( $? >> 8 ) == 0 );
        if ( $self->{'isscreenactive'} ) {
            my $ret = tinycv::read($tmp);
            unlink $tmp;
            return $ret;
        }
        unlink $tmp;
    }
    return undef;
}

sub start_audiocapture($) {
    my $self        = shift;
    my $wavfilename = shift;
    if ( $self->{'hardware'}->{'sound'} eq 'null' ) {

        # skip null interface as it gives you 500MB of data per second
        bmwqemu::diag("audiocapture: Skipping capture on 'null' audio interface");
        return;
    }
    my $pid = fork();
    if ( $pid == 0 ) {
        exec( qw"arecord -r44100 -c1 -f S16_LE -D", $self->{'hardware'}->{'sound'}, $wavfilename );
        die "exec failed $!";
    }
    else {
        $self->{'arecordpid'} = $pid;
    }
}

sub stop_audiocapture($) {
    my $self = shift;
    return unless defined $self->{'arecordpid'};
    kill( 15, $self->{'arecordpid'} );
    sleep 1;
    waitpid( $self->{'arecordpid'}, WNOHANG );
}

sub insert_cd($) {
    my $self = shift;
    my $iso  = shift;
    if ( $self->{'hardware'}->{'cdrom'} eq 'ilo' ) {
        $iso =~ s#.*/iso/#/#;

        #TODO: move this url to some config
        my $isourl  = 'http://autoinst.qa.suse.de:8080' . $iso;
        my $ilo_xml = '<RIB_INFO MODE="write">' . '<INSERT_VIRTUAL_MEDIA DEVICE="CDROM" IMAGE_URL= "' . $isourl . '" />' . '<SET_VM_STATUS DEVICE="CDROM">' . '<VM_BOOT_OPTION value="CONNECT" /><VM_WRITE_PROTECT value="Y" />' . '</SET_VM_STATUS>' . '</RIB_INFO>';
        $self->eject_cd();
        sleep(1);
        $self->raw_ilo_request($ilo_xml);
    }
    else {
        warn "No cdrom backend!\n";
    }
}

sub eject_cd() {
    my $self = shift;
    if ( $self->{'hardware'}->{'cdrom'} eq 'ilo' ) {
        my $ilo_xml = '<RIB_INFO MODE="write">' . '<EJECT_VIRTUAL_MEDIA DEVICE="CDROM" />' . '</RIB_INFO>';
        $self->raw_ilo_request($ilo_xml);
    }
    else {
        warn "No cdrom backend!\n";
    }
}

sub power($) {

    # parameters:
    # acpi, reset, on, off
    my $self   = shift;
    my $action = shift;
    if ( $self->{'hardware'}->{'power'}->{'type'} eq 'ilo' ) {
        if ( $action eq 'reset' ) {
            $self->power('on');
            sleep 1;
        }
        $self->raw_power_ilo($action);
    }
    elsif ( $self->{'hardware'}->{'power'}->{'type'} eq 'snmp' ) {
        if ( $action eq 'reset' ) {
            $self->raw_power_snmp('off');
            sleep(4);
            $self->raw_power_snmp('on');
        }
        else {
            $self->raw_power_snmp($action);
        }
    }
    elsif ( $self->{'hardware'}->{'power'}->{'type'} eq 'usbnetpower' ) {
        $action =~ s/reset/cycle/;
        if ( $action eq "acpi" ) { warn "unsupported $action power action" }
        system( "usbnetpower8800", $action );
    }
    else {
        warn "Unsupported power type: $self->{'hardware'}->{'power'}->{'type'}";
    }
}

sub raw_alive($) {
    my $self = shift;
    return $self->{'isalive'};
}

sub get_backend_info($) {
    my $self = shift;
    return {
        'hwslot'  => $bmwqemu::vars{'HWSLOT'},
        'hw_info' => $self->{'hardware'}->{'info'}
    };
}

sub do_start_vm {
    my $self = shift;
    $self->raw_set_capture_params();
    print STDOUT "Inserting CD: $bmwqemu::vars{ISO}\n";
    $self->insert_cd( $bmwqemu::vars{ISO} );
    sleep(1);
    print STDOUT "Power reset $bmwqemu::vars{'HWSLOT'}\n";
    $self->power('reset');
    sleep(5);
    $self->start_serial_grab();
    $self->{'isalive'} = 1;
}

sub do_stop_vm {
    my $self = shift;
    $self->stop_serial_grab();
    $self->{'isalive'} = 0;
}

sub stop {
    print STDOUT "stop=NOP\n";
}

sub cont {
    print STDOUT "cont=NOP\n";
}

sub do_savevm($) {
    print STDOUT "do_savevm=NOP\n";
}

sub do_loadvm($) {
    print STDOUT "do_loadvm=NOP\n";
}

# baseclass virt method overwrite end

sub screenactive($) {
    my $self = shift;
    return $self->{'isscreenactive'};
}

# ioctl

sub raw_ps2_io($) {
    my $self   = shift;
    my $addr   = shift;    # 1=keyb 2=mouse
    my $data   = shift;
    my $length = @$data;
    no warnings;

    # mouse bytes are signed and will be wrapped to unsigned
    # this is also done in c-reference implementation...
    my $sendstr = pack( "SSC*", $addr, $length, @$data );
    use warnings;
    open( my $fd, "+>", $self->{'hardware'}->{'ctldev'} ) or die $!;
    ioctl( $fd, 0x40445610, $sendstr ) or print "Error: sending PS2 sequence to '" . $self->{'hardware'}->{'ctldev'} . "' failed!\n";
    close($fd);
}

sub raw_set_capture_params($) {
    my $self    = shift;
    my $confp   = $self->{'hardware'}->{'grab_params'};
    my $h       = shift || $confp->{'hshift'};                                                                                                               # value -255,255
    my $v       = shift || $confp->{'vshift'};                                                                                                               # value -255,255
    my $gain    = shift || $confp->{'gain'};                                                                                                                 # value 0,255
    my $offset  = shift || $confp->{'offset'};                                                                                                               # value 0,63
    my $phase   = shift || $confp->{'phase'};                                                                                                                # value 0,31
    # 0,0 seems to mean auto - but fixed seems to work better...
    # change flags: hshift: 0x0001, phase: 0x0002, offset/gain: 0x0004, vshift: 0x0008
    my $sendstr = pack( "LlCCCCCCCCllLL", 0x0001 | 0x0002 | 0x0004 | 0x0008, $h, $phase, $gain, $gain, $gain, $offset, $offset, $offset, 0, $v, 0, 0, 0 );
    open( my $fd, "+>", $self->{'hardware'}->{'ctldev'} ) or die $!;
    ioctl( $fd, 0x40205608, $sendstr ) or print "Error: setting capture parameters via '" . $self->{'hardware'}->{'ctldev'} . "' failed!\n";
    close($fd);

}

sub raw_get_videomode($) {
    my $self = shift;
    my $vmode_packed = pack( 'lll', 0, 0, 0 );
    open( my $fd, "+>", $self->{'hardware'}->{'ctldev'} ) or die $!;
    ioctl( $fd, 0x800C5609, $vmode_packed ) or print "Error: getting videomode via '" . $self->{'hardware'}->{'ctldev'} . "' failed!\n";
    close($fd);
    my @videomode = unpack( 'lll', $vmode_packed );

    # mHz -> Hz
    $videomode[2] /= 1000;

    # returns array(width,height,refresh_rate)
    return @videomode;
}

# ioctl end

# snmp / bmc

sub raw_power_snmp($) {

    # parameter: on, off
    my $self     = shift;
    my $power    = shift;
    my $newvalue = ( $power eq 'on' ) ? $self->{'hardware'}->{'power'}->{'snmp'}->{'on_value'} : $self->{'hardware'}->{'power'}->{'snmp'}->{'off_value'};
    my $ports    = $self->{'hardware'}->{'power'}->{'snmp'}->{'ports'};
    require Net::SNMP;
    my ( $session, $error ) = Net::SNMP->session(
        -hostname  => $self->{'hardware'}->{'power'}->{'snmp'}->{'host'},
        -community => $self->{'hardware'}->{'power'}->{'snmp'}->{'community'}
    );
    if ( !defined $session ) {
        printf "ERROR: %s.\n", $error;
    }
    for my $power_port (@$ports) {
        my $result = $session->set_request( -varbindlist => [ $self->{'hardware'}->{'power'}->{'snmp'}->{'base_mib'} . $power_port, Net::SNMP::INTEGER(), $newvalue ] );
        if ( !defined $result ) {
            printf "ERROR: %s.\n", $session->error();
        }
    }
    $session->close();
}

sub raw_power_ilo($) {
    my $self   = shift;
    my $action = shift;
    my $xcmd   = '';
    if ( $action eq 'acpi' ) {
        if ( $self->raw_ilo_request('<SERVER_INFO MODE="read"><GET_HOST_POWER_STATUS/></SERVER_INFO>') =~ m/HOST_POWER="ON"/ ) {
            $xcmd = '<PRESS_PWR_BTN/>';
        }
    }
    elsif ( $action eq 'on' ) {
        if ( $self->raw_ilo_request('<SERVER_INFO MODE="read"><GET_HOST_POWER_STATUS/></SERVER_INFO>') =~ m/HOST_POWER="OFF"/ ) {
            $xcmd = '<PRESS_PWR_BTN/>';
        }
    }
    elsif ( $action eq 'reset' ) {
        $xcmd = '<RESET_SERVER/>';
    }
    elsif ( $action eq 'off' ) {
        $xcmd = '<HOLD_PWR_BTN/>';
    }
    return if ( $xcmd eq '' );
    my $ilo_xml = '<SERVER_INFO MODE="write">' . $xcmd . '</SERVER_INFO>';

    #print $ilo_xml."\n";
    $self->raw_ilo_request($ilo_xml);
}

sub raw_ilo_request($) {
    my $self    = shift;
    my $ilo_xml = shift;
    my $ihost   = $self->{'hardware'}->{'ilo'}->{'host'};
    my $iuser   = $self->{'hardware'}->{'ilo'}->{'user'};
    my $ipass   = $self->{'hardware'}->{'ilo'}->{'pass'};
    $ihost .= ":443" unless ( $ihost =~ m/:/ );
    my $iclient = new IO::Socket::SSL->new( PeerAddr => $ihost );
    if ( !$iclient ) { print "ERROR: Failed to establish ILO SSL connection with $ihost.\n"; }

    print $iclient '<?xml version="1.0"?>' . "\r\n";
    print $iclient '<RIBCL VERSION="2.0"><LOGIN USER_LOGIN="' . $iuser . '" PASSWORD="' . $ipass . '">' . $ilo_xml . '</LOGIN></RIBCL>' . "\r\n";
    my $out_xml = '';
    while ( my $ln = <$iclient> ) {
        last if ( length($ln) == 0 );

        # This isn't really required, but it makes the output look nicer
        $ln =~ s/<\/RIBCL>/<\/RIBCL>\n/g;
        $out_xml .= $ln . "\n";

        #print $ln;
    }
    close($iclient);
    return $out_xml;
}

# snmp / bmc end

# serial grab

sub start_serial_grab() {
    my $self = shift;

    # kill all dd's on the same tty
    my $ddpidlist = `pidof dd`;
    if ( defined $ddpidlist and $ddpidlist ne "" ) {
        my @pids = split( " ", $ddpidlist );
        foreach my $pid (@pids) {
            my $ddtty = readlink("/proc/$pid/fd/0");
            if ( $ddtty eq $self->{'hardware'}->{'serial'} ) {
                kill( 15, int($pid) );
            }
        }
    }

    my $pid = fork();
    if ( $pid == 0 ) {

        # ensure 115200 baud
        system( 'stty', '-F', $self->{'hardware'}->{'serial'}, '-echo', '-echoprt', '115200' );
        exec( "dd", "if=" . $self->{'hardware'}->{'serial'}, "of=" . $bmwqemu::serialfile, "bs=1" );
        die "exec failed $!";
    }
    else {
        $self->{'serialpid'} = $pid;
    }
}

sub stop_serial_grab($) {
    my $self = shift;
    kill( 15, $self->{'serialpid'} );
    sleep 1;
    waitpid( $self->{'serialpid'}, WNOHANG );
}

# serial grab end

1;
# vim: set sw=4 et:
