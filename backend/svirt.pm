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
use testapi qw(get_var get_required_var check_var);

use IO::Select;

# this is a fake backend to some extend. We don't start VMs, but provide ssh access
# to a libvirt running host (KVM for System Z in mind)

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new;
    get_required_var('WORKER_HOSTNAME');

    return $self;
}

# we don't do anything actually
sub do_start_vm {
    my ($self) = @_;

    my $vars = \%bmwqemu::vars;
    my $n = $vars->{NUMDISKS} || 1;
    $vars->{NUMDISKS} ||= defined($vars->{RAIDLEVEL}) ? 4 : $n;

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

    bmwqemu::save_vars();    # update variables
    return {};
}

sub do_stop_vm {
    my ($self) = @_;

    $self->stop_serial_grab;

    unless (get_var('SVIRT_KEEP_VM_RUNNING')) {
        my $vmname = $self->console('svirt')->name;
        bmwqemu::diag "Destroying $vmname virtual machine";
        if (check_var('VIRSH_VMM_FAMILY', 'hyperv')) {
            my $ps = 'powershell -Command';
            $self->run_cmd("$ps Stop-VM -Force -VMName $vmname -TurnOff");
            $self->run_cmd("$ps Remove-VM -Force -VMName $vmname");
        }
        else {
            $self->run_cmd("virsh destroy $vmname");
            $self->run_cmd("virsh undefine $vmname");
        }
    }
    return {};
}

# In list context returns pair ($stdout, $stderr). In void (and scalar)
# context just logs stdout and stderr, returns nothing.
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

sub run_cmd {
    my ($self, $cmd, $hostname, $password) = @_;
    $hostname ||= get_required_var('VIRSH_HOSTNAME');
    $password ||= get_var('VIRSH_PASSWORD');

    $self->{ssh} = $self->new_ssh_connection(
        hostname => $hostname,
        password => $password,
        username => 'root'
    );
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
    my $vars = \%bmwqemu::vars;
    if ($args->{function} eq 'snapshots' && !check_var('HDDFORMAT', 'raw')) {
        # Snapshots via libvirt are supported on KVM and, perhaps, ESXi. Hyper-V uses native tools.
        if (check_var('VIRSH_VMM_FAMILY', 'kvm') || check_var('VIRSH_VMM_FAMILY', 'hyperv')) {
            return {ret => 1};
        }
    }
    return;
}

sub is_shutdown {
    my ($self) = @_;
    my $vmname = $self->console('svirt')->name;
    my $rsp;
    if (check_var('VIRSH_VMM_FAMILY', 'hyperv')) {
        $rsp = $self->run_cmd("powershell -Command \"if (\$(Get-VM -VMName $vmname \| Where-Object {\$_.state -eq 'Off'})) { exit 1 } else { exit 0 }\"");
    }
    else {
        $rsp = $self->run_cmd("! virsh dominfo $vmname | grep -w 'shut off'");
    }
    return $rsp;
}

sub save_snapshot {
    my ($self, $args) = @_;
    my $snapname = $args->{name};
    my $vmname   = $self->console('svirt')->name;
    my $rsp;
    if (check_var('VIRSH_VMM_FAMILY', 'hyperv')) {
        my $ps = 'powershell -Command';
        $self->run_cmd("$ps Remove-VMSnapshot -VMName $vmname -Name $snapname");
        $rsp = $self->run_cmd("$ps Checkpoint-VM -VMName $vmname -SnapshotName $snapname");
    }
    else {
        $self->run_cmd("virsh snapshot-delete $vmname $snapname");
        $rsp = $self->run_cmd("virsh snapshot-create-as $vmname $snapname");
    }
    bmwqemu::diag "SAVE VM \"$vmname\" as \"$snapname\" snapshot, return code=$rsp";
    die unless ($rsp == 0);
    return;
}

sub load_snapshot {
    my ($self, $args) = @_;
    my $snapname = $args->{name};
    my $vmname   = $self->console('svirt')->name;
    my $rsp;
    if (check_var('VIRSH_VMM_FAMILY', 'hyperv')) {
        my $ps = 'powershell -Command';
        $rsp = $self->run_cmd("$ps Restore-VMSnapshot -VMName $vmname -Name $snapname -Confirm:\$false");
        $self->run_cmd("mv -v xfreerdp_${vmname}_stop xfreerdp_${vmname}_stop.bkp", get_required_var('VIRSH_GUEST'), get_var('VIRSH_GUEST_PASSWORD'));
        for my $i (1 .. 5) {
            # Because of FreeRDP issue https://github.com/FreeRDP/FreeRDP/issues/3876,
            # we can't connect too "early". Let's have a nap for a while.
            sleep 10;
            last
              unless $self->run_cmd(
                "pgrep --full --list-full xfreerdp.*\$(cat xfreerdp_${vmname}_stop.bkp)",
                get_required_var('VIRSH_GUEST'),
                get_var('VIRSH_GUEST_PASSWORD'));
            die "xfreerdp did not start" if ($i eq 5);
        }
    }
    else {
        $rsp = $self->run_cmd("virsh snapshot-revert $vmname $snapname");
    }
    bmwqemu::diag "LOAD snapshot \"$snapname\" to \"$vmname\", return code=$rsp";
    die unless ($rsp == 0);
    return $rsp;
}

# Open another ssh connection to grab the serial console.
sub start_serial_grab {
    my ($self, $name) = @_;

    # Connect to VM host, or, in case of Hyper-V, to intermediary from which we gather
    # remote serial console output.
    my ($hostname, $password);
    if (check_var('VIRSH_VMM_FAMILY', 'hyperv')) {
        $hostname = get_required_var('VIRSH_GUEST');
        $password = get_var('VIRSH_GUEST_PASSWORD');
    }
    else {
        $hostname = get_required_var('VIRSH_HOSTNAME');
        $password = get_var('VIRSH_PASSWORD');
    }
    my $chan = $self->start_ssh_serial(hostname => $hostname, password => $password, username => 'root');
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

1;

# vim: set sw=4 et:
