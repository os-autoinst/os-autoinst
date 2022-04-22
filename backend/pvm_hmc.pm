# Copyright 2019-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::pvm_hmc;
use Mojo::Base 'backend::virt', -signatures;

# supporting the minimal command set of the HMC through a ssh tunnel

sub new ($class) {
    my $self = $class->SUPER::new;
    defined $bmwqemu::vars{HMC_MACHINE_NAME} or die 'Need variable HMC_MACHINE_NAME';

    return $self;
}

# only define the HMC console - we leave the actual
# poweron to the test
sub do_start_vm ($self, @) {
    # truncate the serial file
    open(my $sf, '>', $self->{serialfile});
    close($sf);

    my $ssh = $testapi::distri->add_console(
        'powerhmc-ssh',
        'ssh-xterm',
        {
            hostname => $bmwqemu::vars{HMC_HOSTNAME} || die('Need variable HMC_HOSTNAME'),
            password => $bmwqemu::vars{HMC_PASSWORD} || die('Need variable HMC_PASSWORD'),
            username => $bmwqemu::vars{HMC_USERNAME} // 'hscroot',
            persistent => 1,
            log => $bmwqemu::vars{HARDWARE_CONSOLE_LOG} // 0
        });
    $ssh->backend($self);

    return {};
}

sub do_stop_vm ($self, @) {
    $self->stop_serial_grab;
    $self->deactivate_console({testapi_console => 'powerhmc-ssh'});
    return {};
}

sub run_cmd ($self, $cmd, $hostname = undef, $password = undef, @) {
    $hostname //= $bmwqemu::vars{HMC_HOSTNAME} or die 'Need variable HMC_HOSTNAME';
    $password //= $bmwqemu::vars{HMC_PASSWORD} or die 'Need variable HMC_PASSWORD';
    my $username = $bmwqemu::vars{HMC_USERNAME} // 'hscroot';
    return $self->run_ssh_cmd($cmd, username => $username, password => $password, hostname => $hostname,
        keep_open => 0);
}

sub can_handle ($self, @) { undef }

sub is_shutdown ($self, @) {
    my $lpar_id = $bmwqemu::vars{LPAR_ID} or die 'Need variable LPAR_ID';
    my $hmc_machine_name = $bmwqemu::vars{HMC_MACHINE_NAME} or die 'Need variable HMC_MACHINE_NAME';
    return $self->run_cmd(
        "! lssyscfg -m ${hmc_machine_name} -r lpar --filter 'lpar_ids=${lpar_id}' -F state | grep -i 'not activated' -q"
    );
}

sub check_socket ($self, $fh, $write = undef) {
    return $self->check_ssh_serial($fh) || $self->SUPER::check_socket($fh, $write);
}

sub stop_serial_grab ($self, @) {
    $self->stop_ssh_serial;
    return undef;
}

1;
