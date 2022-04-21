# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::localXvnc;

use Mojo::Base 'consoles::vnc_base', -signatures;
use autodie ':all';
use IPC::Run ();
require IPC::System::Simple;
use Socket;
use File::Path 'mkpath';
use File::Which;
use Time::Seconds;

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
    my $xterm_vt_cmd = which "xterm-console";
    die "Missing 'xterm-console'" unless $xterm_vt_cmd;
    die('Missing "Xvnc"') unless which('Xvnc');
    die('Missing "icewm"') unless which('icewm');
    die('Missing "xterm"') unless which('xterm');
    if ($self->{args}->{log}) {
        mkpath 'ulogs';
        $command = "script -f ulogs/hardware-console-log.txt -c \"$command\"";
    }
    eval { system("DISPLAY=$display $xterm_vt_cmd -title $window_name -e bash -c '$command' & echo \"xterm PID is \$!\""); };
    die "cant' start xterm on $display (err: $! retval: $?)" if $@;
}

sub fullscreen ($self, $args) {
    my $display = $self->{DISPLAY};
    my $window_name = $args->{window_name};

    my $xdotool = $ENV{OS_AUTOINST_XDOTOOL} // which "xdotool";
    die "Missing 'xdotool'" unless $xdotool;

    # search for YaST Window and grab the id
    my $window_id = qx"DISPLAY=$display $xdotool search --sync --onlyvisible --name $window_name";
    $window_id =~ s/\D//g;

    # resize and move window to fit in icewm
    system("DISPLAY=$display $xdotool windowsize $window_id 100% 100%");
    system("DISPLAY=$display $xdotool windowmove $window_id 0 0");
}

# uncoverable statement count:1
# uncoverable statement count:2
# uncoverable statement count:3
# uncoverable statement count:4
sub start_xvnc ($s, $display) {
    listen($s, 1);    # uncoverable statement
    my $peer;    # uncoverable statement
    accept($peer, $s);    # uncoverable statement
    close($s);    # uncoverable statement
    open(STDIN, "<&", $peer);    # uncoverable statement
    open(STDOUT, ">&", $peer);    # uncoverable statement
    close($peer);    # uncoverable statement
    exec("Xvnc -depth 16 -inetd -SecurityTypes None -ac $display");    # uncoverable statement
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
    start_xvnc($s, $display) unless $pid;
    close($s);

    my $vnc = $self->connect_remote({hostname => 'localhost', port => $port, ikvm => 0, description => 'local Xvnc'});
    # disable checking VNC stalls as this setup would not survive re-connects triggered by the VNC stall
    # detection anyways (as Xvnc terminates itself when the connection is closed)
    # note: Otherwise jobs are failing with "Error connecting to VNC server localhost … Connection refused"
    #       (see poo#105882).
    $vnc->check_vnc_stalls(0);
    bmwqemu::diag("Connected to Xvnc - PID $pid");
    $self->{DISPLAY} = $display;
    sleep 1;

    # we need a window manager for fullscreen apps to work
    system("DISPLAY=$display icewm -c $bmwqemu::scriptdir/consoles/icewm.cfg & echo \"icewm PID is \$!\"");
    return;
}

1;
