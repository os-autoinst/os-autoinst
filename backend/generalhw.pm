# Copyright © 2016-2021 SUSE LLC
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

# this backend uses a KVM connector speaking VNC and external tools
# for serial line and power cycling

package backend::generalhw;

use Mojo::Base -strict, -signatures;
use autodie ':all';

use base 'backend::baseclass';

use bmwqemu;
use testapi qw(get_required_var get_var);
use IPC::Run ();
require IPC::System::Simple;
use File::Basename 'basename';

sub new ($class) {
    # required for the tests to access our HTTP port
    get_required_var('WORKER_HOSTNAME');
    return $class->SUPER::new;
}

sub get_cmd ($self, $cmd) {
    my $dir = get_required_var('GENERAL_HW_CMD_DIR');
    die 'GENERAL_HW_CMD_DIR is not pointing to a directory' unless -d $dir;

    my %GENERAL_HW_ARG_VARIABLES_BY_CMD = ('GENERAL_HW_FLASH_CMD' => 'GENERAL_HW_FLASH_ARGS', 'GENERAL_HW_SOL_CMD' => 'GENERAL_HW_SOL_ARGS', 'GENERAL_HW_POWERON_CMD' => 'GENERAL_HW_POWERON_ARGS', 'GENERAL_HW_POWEROFF_CMD' => 'GENERAL_HW_POWEROFF_ARGS');
    my $args = get_var($GENERAL_HW_ARG_VARIABLES_BY_CMD{$cmd}) if get_var($GENERAL_HW_ARG_VARIABLES_BY_CMD{$cmd});

    # Append HDD infos to flash script
    if ($cmd eq 'GENERAL_HW_FLASH_CMD' and get_var('HDD_1')) {
        my $numdisks = get_var('NUMDISKS') // 1;
        for my $i (1 .. $numdisks) {
            # Pass path of HDD
            $args .= " " . get_required_var("HDD_$i");
            # Pass size of HDD
            my $size = get_var("HDDSIZEGB_$i");
            $size //= get_var('HDDSIZEGB') // 10;
            $args .= " $size" . 'G';
        }
    }

    $cmd = get_required_var($cmd);
    $cmd = "$dir/" . basename($cmd);
    $cmd .= " $args" if $args;
    return $cmd;
}

sub run_cmd ($self, $cmd) {
    my @full_cmd = split / /, $self->get_cmd($cmd);

    my ($stdin, $stdout, $stderr, $ret);
    eval { $ret = IPC::Run::run([@full_cmd], \$stdin, \$stdout, \$stderr) };
    die "Unable to run command '@full_cmd' (deduced from test variable $cmd): $@\n" if $@;
    chomp $stdout;
    chomp $stderr;

    die "$cmd: $stderr" unless $ret;
    bmwqemu::diag("IPMI: $stdout");
    return $stdout;
}

sub poweroff_host ($self) {
    $self->run_cmd('GENERAL_HW_POWEROFF_CMD');
    return;
}

sub restart_host ($self) {
    $self->poweroff_host;
    sleep(3);
    $self->run_cmd('GENERAL_HW_POWERON_CMD');
    return;
}

sub relogin_vnc ($self) {
    if ($self->{vnc}) {
        close($self->{vnc}->socket);
        sleep(1);
    }

    my $vnc = $testapi::distri->add_console(
        'sut',
        'vnc-base',
        {
            hostname        => get_required_var('GENERAL_HW_VNC_IP'),
            port            => 5900,
            depth           => 16,
            connect_timeout => 50
        });
    $vnc->backend($self);
    $self->select_console({testapi_console => 'sut'});

    return 1;
}

sub do_start_vm ($self) {
    $self->truncate_serial_file;
    if (get_var('GENERAL_HW_FLASH_CMD')) {
        $self->poweroff_host;    # Ensure system is off, before flashing
        $self->run_cmd('GENERAL_HW_FLASH_CMD');
    }
    $self->restart_host;
    $self->relogin_vnc       if (get_var('GENERAL_HW_VNC_IP'));
    $self->start_serial_grab if (get_var('GENERAL_HW_VNC_IP') || get_var('GENERAL_HW_SOL_CMD'));
    return {};
}

sub do_stop_vm ($self) {
    $self->poweroff_host;
    $self->stop_serial_grab() if (get_var('GENERAL_HW_VNC_IP') || get_var('GENERAL_HW_SOL_CMD'));
    return {};
}

sub check_socket ($self, $fh, $write) {
    return $self->check_ssh_serial($fh) || $self->SUPER::check_socket($fh, $write);
}

# serial grab

sub start_serial_grab ($self) {
    $self->{serialpid} = fork();
    return unless $self->{serialpid} == 0;
    setpgrp 0, 0;
    open(my $serial, '>',  $self->{serialfile});
    open(STDOUT,     ">&", $serial);
    open(STDERR,     ">&", $serial);
    exec($self->get_cmd('GENERAL_HW_SOL_CMD'));
    die "exec failed $!";
}

sub stop_serial_grab ($self) {
    return unless $self->{serialpid};
    kill("-TERM", $self->{serialpid});
    return waitpid($self->{serialpid}, 0);
}

# serial grab end

1;
