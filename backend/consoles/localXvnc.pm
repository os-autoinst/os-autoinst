package backend::consoles::localXvnc;
use base 'backend::consoles::console';

use testapi qw/get_var/;

sub init() {
    my ($self) = @_;
    $self->{name} = 'local-Xvnc';
}

sub activate() {
    my ($self, $testapi_console, $console_args) = @_;
    
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

sub disable() {
        # FIXME shut down more gracefully, some processes may still be
        # open on Xvnc.
        IPC::Run::signal($self->{local_X_handle}, "TERM");
        IPC::Run::signal($self->{local_X_handle}, "KILL");
        IPC::Run::finish($self->{local_X_handle});
    }

 # override
sub select() {}

1;
