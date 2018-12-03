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

package backend::spvm;

use strict;
use warnings;

use base 'backend::virt';

use testapi qw(get_var get_required_var check_var);
use IO::Select;

# supporting the minimal command set of NovaLink through a ssh tunnel

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new;
    get_required_var('WORKER_HOSTNAME');

    return $self;
}

# only define the novalink console - we leave the actual
# poweron to the test
sub do_start_vm {
    my ($self) = @_;

    # truncate the serial file
    open(my $sf, '>', $self->{serialfile});
    close($sf);

    my $ssh = $testapi::distri->add_console(
        'novalink-ssh',
        'ssh-xterm',
        {
            hostname => get_required_var('NOVALINK_HOSTNAME'),
            password => get_required_var('NOVALINK_PASSWORD'),
            username => get_var('NOVALINK_USERNAME', 'root')});
    $ssh->backend($self);

    return {};
}

sub do_stop_vm {
    my ($self) = @_;

    $self->stop_serial_grab;
    $self->deactivate_console({testapi_console => 'novalink-ssh'});
    return {};
}

sub run_cmd {
    my ($self, $cmd, $hostname, $password) = @_;
    $hostname ||= get_required_var('NOVALINK_HOSTNAME');
    $password ||= get_required_var('NOVALINK_PASSWORD');

    $self->{ssh} = $self->new_ssh_connection(
        hostname => $hostname,
        password => $password,
        username => get_var('NOVALINK_USERNAME', 'root'));
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
    # TODO
    return 0;
}

sub check_socket {
    my ($self, $fh, $write) = @_;

    if ($self->check_ssh_serial($fh)) {
        return 1;
    }
    return $self->SUPER::check_socket($fh, $write);
}

sub stop_serial_grab {
    my ($self) = @_;

    $self->stop_ssh_serial;
    return;
}

1;
