# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2016 SUSE LLC
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

package backend::svirt;
use strict;
use base ('backend::virt');
use testapi qw(get_required_var check_var);

use IO::Select;

# this is a fake backend to some extend. We don't start VMs, but provide ssh access
# to a libvirt running host (KVM for System Z in mind)

use testapi qw/get_var check_var/;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new;
    get_required_var('WORKER_HOSTNAME');

    return $self;
}

# we don't do anything actually
sub do_start_vm {
    my ($self) = @_;

    # truncate the serial file
    open(my $sf, '>', $self->{serialfile});
    close($sf);

    my $ssh = $testapi::distri->add_console(
        'svirt',
        'ssh-virtsh',
        {
            hostname => get_required_var('VIRSH_HOSTNAME'),
            password => get_var('VIRSH_PASSWORD'),
        });

    $ssh->backend($self);
    $self->select_console({testapi_console => 'svirt'});

    # remove backend.crashed
    $self->unlink_crash_file;
    return {};
}

sub do_stop_vm {
    my ($self) = @_;

    $self->stop_serial_grab;
    return {};
}

# Open another ssh connection to grab the serial console.
sub start_serial_grab {
    my ($self, $name) = @_;

    my $chan = $self->start_ssh_serial(hostname => get_required_var('VIRSH_HOSTNAME'), password => get_var('VIRSH_PASSWORD'), username => 'root');
    if (check_var('VIRSH_VMM_FAMILY', 'vmware')) {
        # libvirt esx driver does not support `virsh console', so
        # we have to connect to VM's serial port via TCP which is
        # provided by ESXi server.
        $chan->exec('nc ' . get_var('VMWARE_SERVER') . ' ' . get_var('VMWARE_SERIAL_PORT'));
    }
    elsif (check_var('VIRSH_VMM_FAMILY', 'hyperv')) {
        # Hyper-V does not support serial console export via TCP, just
        # windows named pipes (e.g. \\.\pipe\mypipe). Such a named pipe
        # has to be enabled by a namedpipe-to-TCP on HYPERV_SERVER application.
        $chan->exec('nc ' . get_var('HYPERV_SERVER') . ' ' . get_var('HYPERV_SERIAL_PORT'));
    }
    else {
        $chan->exec('virsh console ' . $name);
    }
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

sub status {
    my ($self) = @_;
    return;
}

1;

# vim: set sw=4 et:
