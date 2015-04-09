#!/usr/bin/perl -w
package backend::s390x;

use base ('backend::vnc_backend');

use strict;
use warnings;
use English;

use Data::Dumper qw(Dumper);
use Carp qw(confess cluck carp croak);

use feature qw/say/;

use backend::s390x::s3270;

use backend::VNC;

use testapi qw(get_var check_var);

sub new {
    my $class = shift;
    my $self = bless({class => $class}, $class);
    return $self;
}

###################################################################
# create x3270 terminals, -e ssh ones and true 3270 ones.
sub new_3270_console() {
    my ($self, $s3270) = @_;
    confess "expecting hashref" unless ref $s3270 eq "HASH";
    $s3270->{s3270} = [
        qw(x3270),
        "-display", ":" . get_var("VNC"),
        qw(-script -charset us -xrm x3270.visualBell:true -xrm x3270.keypadOn:false
          -set screenTrace -xrm x3270.traceDir:.
          -trace -xrm x3270.traceMonitor:false),
        # Dark arts: ancient terminals don't have an
        # Alt key.  They usually send Esc + the key
        # instead.  FIXME: x3270 for whichever reason
        # can't send the Escape keysym, so we have to
        # hard code it here (0x1b).
        '-xrm', 'x3270.keymap.base.nvt:#replace\nAlt<Key>: Key(0x1b) Default()'
    ];
    $s3270 = new backend::s390x::s3270($s3270);
    $s3270->start();
    my $status = $s3270->send_3270()->{terminal_status};
    $status = &backend::s390x::s3270::nice_3270_status($status);
    my $console_info = {
        window_id => $status->{window_id},
        console   => $s3270
    };
    return $console_info;
}
###################################################################
# FIXME the following if (console_type eq ...) cascades could be
# rewritten using objects.
sub _new_console($$) {
    my ($self, $args) = @_;
    #CORE::say __FILE__ .':'. __LINE__ .':'. bmwqemu::pp($args);
    my ($backend_console, $console_args) = @$args{qw(backend_console backend_args)};
    my $console_info = {};
    if ($backend_console eq "s3270") {
        # my () = @console_args;
        $console_info = $self->new_3270_console(
            {
                zVM_host    => (get_var("ZVM_HOST")     // die "ZVMHOST unset in vars.json"),
                guest_user  => (get_var("ZVM_GUEST")    // die "ZVM_GUEST unset in vars.json"),
                guest_login => (get_var("ZVM_PASSWORD") // die "ZVM_PASSWORD unset in vars.json"),
            });
    }
    elsif ($backend_console =~ qr/ssh(-X)?/) {
        my $host        = get_var("PARMFILE")->{Hostname};
        my $sshpassword = get_var("PARMFILE")->{sshpassword};
        system("ssh-keygen -R $host -f ./known_hosts");
        # create s3270 console
        $console_info = $self->new_3270_console({});
        # do ssh connect
        my $s3270      = $console_info->{console};
        my $sshcommand = "TERM=vt100 ssh";
        if ($backend_console eq "ssh-X") {
            my $display = get_var("VNC") || die "VNC unset in vars.json.";
            $sshcommand = "DISPLAY=:$display " . $sshcommand . " -X";
        }
        $sshcommand .= " -o UserKnownHostsFile=./known_hosts -o StrictHostKeyChecking=no root\@$host";
        $s3270->send_3270("Connect(\"-e $sshcommand\")");
        # wait for password prompt...
        while (1) {
            $s3270->send_3270("Snap");
            my $r  = $s3270->send_3270("Snap(Ascii)");
            my $co = $r->{command_output};
            CORE::say bmwqemu::pp($r);
            CORE::say bmwqemu::pp($co);
            last if grep { /[Pp]assword:/ } @$co;
            sleep 1;
        }
        $s3270->send_3270("String(\"$sshpassword\")");
        $s3270->send_3270("ENTER");
    }
    elsif ($backend_console eq "remote-vnc") {
        my ($vncpasswd) = @$console_args;
        $self->connect_vnc(
            {
                hostname => get_var("PARMFILE")->{Hostname},
                port     => 5901,
                password => get_var("DISPLAY")->{PASSWORD},
                ikvm     => 0,
            });
        $console_info->{console} = $self->{vnc};
    }
    elsif ($backend_console eq "local-Xvnc") {
        ## start Xvnc Server, the local console to do all the work from
        my $display = get_var("VNC") || die "VNC unset in vars.json.";

        $self->{local_X_handle} = IPC::Run::start("Xvnc :$display -SecurityTypes None -ac");
        $self->connect_vnc(
            {
                hostname => "localhost",
                port     => 5900 + $display,
                ikvm     => 0
            });
        $console_info->{console} = $self->{vnc};
        $console_info->{DISPLAY} = $display;
        sleep 1;

        # magic stanza from
        # https://github.com/yast/yast-x11/blob/master/src/tools/testX.c
        system("ICEWM_PRIVCFG=/etc/icewm/yast2 DISPLAY=:$display icewm -c preferences.yast2 -t yast2 &") != -1 || warn "couldn't start icewm on :$display";
        # FIXME proper debugging viewer, also needs to be switched when
        # switching vnc console...
        system("vncviewer :$display &") != -1 || warn "couldn't start vncviewer :$display (err: $! retval: $?)";

    }
    else {
        confess "unknown backend console $backend_console";
    }
    $console_info->{args} = $args;
    return $console_info;
}

sub _select_console() {
    my ($self, $console_info) = @_;
    #CORE::say __FILE__.":".__LINE__.":".bmwqemu::pp($console_info);
    my $backend_console = $console_info->{args}->{backend_console};

    # There can be two vnc backends (local Xvnc or remote vnc) and
    # there can be several terminals on the local Xvnc.
    #
    # switching means: turn to the right vnc and if it's the Xvnc,
    # iconify/deiconify the right x3270 terminal window.
    if ($backend_console eq "s3270" || $backend_console =~ qr/ssh(-X)?/) {
        #CORE::say __FILE__.":".__LINE__.":".bmwqemu::pp($self->{current_console});
        my $current_window_id = $self->{current_console}->{window_id};
        # FIXME: do the full monty xauth authentication, with a local
        # XAUTHORITY=./XAuthority-for-testing
        #
        # There is only one DISPLAY with x3270 terminals on it: the
        # local-Xvnc aka worker one
        my $display = $self->{consoles}->{worker}->{DISPLAY};
        # FIXME: think about proper window switching for these
        # consoles...  sometimes it's itneresting to see what's going
        # on in the background.  on the other hand, on other
        # architectures, the console needs to be switched explicitely
        # in that case.
        # if (defined $current_window_id) {
        #     system("DISPLAY=:$display xdotool windowminimize --sync $current_window_id") != -1 || die;
        # }
        # set vnc to the right one...
        $self->select_console({testapi_console => "worker"});
        my $new_window_id = $console_info->{window_id};
        system("DISPLAY=:$display xdotool windowactivate --sync $new_window_id") != -1 || die;
    }
    elsif ($backend_console eq "remote-vnc" || $backend_console eq "local-Xvnc") {
        $self->{vnc} = $console_info->{console};
    }
    else {
        confess "don't know how to switch to backend console $backend_console";
    }
}

sub _delete_console($$) {
    my ($self, $console_info) = @_;
    my $backend_console = $console_info->{args}->{backend_console};
    #CORE::say __FILE__ .':'. __LINE__ .':'. bmwqemu::pp($console_info);
    if ($backend_console eq "s3270") {
        if (exists get_var("DEBUG")->{"keep zVM guest"}) {
            $console_info->{console}->cp_disconnect();
        }
        else {
            $self->{consoles}->{bootloader}->{console}->cp_logoff_disconnect();
        }
        $console_info->{console} = undef;
    }
    elsif ($backend_console eq "ssh") {
        $console_info->{console} = undef;
    }
    elsif ($backend_console eq "local-Xvnc") {
        # FIXME shut down more gracefully, some processes may still be
        # open on Xvnc.
        #IPC::Run::signal($self->{local_X_handle}, "TERM");
        IPC::Run::signal($self->{local_X_handle}, "KILL");
        IPC::Run::finish($self->{local_X_handle});
    }
    elsif ($backend_console eq "remote-vnc") {
        $self->{vnc} = undef;
    }
    else {
        confess "unknown backend console $backend_console";
    }
}
###################################################################
sub do_start_vm() {
    my ($self) = @_;

    $self->unlink_crash_file();

    $self->activate_console({testapi_console => "worker", backend_console => "local-Xvnc"});
    return 1;
}

sub do_stop_vm() {
    my ($self) = @_;

    # first kill all _remote_ consoles except for the remote zVM
    # console (which would stop the vm guest)
    for my $console (keys %{$self->{consoles}}) {
        $self->deactivate_console({testapi_console => $console})
          unless $console =~ qr/bootloader|worker/;
    }

    # now cleanly disconnect from the guest and then kill the local
    # Xvnc
    $self->deactivate_console({testapi_console => "bootloader"});
    $self->deactivate_console({testapi_console => "worker"});

}

sub do_savevm() {
    notimplemented;
}

sub do_loadvm() {
    notimplemented;
}

sub do_upload_image() {
    notimplemented;
}


1;
