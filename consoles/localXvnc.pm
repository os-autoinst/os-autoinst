# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::localXvnc;

use Mojo::Base -strict, -signatures;
use autodie ':all';

use base 'consoles::vnc_base';

use IPC::Run ();
require IPC::System::Simple;
use Socket;
use File::Path 'mkpath';
use File::Which;
use Time::Seconds;

our $xterm_vt = 'xterm-console';

# helper function
# Keep ssh session for the maximum of ServerAliveCountMax x ServerAliveInterval seconds
# even without receiving any message back from the server, and this will not affect normal
# ssh disconnect and console switching. Ssh console may not display returned result of
# long-time run test without these options. TCPKeepAlive ensures that if network goes down
# or the remote host dies, machines will be properly noticed
sub sshCommand ($self, $username, $host, $gui = undef) {
    my $server_alive_count_max = $bmwqemu::vars{_SSH_SERVER_ALIVE_COUNT_MAX} // 480;
    my $server_alive_interval = $bmwqemu::vars{_SSH_SERVER_ALIVE_INTERVAL} // ONE_MINUTE;
    my $sshopts = "-o TCPKeepAlive=yes -o ServerAliveCountMax=$server_alive_count_max -o ServerAliveInterval=$server_alive_interval -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PubkeyAuthentication=no $username\@$host";
    $sshopts = "-X $sshopts" if $gui;
    return "ssh $sshopts; read";
}

sub callxterm ($self, $command, $window_name) {
    my $display = $self->{DISPLAY};
    $command = "TERM=xterm $command";
    my $xterm_vt_cmd = which $xterm_vt;
    die "Missing '$xterm_vt'" unless $xterm_vt_cmd;
    die('Missing "Xvnc"') unless which('Xvnc');
    die('Missing "icewm"') unless which('icewm');
    die('Missing "xterm"') unless which('xterm');
    if ($self->{args}->{log}) {
        mkpath 'ulogs';
        $command = "script -f ulogs/hardware-console-log.txt -c \"$command\"";
    }
    system("DISPLAY=$display $xterm_vt_cmd -title $window_name -e bash -c '$command' & echo \"xterm PID is \$!\"");
}

sub fullscreen ($self, $args) {
    my $display = $self->{DISPLAY};
    my $window_name = $args->{window_name};

    my $xdotool = which "xdotool";
    die "Missing 'xdotool'" unless $xdotool;

    # search for YaST Window and grab the id
    my $window_id = qx"DISPLAY=$display $xdotool search --sync --limit 1 --name $window_name";
    $window_id =~ s/\D//g;

    # resize and move window to fit in icewm
    system("DISPLAY=$display $xdotool windowsize $window_id 100% 100%");
    system("DISPLAY=$display $xdotool windowmove $window_id 0 0");
}

sub activate ($self) {
    # start Xvnc on a random high port and use that port also as $DISPLAY

    my $tcpproto = getprotobyname('tcp');
    my $s;
    socket($s, PF_INET, SOCK_STREAM, $tcpproto) || die "socket: $!\n";
    bind($s, sockaddr_in(0, INADDR_ANY));
    my ($port) = sockaddr_in(getsockname($s));

    my $display = ":$port";
    my $pid = fork();
    die unless defined $pid;
    if (!$pid) {
        listen($s, 1);
        my $peer;
        accept($peer, $s);
        close($s);
        open(STDIN, "<&", $peer);
        open(STDOUT, ">&", $peer);
        close($peer);
        exec("Xvnc -depth 16 -inetd -SecurityTypes None -ac $display");
    }
    close($s);

    $self->connect_remote(
        {
            hostname => "localhost",
            port => $port,
            ikvm => 0
        });
    bmwqemu::diag("Connected to Xvnc - PID $pid");
    $self->{DISPLAY} = $display;
    sleep 1;

    # we need a window manager for fullscreen apps to work
    system("DISPLAY=$display icewm -c $bmwqemu::scriptdir/consoles/icewm.cfg & echo \"icewm PID is \$!\"");
    return;
}

sub disable ($self) {
    return unless $self->{local_X_handle};

    # We could shut down more gracefully, some processes may still be open on
    # Xvnc.
    IPC::Run::signal($self->{local_X_handle}, 'TERM');
    IPC::Run::signal($self->{local_X_handle}, 'KILL');
    IPC::Run::finish($self->{local_X_handle});
    $self->{local_X_handle} = undef;
    return;
}

sub DESTROY ($self) {
    $self->disable();
    return;
}

1;
