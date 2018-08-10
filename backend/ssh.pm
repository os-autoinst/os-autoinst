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
use testapi 'get_required_var';
use Carp 'cluck';

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
    my $username = get_required_var('SSH_USERNAME', 'root');

    # truncate the serial file
    open(my $sf, '>', $self->{serialfile});
    close($sf);

    my $ssh_console = $testapi::distri->add_console(
        'sut',
        'ssh_console',
        {
            hostname => $hostname,
            password => $password,
            username => $username
        });
    $ssh_console->backend($self);
    $self->select_console({testapi_console => 'sut'});

    # TODO use unique filename or exit if file exists
    my $serial_file = "/dev/" . $testapi::serialdev;
    $self->run_cmd("mkfifo $serial_file", $hostname, $password, $username);

    # Listen on serial file
    my $chan = $self->start_ssh_serial(hostname => $hostname, password => $password, username => $username);
    $chan->exec("tail -F $serial_file");

    return {};
}

sub do_stop_vm {

    my ($self) = @_;
    my $serial_file = "/dev/" . $testapi::serialdev;

    $self->stop_ssh_serial;
    $self->run_cmd("rm $serial_file");
    $self->deactivate_console({testapi_console => 'sut'});

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
