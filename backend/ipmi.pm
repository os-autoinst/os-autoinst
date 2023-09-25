# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::ipmi;
use Mojo::Base 'backend::baseclass', -signatures;
use autodie ':all';
use Time::HiRes qw(sleep);
use Time::Seconds;
use IPC::Run ();
require IPC::System::Simple;

sub new ($class) {
    $bmwqemu::vars{WORKER_HOSTNAME} or die 'Need variable WORKER_HOSTNAME';
    return $class->SUPER::new;
}

sub ipmi_cmdline ($self) {
    $bmwqemu::vars{"IPMI_$_"} or die "Need variable IPMI_$_" for qw(HOSTNAME USER PASSWORD);
    return ('ipmitool', '-I', 'lanplus', '-H', $bmwqemu::vars{IPMI_HOSTNAME}, '-U', $bmwqemu::vars{IPMI_USER}, '-P', $bmwqemu::vars{IPMI_PASSWORD});
}

sub ipmitool ($self, $cmd, %args) {
    $args{tries} //= 1;

    my @cmd = $self->ipmi_cmdline();
    push(@cmd, split(/ /, $cmd));

    my ($stdin, $stdout, $stderr, $ret);
    # Mitigate occasional failures of impitool due to self-tests/self-reboots of
    # the IPMI controller by a simple sleep/retry mechanism.
    my @tries = (1 .. $args{tries});
    for (@tries) {
        $ret = IPC::Run::run(\@cmd, \$stdin, \$stdout, \$stderr);
        if ($ret) {
            $self->dell_sleep;
            last;
        } else {
            sleep 4;
        }
    }
    chomp $stdout;
    chomp $stderr;
    # Output error message with ipmi password masked
    die join(' ', map { $_ eq $bmwqemu::vars{IPMI_PASSWORD} ? "[masked]" : $_ } @cmd) . ": $stderr" unless ($ret);

    bmwqemu::diag("IPMI: $stdout");
    return $stdout;
}

# DELL BMCs are touchy
sub dell_sleep ($self) {
    return unless ($bmwqemu::vars{IPMI_HW} || '') eq 'dell';
    sleep 4;
}

sub restart_host ($self) {
    my $tries = 3;    # arbitrary selection of tries

    my $stdout = $self->ipmitool('chassis power status', tries => $tries);
    if ($stdout !~ m/is off/) {
        $self->ipmitool("chassis power off");
        for (0 .. $tries) {
            sleep(3);
            my $stdout = $self->ipmitool('chassis power status', tries => $tries);
            last if $stdout =~ m/is off/;
            $self->ipmitool('chassis power off');
        }
    }

    $self->ipmitool("chassis power on");
    for (0 .. $tries) {
        sleep(3);
        my $ret = $self->ipmitool('chassis power status', tries => $tries);
        last if $ret =~ m/is on/;
        $self->ipmitool('chassis power on');
    }
    1;
}

sub do_start_vm ($self, @) {
    # reset ipmi main board if switch on
    # We may need this IPMI_BACKEND_MC_RESET setting to tune differently
    # on different ipmi workers according to different ipmi machines' behavior.
    # It is expected generally that ipmi machine's stability is higher with this mc reset.
    # However there maybe exceptions on machines from different vendors.
    # So keep it for flexibility.
    $self->do_mc_reset if $bmwqemu::vars{IPMI_BACKEND_MC_RESET};
    $self->get_mc_status;
    $self->restart_host unless $bmwqemu::vars{IPMI_DO_NOT_RESTART_HOST};
    $self->truncate_serial_file;
    my $sol = $testapi::distri->add_console(
        'sol', 'ipmi-xterm',
        {
            persistent => $bmwqemu::vars{IPMI_SOL_PERSISTENT_CONSOLE} // 1,
            log => $bmwqemu::vars{HARDWARE_CONSOLE_LOG} // 0});
    $sol->backend($self);
    return {};
}

sub do_stop_vm ($self, @) {
    $self->ipmitool("chassis power off") unless $bmwqemu::vars{IPMI_DO_NOT_POWER_OFF};
    $self->deactivate_console({testapi_console => 'sol'}) if defined $testapi::distri->{consoles}->{sol};
    return {};
}

sub is_shutdown ($self, @) {
    my $ret = $self->ipmitool('chassis power status', tries => 3);
    return $ret =~ m/is off/;
}

sub check_socket ($self, $fh, $write = undef) { $self->check_ssh_serial($fh) || $self->SUPER::check_socket($fh, $write) }

sub get_mc_status ($self) {
    $self->ipmitool("mc guid");
    $self->ipmitool("mc info");
    $self->ipmitool("mc selftest") unless $bmwqemu::vars{IPMI_SKIP_SELFTEST};
}

sub do_mc_reset ($self) {
    # deactivate sol console before doing mc reset because it breaks sol connection
    if (defined $testapi::distri->{consoles}->{sol}) {
        bmwqemu::diag("Before doing mc reset, sol console exists, so cleanup it");
        $testapi::distri->{consoles}->{sol}->reset();
        bmwqemu::diag("sol console reset done");
        $self->deactivate_console({testapi_console => 'sol'});
        bmwqemu::diag("deactivate console sol done");
    }

    # during the eval execution of following commands, SIG{__DIE__} will definitely be triggered, let it go
    local $SIG{__DIE__} = sub { };

    # mc reset cmd should return immediately, try maximum 5 times to ensure cmd executed
    my $max_tries = $bmwqemu::vars{IPMI_MC_RESET_MAX_TRIES} // 5;
    for (1 .. $max_tries) {
        eval { $self->ipmitool("mc reset cold"); };
        if (my $E = $@) {
            bmwqemu::diag("IPMI mc reset failure: $E");
        }
        else {
            bmwqemu::diag('IPMI mc reset success, waiting some seconds before trying to connect again');
            sleep $bmwqemu::vars{IPMI_MC_RESET_SLEEP_TIME_S} // 10;
            bmwqemu::diag('sleep period ends, probing connection with ping');
            # check until  mc reset is done and ipmi recovered
            my $count = 0;
            my $timeout = $bmwqemu::vars{IPMI_MC_RESET_TIMEOUT} // ONE_MINUTE;
            my $ping_count = $bmwqemu::vars{IPMI_MC_RESET_PING_COUNT} // 1;
            my $ping_cmd = "ping -c$ping_count '$bmwqemu::vars{IPMI_HOSTNAME}'";
            my $ipmi_tries = $bmwqemu::vars{IPMI_MC_RESET_IPMI_TRIES} // 3;
            while ($count++ < $timeout) {
                eval { system($ping_cmd); };
                if (!$@) {
                    # ping pass, check ipmitool function normally
                    eval { $self->ipmitool('chassis power status', tries => $ipmi_tries); };
                    if (!$@) {
                        bmwqemu::diag("IPMI: ipmitool is recovered after mc reset");
                        return;
                    }
                }
                sleep 3;    # uncoverable statement
            }
        }
        sleep 3;    # uncoverable statement
    }

    die "IPMI mc reset failure after $max_tries tries! Exit...";
}

1;
