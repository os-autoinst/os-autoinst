# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::ova;
use Mojo::Base 'backend::svirt', -signatures;
use bmwqemu;

sub do_start_vm ($self, @) {
    my $vars = \%bmwqemu::vars;
    my $n = $vars->{NUMDISKS} // 1;
    $vars->{NUMDISKS} //= defined($vars->{RAIDLEVEL}) ? 4 : $n;
    $self->truncate_serial_file;
    my $ssh = $testapi::distri->add_console(
        'svirt',
        'ssh-virtsh-ova',
        {
            hostname => $bmwqemu::vars{VIRSH_HOSTNAME} || die('Need variables VIRSH_HOSTNAME'),
            username => $bmwqemu::vars{VIRSH_USERNAME},
            password => $bmwqemu::vars{VIRSH_PASSWORD},
        });

    $ssh->backend($self);

    bmwqemu::save_vars();    # update variables
    return {};
}

1;
