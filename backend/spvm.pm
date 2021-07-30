# Copyright 2018-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::spvm;

use Mojo::Base -strict, -signatures;

use base 'backend::virt';

use testapi qw(get_var get_required_var);

# supporting the minimal command set of NovaLink through a ssh tunnel

sub new ($class) {
    my $self = $class->SUPER::new;
    $bmwqemu::vars{WORKER_HOSTNAME} // die 'Need variable \'WORKER_HOSTNAME\'';
    return $self;
}

# only define the novalink console - we leave the actual
# poweron to the test
sub do_start_vm ($self) {
    $self->truncate_serial_file;
    $bmwqemu::vars{NOVALINK_HOSTNAME} // die 'Need variable \'NOVALINK_HOSTNAME\'';
    $bmwqemu::vars{NOVALINK_PASSWORD} // die 'Need variable \'NOVALINK_PASSWORD\'';
    my $ssh = $testapi::distri->add_console(
        'novalink-ssh',
        'ssh-xterm',
        {
            hostname => $bmwqemu::vars{NOVALINK_HOSTNAME},
            password => $bmwqemu::vars{NOVALINK_PASSWORD},
            username => $bmwqemu::vars{NOVALINK_USERNAME} // 'root',
            persistent => 1});
    $ssh->backend($self);

    return {};
}

sub do_stop_vm ($self) {
    $self->stop_serial_grab;
    $self->deactivate_console({testapi_console => 'novalink-ssh'});
    return {};
}

sub run_cmd ($self, $cmd, $hostname = $bmwqemu::vars{NOVALINK_HOSTNAME}, $password = $bmwqemu::vars{NOVALINK_PASSWORD}) {
    my $username = $bmwqemu::vars{NOVALINK_USERNAME} // 'root';

    return $self->run_ssh_cmd($cmd, username => $username, password => $password, hostname => $hostname, keep_open => 0);
}

sub can_handle ($self, $args) {
    return;
}

sub is_shutdown ($self) {
    my $lpar_id = $bmwqemu::vars{NOVALINK_LPAR_ID} // die 'Need variable \'NOVALINK_LPAR_ID\'';
    return $self->run_cmd("! pvmctl  lpar list -i id=${lpar_id} | grep  'not a'");
}

sub check_socket ($self, $fh, $write = undef) {
    return $self->check_ssh_serial($fh) || $self->SUPER::check_socket($fh, $write);
}

sub stop_serial_grab ($self) {
    $self->stop_ssh_serial;
    return;
}

# parameters: on, off, reset
sub power ($self, $args) {
    my $action = $args->{action};
    my $lpar_id = $bmwqemu::vars{NOVALINK_LPAR_ID} // die 'Need variable \'NOVALINK_LPAR_ID\'';

    my %cmds = (
        on => "pvmctl lpar power-on -i id=${lpar_id} --bootmode norm",
        off => "pvmctl lpar power-off -i id=${lpar_id} --hard",
        reset => "pvmctl lpar restart -i id=${lpar_id}");
    $self->run_cmd($cmds{$action}) if (exists($cmds{$action})) || die "Unknown power action ${action}";
}

1;
