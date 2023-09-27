# Copyright 2016-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# this backend uses a KVM connector speaking VNC and external tools
# for serial line and power cycling

package backend::generalhw;

use Mojo::Base 'backend::baseclass', -signatures;
use autodie ':all';
use bmwqemu;
use IPC::Run ();
require IPC::System::Simple;
use File::Basename 'basename';
use Mojo::IOLoop::ReadWriteProcess::Session 'session';

sub new ($class) {
    # required for the tests to access our HTTP port
    defined $bmwqemu::vars{WORKER_HOSTNAME} or die 'Need variable WORKER_HOSTNAME';
    return $class->SUPER::new;
}

sub get_cmd ($self, $cmd) {
    my $dir = $bmwqemu::vars{GENERAL_HW_CMD_DIR} or die 'Need variable GENERAL_HW_CMD_DIR';
    die 'GENERAL_HW_CMD_DIR is not pointing to a directory' unless -d $dir;

    my %GENERAL_HW_ARG_VARIABLES_BY_CMD = (
        'GENERAL_HW_FLASH_CMD' => 'GENERAL_HW_FLASH_ARGS',
        'GENERAL_HW_SOL_CMD' => 'GENERAL_HW_SOL_ARGS',
        'GENERAL_HW_INPUT_CMD' => 'GENERAL_HW_INPUT_ARGS',
        'GENERAL_HW_POWERON_CMD' => 'GENERAL_HW_POWERON_ARGS',
        'GENERAL_HW_POWEROFF_CMD' => 'GENERAL_HW_POWEROFF_ARGS',
        'GENERAL_HW_IMAGE_CMD' => 'GENERAL_HW_IMAGE_ARGS',
    );
    my $args = $bmwqemu::vars{$GENERAL_HW_ARG_VARIABLES_BY_CMD{$cmd}} if $bmwqemu::vars{$GENERAL_HW_ARG_VARIABLES_BY_CMD{$cmd}};

    $cmd = $bmwqemu::vars{$cmd} or die "Need test variable '$cmd'";
    $cmd = "$dir/" . basename($cmd);
    $cmd .= " $args" if $args;
    return $cmd;
}

sub run_cmd ($self, $cmd, @extra_args) {
    my @full_cmd = split / /, $self->get_cmd($cmd);

    push @full_cmd, @extra_args;

    bmwqemu::diag("Calling $cmd");
    my $ret = _system(@full_cmd);
    die "Failed to run command '@full_cmd' (deduced from test variable $cmd): $ret\n" if ($ret != 0);
}

# wrapper to be mocked in os-autoinst unit tests as it is hard to mock system()
sub _system (@cmd) { system(@cmd) }    # uncoverable statement

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

sub power ($self, $args) {
    if ($args->{action} eq 'on') {
        $self->run_cmd('GENERAL_HW_POWERON_CMD');
    } elsif ($args->{action} eq 'off') {
        $self->run_cmd('GENERAL_HW_POWEROFF_CMD');
    } else {
        $self->notimplemented;
    }
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
            port => $bmwqemu::vars{GENERAL_HW_VNC_PORT} // 5900,
            password => $bmwqemu::vars{GENERAL_HW_VNC_PASSWORD},
            depth => $bmwqemu::vars{GENERAL_HW_VNC_DEPTH} // 16,
            connect_timeout => 50
        });
    $vnc->backend($self);
    $self->select_console({testapi_console => 'sut'});

    return 1;
}

sub compute_hdd_args ($self) {
    my @hdd_args;

    if ($bmwqemu::vars{HDD_1}) {
        my $numdisks = $bmwqemu::vars{NUMDISKS} // 1;
        for my $i (1 .. $numdisks) {
            # Pass path of HDD
            push @hdd_args, $bmwqemu::vars{"HDD_$i"} or die 'Need variable HDD_$i';
            # Pass size of HDD
            my $size = $bmwqemu::vars{"HDDSIZEGB_$i"};
            $size //= $bmwqemu::vars{HDDSIZEGB} // 10;
            push @hdd_args, $size . 'G';
        }
    }
    return \@hdd_args;
}

sub reconnect_video_stream ($self, @) {

    my $input_cmd;
    $input_cmd = $self->get_cmd('GENERAL_HW_INPUT_CMD') if ($bmwqemu::vars{GENERAL_HW_INPUT_CMD});
    my $vnc = $testapi::distri->add_console(
        'sut',
        'video-stream',
        {
            url => $bmwqemu::vars{GENERAL_HW_VIDEO_STREAM_URL},
            connect_timeout => 50,
            input_cmd => $input_cmd,
            edid => $bmwqemu::vars{GENERAL_HW_EDID},
        });
    $vnc->backend($self);
    $self->select_console({testapi_console => 'sut'});

    return 1;
}

sub do_start_vm ($self, @) {
    $self->truncate_serial_file;
    if ($bmwqemu::vars{GENERAL_HW_FLASH_CMD}) {
        # Append HDD infos to flash script
        my $hdd_args = $self->compute_hdd_args;

        $self->poweroff_host;    # Ensure system is off, before flashing
        $self->run_cmd('GENERAL_HW_FLASH_CMD', @$hdd_args);
    }
    $self->restart_host;
    $self->relogin_vnc if ($bmwqemu::vars{GENERAL_HW_VNC_IP});
    $self->reconnect_video_stream if ($bmwqemu::vars{GENERAL_HW_VIDEO_STREAM_URL});
    $self->start_serial_grab if (($bmwqemu::vars{GENERAL_HW_VNC_IP} || $bmwqemu::vars{GENERAL_HW_SOL_CMD}) && !$bmwqemu::vars{GENERAL_HW_NO_SERIAL});
    return {};
}

sub do_stop_vm ($self, @) {
    $self->poweroff_host;
    $self->stop_serial_grab() if (($bmwqemu::vars{GENERAL_HW_VNC_IP} || $bmwqemu::vars{GENERAL_HW_SOL_CMD}) && !$bmwqemu::vars{GENERAL_HW_NO_SERIAL});
    $self->disable_consoles;
    return {};
}

sub check_socket ($self, $fh, $write = undef) {
    return $self->check_ssh_serial($fh) || $self->SUPER::check_socket($fh, $write);
}

# serial grab

sub start_serial_grab ($self) {
    $self->{serialpid} = fork();
    return unless $self->{serialpid} == 0;
    setpgrp 0, 0;    # uncoverable statement
    open(my $serial, '>', $self->{serialfile});    # uncoverable statement
    open(STDOUT, ">&", $serial);    # uncoverable statement
    open(STDERR, ">&", $serial);    # uncoverable statement
    exec($self->get_cmd('GENERAL_HW_SOL_CMD'));    # uncoverable statement
    die "exec failed $!";    # uncoverable statement
}

sub stop_serial_grab ($self, @) {
    return 0 unless $self->{serialpid};
    eval { kill -TERM => $self->{serialpid} };
    return waitpid($self->{serialpid}, 0) unless my $error = $@;
    return -1 if $error =~ qr/No such process/i;
    die "$error\n" if $error;    # uncoverable statement
}

# serial grab end

sub do_extract_assets ($self, $args) {
    my $name = $args->{name};
    my $img_dir = $args->{dir};
    my $hdd_num = $args->{hdd_num} - 1;
    die "extracting pflash vars not supported" if $args->{pflash_vars};

    $self->run_cmd('GENERAL_HW_IMAGE_CMD', ($hdd_num, "$img_dir/$name"));
}

1;
