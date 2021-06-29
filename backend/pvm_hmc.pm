# Copyright © 2019-2021 SUSE LLC
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

package backend::pvm_hmc;

use Mojo::Base -strict, -signatures;

use base 'backend::virt';

use testapi qw(get_var get_required_var);

# supporting the minimal command set of the HMC through a ssh tunnel

sub new ($class) {
    my $self = $class->SUPER::new;
    get_required_var('HMC_MACHINE_NAME');

    return $self;
}

# only define the HMC console - we leave the actual
# poweron to the test
sub do_start_vm ($self) {

    # truncate the serial file
    open(my $sf, '>', $self->{serialfile});
    close($sf);

    my $ssh = $testapi::distri->add_console(
        'powerhmc-ssh',
        'ssh-xterm',
        {
            hostname   => get_required_var('HMC_HOSTNAME'),
            password   => get_required_var('HMC_PASSWORD'),
            username   => get_var('HMC_USERNAME', 'hscroot'),
            persistent => 1});
    $ssh->backend($self);

    return {};
}

sub do_stop_vm ($self) {

    $self->stop_serial_grab;
    $self->deactivate_console({testapi_console => 'powerhmc-ssh'});
    return {};
}

sub run_cmd ($self, $cmd, $hostname, $password) {
    $hostname ||= get_required_var('HMC_HOSTNAME');
    $password ||= get_required_var('HMC_PASSWORD');
    my $username = get_var('HMC_USERNAME', 'hscroot');

    return $self->run_ssh_cmd($cmd, username => $username, password => $password, hostname => $hostname, keep_open => 0);
}

sub can_handle ($self, $args) {
    return undef;
}

sub is_shutdown ($self) {
    my $lpar_id          = get_required_var('LPAR_ID');
    my $hmc_machine_name = get_required_var('HMC_MACHINE_NAME');
    return $self->run_cmd("! lssyscfg -m ${hmc_machine_name} -r lpar --filter 'lpar_ids=${lpar_id}' -F state | grep -i 'not activated' -q");
}

sub check_socket ($self, $fh, $write) {

    return $self->check_ssh_serial($fh) || $self->SUPER::check_socket($fh, $write);
}

sub stop_serial_grab ($self) {

    $self->stop_ssh_serial;
    return undef;
}

1;
