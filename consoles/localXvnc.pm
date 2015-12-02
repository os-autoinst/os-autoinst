package consoles::localXvnc;
use base 'consoles::vnc_base';
use strict;
use warnings;
use IPC::Run ();

use testapi qw/get_var/;
require IPC::System::Simple;
use autodie qw(:all);
use Socket;
use strict;
use warnings;

sub activate {
    my ($self) = @_;

    # start Xvnc on a random high port and use that port also as $DISPLAY

    my $tcpproto = getprotobyname('tcp');
    my $s;
    socket($s, PF_INET, SOCK_STREAM, $tcpproto) || die "socket: $!\n";
    bind($s, sockaddr_in(0, INADDR_ANY));
    my ($port) = sockaddr_in(getsockname($s));

    my $display = ":$port";
    my $pid     = fork();
    die unless defined $pid;
    if (!$pid) {
        listen($s, 1);
        my $peer;
        accept($peer, $s);
        close($s);
        open(STDIN,  "<&", $peer);
        open(STDOUT, ">&", $peer);
        close($peer);
        exec("Xvnc -depth 16 -inetd -SecurityTypes None -ac $display");
    }
    close($s);
    print "$self->{testapi_console} -> $port\n";

    $self->connect_vnc(
        {
            hostname => "localhost",
            port     => $port,
            ikvm     => 0
        });
    $self->{DISPLAY} = $display;
    sleep 1;

    return;
}

sub disable {
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

sub DESTROY {
    my $self = shift;
    $self->disable();
    return;
}

1;
