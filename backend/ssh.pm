# Copyright © 2018 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package backend::ssh;
use strict;
use base 'backend::baseclass';
use testapi qw(get_required_var set_var get_var);
use Carp 'cluck';
use Mojo::IOLoop::ReadWriteProcess 'process';
use IO::Select;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new;

    return $self;
}

sub do_start_vm {
    my ($self) = @_;

    my $hostname = get_required_var('SSH_HOSTNAME');
    my $password = get_required_var('SSH_PASSWORD');
    my $username = get_var('SSH_USERNAME', 'root');
    my $port     = get_var('SSH_PORT', '22');

    # truncate the serial file
    open(my $sf, '>', $self->{serialfile});
    close($sf);

    my $ssh_console = $testapi::distri->add_console(
        'sut',
        'ssh_console',
        {
            hostname => $hostname,
            password => $password,
            username => $username,
            port     => $port
        });
    $ssh_console->backend($self);
    $self->select_console({testapi_console => 'sut'});

    $self->start_reverse_tunnel;

    my $chan = $self->start_ssh_serial(
        hostname => $hostname,
        password => $password,
        username => $username,
        port     => $port
    );
    return {};
}

sub start_reverse_tunnel {
    my ($self) = @_;

    my $workerport = get_required_var("QEMUPORT") + 1;
    my $hostname   = get_required_var('SSH_HOSTNAME');
    my $password   = get_required_var('SSH_PASSWORD');
    my $username   = get_var('SSH_USERNAME', 'root');
    my $port       = get_var('SSH_PORT', '22');

    my $fwd_process = process(sub {
            my $ssh = $self->new_ssh_connection(
                hostname => $hostname,
                password => $password,
                username => $username,
                port     => $port
            ) || die($@);

            # FIXME allow simultaneous connections
            my $l = $ssh->listen($workerport);
            while (1) {
                $ssh->blocking(1);
                my $channel = $l->accept();
                last unless (defined($channel));
                $ssh->blocking(0);

                my $socket = IO::Socket::INET->new(
                    PeerHost => '127.0.0.1',
                    PeerPort => $workerport,
                    Proto    => 'tcp',
                );
                if ($socket) {
                    my $buf = '';
                    my $len = 512;
                    my $s   = IO::Select->new();
                    $s->add($socket);
                    while (1) {
                        last if ($channel->eof);
                        while (sysread($channel, $buf, $len)) {
                            last unless syswrite($socket, $buf);
                        }
                        if ($s->can_read(0.1)) {
                            last unless sysread($socket, $buf, $len);
                            last unless syswrite($channel, $buf);
                        }
                    }
                    $socket->close();
                }
                $channel->close();
            }
    })->blocking_stop(1)->start;
    $fwd_process->on(stop => sub { bmwqemu::diag("SSH Tunnel " . (shift->pid) . " finished"); });
    $self->{fwd_process} = $fwd_process;
}

sub do_stop_vm {

    my ($self) = @_;

    $self->stop_ssh_serial;
    $self->deactivate_console({testapi_console => 'sut'});
    if ($self->{fwd_process}) {
        $self->{fwd_process}->stop();
    }

    return {};
}

# In list context returns pair ($stdout, $stderr). In void (and scalar)
# context just logs stdout and stderr, returns nothing.
# TODO used from svirt.pm, move to baseclass?!
sub get_ssh_output {
    my ($chan) = @_;

    my ($stdout, $errout) = ('', '');
    while (!$chan->eof) {
        if (my ($o, $e) = $chan->read2) {
            $stdout .= $o;
            $errout .= $e;
        }
    }
    if (wantarray) {
        return ($stdout, $errout);
    }
    else {
        bmwqemu::diag "Command's stdout:\n$stdout" if length($stdout);
        bmwqemu::diag "Command's stderr:\n$errout" if length($errout);
    }
}

# TODO used from svirt.pm, move to baseclass?!
sub run_cmd {
    my ($self, $cmd, $hostname, $password, $username) = @_;

    $hostname //= get_required_var('SSH_HOSTNAME');
    $password //= get_required_var('SSH_PASSWORD');
    $username //= get_required_var('SSH_USERNAME', 'root');

    $self->{ssh} = $self->new_ssh_connection(
        hostname => $hostname,
        password => $password,
        username => $username
    ) unless defined($self->{ssh});
    my $chan = $self->{ssh}->channel();
    $chan->exec($cmd);
    get_ssh_output($chan);
    $chan->send_eof;
    my $ret = $chan->exit_status();
    bmwqemu::diag "Command executed: $cmd, ret=$ret";
    $chan->close();
    return $ret;
}

sub can_handle {
    my ($self, $args) = @_;
    return;
}

sub is_shutdown {
    my ($self) = @_;
    return 0;
}


sub check_socket {
    my ($self, $fh, $write) = @_;

    if ($self->check_ssh_serial($fh)) {
        return 1;
    }
    return $self->SUPER::check_socket($fh, $write);
}

1;

# vim: set sw=4 et:
