package consoles::localXvnc;
use base 'consoles::vnc_base';
use strict;
use warnings;
use IPC::Run ();

use testapi qw/get_var/;
require IPC::System::Simple;
use autodie qw(:system);

sub init() {
    my ($self) = @_;
    $self->SUPER::init();
    # overwrite name
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

    $self->connect_vnc(
        {
            hostname => "localhost",
            port     => 5900 + $display_id,
            ikvm     => 0
        });
    $self->{DISPLAY} = $display;
    sleep 1;

    # magic stanza from
    # https://github.com/yast/yast-x11/blob/master/src/tools/testX.c
    system("ICEWM_PRIVCFG=/etc/icewm/yast2 DISPLAY=$display icewm -c preferences.yast2 -t yast2 &");
    # FIXME robustly wait for the window manager
    sleep 2;
    return;
}

sub disable() {
    my ($self) = @_;

    return unless $self->{local_X_handle};

    # FIXME shut down more gracefully, some processes may still be
    # open on Xvnc.
    IPC::Run::signal($self->{local_X_handle}, 'TERM');
    IPC::Run::signal($self->{local_X_handle}, 'KILL');
    IPC::Run::finish($self->{local_X_handle});
    $self->{local_X_handle} = undef;
    return;
}

# override
sub select() { return; }

sub DESTROY {
    my $self = shift;
    $self->disable();
    return;
}

1;
