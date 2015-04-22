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

use testapi qw(get_var check_var set_var);

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
    my $display = ":" . (get_var("VNC") // die "VNC unset in vars.json.");
    $s3270->{s3270} = [
        qw(x3270),
        "-display", $display,
        qw(-script -charset us -xrm x3270.visualBell:true -xrm x3270.keypadOn:false
          -set screenTrace -xrm x3270.traceDir:.
          -trace -xrm x3270.traceMonitor:false),
        # Dark arts: ancient terminals (ansi.64, vt100) don't have an
        # Alt key.  They send Esc + the key instead.  x3270 for
        # whichever reason can't send the Escape keysym, so we have to
        # hard code it here (0x1b).
        '-xrm', 'x3270.keymap.base.nvt:#replace\nAlt<Key>: Key(0x1b) Default()'
    ];
    $s3270 = new backend::s390x::s3270($s3270);
    $s3270->start();
    my $status = $s3270->send_3270()->{terminal_status};
    $status = &backend::s390x::s3270::nice_3270_status($status);
    die "no worker Xvnc??" . bmwqemu::pp($self) unless exists $self->{consoles}->{worker};
    my $console_info = {
        window_id => $status->{window_id},
        console   => $s3270,
        vnc       => $self->{consoles}->{worker}->{vnc},
        DISPLAY   => $display,
    };
    return $console_info;
}
###################################################################
# FIXME the following if (console_type eq ...) cascades could be
# rewritten using objects.
sub _new_console($$) {
    my ($self, $args) = @_;
    #CORE::say __FILE__ . ':' . __LINE__ . ':' . (caller 0)[3];    #.':'.bmwqemu::pp($args);
    my ($testapi_console, $backend_console, $console_args) = @$args{qw(testapi_console backend_console backend_args)};
    my $console_info = {
        # vnc => the vnc for this console
        # window_id => the x11 window id, if applicable
        # DISPLAY => the x11 DISPLAY, if applicable
        # console => the console object (backend::s390x::s3270 or backend::VNC)
    };
    if ($backend_console eq "s3270") {
        die "s3270 must be named 'bootloader'" unless $testapi_console eq 'bootloader';
        # my () = @console_args;
        $console_info = $self->new_3270_console(
            {
                zVM_host    => (get_var("ZVM_HOST")     // die "ZVM_HOST unset in vars.json"),
                guest_user  => (get_var("ZVM_GUEST")    // die "ZVM_GUEST unset in vars.json"),
                guest_login => (get_var("ZVM_PASSWORD") // die "ZVM_PASSWORD unset in vars.json"),
                vnc_backend => $self,
            });
    }
    elsif ($backend_console =~ qr/ssh(-X)?(-xterm_vt)?/) {
        my $host        = get_var("PARMFILE")->{Hostname};
        my $sshpassword = get_var("PARMFILE")->{sshpassword};
        system("ssh-keygen -R $host -f ./known_hosts");
        my $sshcommand = "ssh";
        my $display_id = get_var("VNC") || die "VNC unset in vars.json.";
        my $display    = ":" . $display_id;
        if ($backend_console eq "ssh-X") {
            $sshcommand = "DISPLAY=$display " . $sshcommand . " -X";
        }
        $sshcommand .= " -o UserKnownHostsFile=./known_hosts -o StrictHostKeyChecking=no root\@$host";
        my $term_app = ($backend_console =~ qr/-xterm_vt/) ? "xterm" : "x3270";
        if ($term_app eq "x3270") {
            $sshcommand = "TERM=vt100 " . $sshcommand;
            $console_info = $self->new_3270_console({vnc_backend => $self});
            # do ssh connect
            my $s3270 = $console_info->{console};
            $s3270->send_3270("Connect(\"-e $sshcommand\")");
            # wait for 10 seconds for password prompt
            for my $i (-9 .. 0) {
                $s3270->send_3270("Snap");
                my $r  = $s3270->send_3270("Snap(Ascii)");
                my $co = $r->{command_output};
                # CORE::say bmwqemu::pp($r);
                CORE::say bmwqemu::pp($co);
                last if grep { /[Pp]assword:/ } @$co;
                die "ssh password prompt timout connecting to $host" unless $i;
                sleep 1;
            }
            $s3270->send_3270("String(\"$sshpassword\")");
            $s3270->send_3270("ENTER");
        }
        else {
            $sshcommand = "TERM=xterm " . $sshcommand;
            my $xterm_vt_cmd = "xterm-console";
            my $window_name  = "ssh:$testapi_console";
            system("DISPLAY=$display $xterm_vt_cmd -title $window_name -e bash -c '$sshcommand' & echo \$!") != -1 ||    #
              die "cant' start xterm on $display (err: $! retval: $?)";
            my $window_id = qx"DISPLAY=$display xdotool search --sync --limit 1 $window_name";
            chomp($window_id);

            $console_info->{window_id} = $window_id;
            $console_info->{vnc}       = $self->{consoles}->{worker}->{vnc};
            $console_info->{console}   = $self->{consoles}->{worker}->{vnc};
            $console_info->{DISPLAY}   = $display;
            # FIXME: capture xterm output, wait for "password:" prompt
            # possible tactics:
            # -xrm bind key print-immediate() action to some cryptic unused key combination like ctrl-alt-§
            # -xrm printerCommand: cat  or simply true
            # xdotool key ctrl-alt-§ and examine file XTerm-$TIMESTAMP (changing filename!)
            sleep 2;
            die if $sshpassword =~ /'/;
            #xterm does not accept key events by default, for security reasons, so this won't work:
            #system("DISPLAY=$display xdotool type '$sshpassword' key enter");
            die unless $console_info->{console} == $self->{vnc};
            $self->type_string({text => "$sshpassword\n"});
            sleep 10;
        }
    }
    elsif ($backend_console eq "remote-vnc") {
        my $hostname = get_var("PARMFILE")->{Hostname};
        my $password = get_var("DISPLAY")->{PASSWORD};
        $self->{vnc} = undef;    # REFACTOR see below
        $self->connect_vnc(
            {
                hostname => $hostname,
                port     => 5901,
                password => $password,
                ikvm     => 0,
            });
        $console_info->{console} = $self->{vnc};
        $console_info->{vnc}     = $self->{vnc};
        if (exists get_var("DEBUG")->{vncviewer}) {

            # start vncviewer and remember it's pid so it can be killed at exit.
            my $subshell_pid;
            {
                defined($subshell_pid = fork) or die $!;
                $subshell_pid and last;
                # FIXME if the password could come from anyhwere, this
                # echo '$password' would be a bobby tables backdoor:
                exec "echo '$password' | vncviewer -autopass $hostname:1 & echo \$! >vncviewer_pid" or die "exec failed?";
            }
            waitpid $subshell_pid, 0;
            open my $fh, '<', 'vncviewer_pid' or die $!;
            my $vncviewer_pid = do { local $/; <$fh> };
            chomp($vncviewer_pid);
            $console_info->{vncviewer_pid} = $vncviewer_pid;
            #CORE::say __FILE__ .':'. __LINE__ .':'.(caller 0)[3].':'.bmwqemu::pp($console_info);
        }
    }
    elsif ($backend_console eq "local-Xvnc") {
        # REFACTOR to have a $self->{localXvnc}
        die "local-Xvnc must be named 'worker'" unless $testapi_console eq 'worker';
        ## start Xvnc Server, the local console to do all the work from
        my $display_id = get_var("VNC") || die "VNC unset in vars.json.";
        my $display = ":" . $display_id;
        # FIXME: do the full monty xauth authentication, with a local
        # XAUTHORITY=./XAuthority file

        # On older Xvnc there is no '-listen tcp' option
        # because that's the default there; need to test Xvnc version
        # and act accordingly.
        my $Xvnc_listen_option = (scalar grep { /-listen/ } qx"Xvnc -help 2>&1") ? "-listen tcp" : "";
        $self->{local_X_handle} = IPC::Run::start("Xvnc -depth 16 $Xvnc_listen_option -SecurityTypes None -ac $display");

        # REFACTOR from connect_vnc to new_vnc, which just returns a
        # new vnc connection.  add a DESTROY to VNC which closes the
        # socket, if that's needed.  Until then we need to remove this
        # pointer to the VNC, so it's socket won't be mollested. aka:
        # shit happens when a function has side-effects, here
        # vnc_baseclass::connect_vnc will close the socket of
        # $self->{vnc}
        $self->{vnc} = undef;
        $self->connect_vnc(
            {
                hostname => "localhost",
                port     => 5900 + $display_id,
                ikvm     => 0
            });
        $console_info->{console} = $self->{vnc};
        $console_info->{DISPLAY} = $display;
        $console_info->{vnc}     = $self->{vnc};
        sleep 1;
        # FIXME proper debugging viewer, also needs to be switched when
        # switching vnc console...
        if (exists get_var("DEBUG")->{vncviewer}) {
            system("vncviewer $display &") != -1 || warn "couldn't start vncviewer $display (err: $! retval: $?)";
            system("xdotool search --sync 'TightVNC: x11'");
        }

        # magic stanza from
        # https://github.com/yast/yast-x11/blob/master/src/tools/testX.c
        system("ICEWM_PRIVCFG=/etc/icewm/yast2 DISPLAY=$display icewm -c preferences.yast2 -t yast2 &") != -1
          || die "couldn't start icewm on $display (err: $! retval: $?)";
        # FIXME robustly wait for the window manager
        sleep 2;

    }
    elsif ($backend_console eq "remote-window") {
        my ($window_name) = @$console_args;
        # This will only work on a remote X display, i.e. when
        # current_console->{DISPLAY} is set for the current console.
        # There is only one DISPLAY which we can do this with: the
        # local-Xvnc aka worker one
        my $display = $self->{consoles}->{worker}->{DISPLAY};
        # FIXME: verify the first in the list of window ids with the same name is the mothership
        my $window_id = qx"DISPLAY=$display xdotool search --sync --limit 1 $window_name";
        die if $?;
        $console_info->{window_id} = $window_id;
        $console_info->{DISPLAY}   = $display;
        $console_info->{vnc}       = $self->{consoles}->{worker}->{vnc};
        $console_info->{console}   = $self->{consoles}->{worker}->{vnc};
    }
    else {
        confess "unknown backend console $backend_console";
    }
    $console_info->{args} = $args;
    return $console_info;
}

sub _select_console() {
    my ($self, $console_info) = @_;
    #local $Devel::Trace::TRACE;
    #$Devel::Trace::TRACE = 1;
    #CORE::say __FILE__ .':'. __LINE__ .':'.(caller 0)[3].':'.bmwqemu::pp($args);

    my $backend_console = $console_info->{args}->{backend_console};

    # There can be two vnc backends (local Xvnc or remote vnc) and
    # there can be several terminals on the local Xvnc.
    #
    # switching means: turn to the right vnc and if it's the Xvnc,
    # iconify/deiconify the right x3270 terminal window.
    #
    # FIXME? for now, we just raise the terminal window to the front on
    # the local-Xvnc DISPLAY.
    #
    # should we hide the other windows, somehow?
    #if exists $self->{current_console} ...
    # my $current_window_id = $self->{current_console}->{window_id};
    # if (defined $current_window_id) {
    #     system("DISPLAY=$display xdotool windowminimize --sync $current_window_id") != -1 || die;
    # }

    if ($backend_console eq "s3270" || $backend_console =~ qr/ssh(-X)?(-xterm_vt)?/ || $backend_console eq "remote-window") {
        #CORE::say __FILE__.":".__LINE__.":".bmwqemu::pp($self->{current_console});
        my $display       = $console_info->{DISPLAY};
        my $new_window_id = $console_info->{window_id};
        #CORE::say bmwqemu::pp($console_info);
        system("DISPLAY=$display xdotool windowactivate --sync $new_window_id") != -1 || die;
    }
    elsif ($backend_console eq "remote-vnc" || $backend_console eq "local-Xvnc") {
    }
    else {
        confess "don't know how to switch to backend console $backend_console";
    }
    # always set vnc to the right one...
    $self->{vnc} = $console_info->{vnc};
    $self->capture_screenshot();
}

sub _delete_console($$) {
    my ($self, $console_info) = @_;
    my $args = $console_info->{args};
    my ($testapi_console, $backend_console) = @$args{qw(testapi_console backend_console)};
    CORE::say __FILE__ . ':' . __LINE__ . ':' . (caller 0)[3] . ':' . bmwqemu::pp($args);
    #CORE::say __FILE__ .':'. __LINE__ .':'.(caller 0)[3].':'.bmwqemu::pp($console_info);
    if ($testapi_console eq "bootloader") {
        if (exists get_var("DEBUG")->{"keep zVM guest"}) {
            $console_info->{console}->cp_disconnect();
        }
        else {
            $console_info->{console}->cp_logoff_disconnect();
        }
        # REFACTOR: DRY (same as in the next two...)
        my $window_id = $console_info->{window_id};
        my $display   = $self->{consoles}->{worker}->{DISPLAY};
        system("DISPLAY=$display xdotool windowkill $window_id") != -1 || die;
        $console_info->{console} = undef;
    }
    elsif ($backend_console =~ qr/ssh(-X)?(-xterm_vt)?/) {
        my $window_id = $console_info->{window_id};
        my $display   = $self->{consoles}->{worker}->{DISPLAY};
        system("DISPLAY=$display xdotool windowkill $window_id") != -1 || die;
        $console_info->{console} = undef;
    }
    elsif ($backend_console eq "remote-window") {
        my $window_id = $console_info->{window_id};
        my $display   = $self->{consoles}->{worker}->{DISPLAY};
        system("DISPLAY=$display xdotool windowkill $window_id") != -1 || die;
        $console_info->{console} = undef;
    }
    elsif ($backend_console eq "local-Xvnc") {
        # FIXME shut down more gracefully, some processes may still be
        # open on Xvnc.
        IPC::Run::signal($self->{local_X_handle}, "TERM");
        IPC::Run::signal($self->{local_X_handle}, "KILL");
        IPC::Run::finish($self->{local_X_handle});
    }
    elsif ($backend_console eq "remote-vnc") {
        #CORE::say __FILE__ .':'. __LINE__ .':'.(caller 0)[3].':'.bmwqemu::pp($console_info);
        if (exists $console_info->{vncviewer_pid}) {
            kill 'KILL', $console_info->{vncviewer_pid};
        }
        # FIXME? close remote socket?
        $console_info->{console} = undef;
        # FIXME: only do when {vnc} currently is "remote-vnc" (not local-Xvnc)?
        $self->{vnc} = undef;
    }
    else {
        confess "unknown backend console $backend_console";
    }
}

# cature send_key events to switch consoles on ctr-alt-fX
sub send_key {
    my ($self, $args) = @_;
    my $_map = {
        "ctrl-alt-f1" => "installation",
        "ctrl-alt-f2" => "ctrl-alt-f2",
        "ctrl-alt-f3" => "ctrl-alt-f2",
        "ctrl-alt-f4" => "ctrl-alt-f2",
        "ctrl-alt-f7" => "installation",
        "ctrl-alt-f9" => "ctrl-alt-f2",
    };
    if ($args->{key} =~ qr/^ctrl-alt-f(\d+)/i) {
        die "unkown ctrl-alt-fX combination $args->{key}" unless exists $_map->{$args->{key}};
        $self->select_console({testapi_console => $_map->{$args->{key}}});
        return;
    }
    return $self->SUPER::send_key($args);
}
###################################################################
sub do_start_vm() {
    my ($self) = @_;

    $self->unlink_crash_file();
    $self->inflate_vars_json();
    $self->activate_console({testapi_console => "worker", backend_console => "local-Xvnc"});
    return 1;
}

# input from the worker in vars.json:
#     "S390_CONSOLE" : "vnc",
#     "S390_HOST" : "153",
#     "S390_NETWORK" : "hsi-l3",
#     "REPO_0" : "SLES-11-SP4-DVD-s390x-Build1050-Media1",
# when not invoked from the worker (no WORKER_CLASS set), these need
# to be set, too:
#     "S390_INSTHOST": "dist",
#     "S390_INSTSRC": "http",
# output: a full-featured vars.json suitable for s390 testing
sub inflate_vars_json {
    my ($self) = @_;

    # these vars have to be set in vars.json:
    die unless defined get_var('S390_HOST');
    die unless defined get_var('S390_NETWORK');
    die unless defined get_var('S390_CONSOLE');
    die unless defined get_var('REPO_0');
    # when called from the openqa worker, these two vars are not set
    # yet:
    if (defined get_var('WORKER_CLASS')) {
        die if defined get_var('S390_INSTHOST');
        die if defined get_var('S390_INSTSRC');
        set_var("S390_INSTHOST", "openqa");
        # FIXME: this should become a parameter in the future, too.
        # only ftp is implemented so far on openqa.suse.de
        set_var("S390_INSTSRC", "ftp");
        bmwqemu::save_vars();
    }
    else {
        die unless defined get_var('S390_INSTHOST');
        die unless defined get_var('S390_INSTSRC');
    }

    # use external script to inflate vars.json
    my $vars_json_cmd = $bmwqemu::scriptdir . "/backend/s390x/vars.json.py";

    system("$vars_json_cmd > vars.json.$$") != -1 || die "vars_json transform failed $?";
    system("mv vars.json.$$ vars.json") != -1 || die;

    bmwqemu::load_vars();
    bmwqemu::expand_DEBUG_vars();
    bmwqemu::save_vars();
}

sub do_stop_vm() {
    my ($self) = @_;

    # first kill all _remote_ consoles except for the remote zVM
    # console (which would stop the vm guest)
    my @consoles = keys %{$self->{consoles}};
    for my $console (@consoles) {
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
sub init_charmap($) {
    my ($self) = (@_);

    ## charmap (like L => shift+l)
    # see http://en.wikipedia.org/wiki/IBM_PC_keyboard
    $self->{charmap} = {
        # minus is special as it splits key combinations
        "-" => "minus",

        "\t" => "tab",
        "\n" => "ret",
        "\b" => "backspace",

        "\e" => "esc"
    };
    ## charmap end
}
1;
