# Copyright 2016-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# this backend uses a KVM connector speaking VNC and external tools
# for serial line and power cycling

package backend::generalhw;

use Mojo::Base -strict, -signatures;
use autodie ':all';

use base 'backend::baseclass';

use bmwqemu;
use IPC::Run ();
require IPC::System::Simple;
use File::Basename 'basename';

sub new ($class) {
    # required for the tests to access our HTTP port
    defined $bmwqemu::vars{WORKER_HOSTNAME} or die 'Need variable WORKER_HOSTNAME';
    return $class->SUPER::new;
}

sub get_cmd ($self, $cmd) {
    my $dir = $bmwqemu::vars{GENERAL_HW_CMD_DIR} or die 'Need variable GENERAL_HW_CMD_DIR';
    die 'GENERAL_HW_CMD_DIR is not pointing to a directory' unless -d $dir;

    my %GENERAL_HW_ARG_VARIABLES_BY_CMD = ('GENERAL_HW_FLASH_CMD' => 'GENERAL_HW_FLASH_ARGS', 'GENERAL_HW_SOL_CMD' => 'GENERAL_HW_SOL_ARGS', 'GENERAL_HW_POWERON_CMD' => 'GENERAL_HW_POWERON_ARGS', 'GENERAL_HW_POWEROFF_CMD' => 'GENERAL_HW_POWEROFF_ARGS');
    my $args = $bmwqemu::vars{$GENERAL_HW_ARG_VARIABLES_BY_CMD{$cmd}} if $bmwqemu::vars{$GENERAL_HW_ARG_VARIABLES_BY_CMD{$cmd}};

    # Append HDD infos to flash script
    if ($cmd eq 'GENERAL_HW_FLASH_CMD' and $bmwqemu::vars{HDD_1}) {
        my $numdisks = $bmwqemu::vars{NUMDISKS} // 1;
        for my $i (1 .. $numdisks) {
            # Pass path of HDD
            $args .= " " . $bmwqemu::vars{"HDD_$i"} or die 'Need variable HDD_$i';
            # Pass size of HDD
            my $size = $bmwqemu::vars{"HDDSIZEGB_$i"};
            $size //= $bmwqemu::vars{HDDSIZEGB} // 10;
            $args .= " $size" . 'G';
        }
    }

    $cmd = $bmwqemu::vars{$cmd} or die "Need test variable '$cmd'";
    $cmd = "$dir/" . basename($cmd);
    $cmd .= " $args" if $args;
    return $cmd;
}

sub run_cmd ($self, @args) {
    my @full_cmd = split / /, $self->get_cmd($args[0]);

    my ($stdin, $stdout, $stderr, $ret);
    eval { $ret = IPC::Run::run([@full_cmd], \$stdin, \$stdout, \$stderr) };
    die "Unable to run command '@full_cmd' (deduced from test variable $args[0]): $@\n" if $@;
    chomp $stdout;
    chomp $stderr;

    die "$args[0]: $stderr" unless $ret;
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
            hostname => $bmwqemu::vars{GENERAL_HW_VNC_IP} || die('Need variable GENERAL_HW_VNC_IP'),
            port => 5900,
            depth => 16,
            connect_timeout => 50
        });
    $vnc->backend($self);
    $self->select_console({testapi_console => 'sut'});

    return 1;
}

sub do_start_vm ($self, @) {
    $self->truncate_serial_file;
    if ($bmwqemu::vars{GENERAL_HW_FLASH_CMD}) {
        $self->poweroff_host;    # Ensure system is off, before flashing
        $self->run_cmd('GENERAL_HW_FLASH_CMD');
    }
    $self->restart_host;
    $self->relogin_vnc if ($bmwqemu::vars{GENERAL_HW_VNC_IP});
    $self->start_serial_grab if ($bmwqemu::vars{GENERAL_HW_VNC_IP} || $bmwqemu::vars{GENERAL_HW_SOL_CMD});
    return {};
}

sub do_stop_vm ($self, @) {
    $self->poweroff_host;
    $self->stop_serial_grab() if ($bmwqemu::vars{GENERAL_HW_VNC_IP} || $bmwqemu::vars{GENERAL_HW_SOL_CMD});
    return {};
}

sub check_socket ($self, $fh, $write = undef) {
    return $self->check_ssh_serial($fh) || $self->SUPER::check_socket($fh, $write);
}

# serial grab

sub start_serial_grab ($self) {
    $self->{serialpid} = fork();
    return unless $self->{serialpid} == 0;
    setpgrp 0, 0;
    open(my $serial, '>', $self->{serialfile});
    open(STDOUT, ">&", $serial);
    open(STDERR, ">&", $serial);
    exec($self->get_cmd('GENERAL_HW_SOL_CMD'));
    die "exec failed $!";
}

sub stop_serial_grab ($self, @) {
    return unless $self->{serialpid};
    kill("-TERM", $self->{serialpid});
    return waitpid($self->{serialpid}, 0);
}

# serial grab end

1;
