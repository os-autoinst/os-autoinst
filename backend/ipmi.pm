# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2015 SUSE LLC
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

package backend::ipmi;
use strict;
use base 'backend::baseclass';
require File::Temp;
use File::Temp ();
use Time::HiRes qw(sleep gettimeofday);
use IO::Select;
use IO::Socket::UNIX 'SOCK_STREAM';
use IO::Handle;
use Data::Dumper;
use POSIX qw(strftime :sys_wait_h);
use JSON;
require Carp;
use Fcntl;
use bmwqemu qw(fileContent diag save_vars diag);
use testapi 'get_required_var';
use IPC::Run ();
require IPC::System::Simple;
use autodie ':all';

sub new {
    my $class = shift;
    get_required_var('WORKER_HOSTNAME');
    return $class->SUPER::new(@_);
}

sub ipmi_cmdline {
    my ($self) = @_;

    return ('ipmitool', '-I', 'lanplus', '-H', $bmwqemu::vars{IPMI_HOSTNAME}, '-U', $bmwqemu::vars{IPMI_USER}, '-P', $bmwqemu::vars{IPMI_PASSWORD});
}

sub ipmitool {
    my ($self, $cmd) = @_;

    my @cmd = $self->ipmi_cmdline();
    push(@cmd, split(/ /, $cmd));

    my ($stdin, $stdout, $stderr, $ret);
    $ret = IPC::Run::run(\@cmd, \$stdin, \$stdout, \$stderr);
    chomp $stdout;
    chomp $stderr;

    $self->dell_sleep;

    die join(' ', @cmd) . ": $stderr" unless ($ret);
    bmwqemu::diag("IPMI: $stdout");
    return $stdout;
}

# DELL BMCs are touchy
sub dell_sleep {
    my ($self) = @_;
    return unless ($bmwqemu::vars{IPMI_HW} || '') eq 'dell';
    sleep 4;
}

sub restart_host {
    my ($self) = @_;

    $self->ipmitool("chassis power off");
    while (1) {
        my $stdout = $self->ipmitool('chassis power status');
        last if $stdout =~ m/is off/;
        $self->ipmitool('chassis power off');
        sleep(2);
    }

    $self->ipmitool("chassis power on");
    while (1) {
        my $ret = $self->ipmitool('chassis power status');
        last if $ret =~ m/is on/;
        $self->ipmitool('chassis power on');
        sleep(2);
    }
}

sub do_start_vm {
    my ($self) = @_;

    # remove backend.crashed
    $self->unlink_crash_file;
    $self->get_mc_status;
    $self->restart_host;

    # truncate the serial file
    open(my $sf, '>', $self->{serialfile});
    close($sf);

    my $sol = $testapi::distri->add_console('sol', 'ipmi-xterm');
    $sol->backend($self);
    return {};
}

sub do_stop_vm {
    my ($self) = @_;

    $self->ipmitool("chassis power off");
    $self->deactivate_console({testapi_console => 'sol'});
    return {};
}

sub is_shutdown {
    my ($self) = @_;
    my $ret = $self->ipmitool('chassis power status');
    return $ret =~ m/is off/;
}

sub check_socket {
    my ($self, $fh, $write) = @_;

    if ($self->check_ssh_serial($fh)) {
        return 1;
    }
    return $self->SUPER::check_socket($fh, $write);
}

sub get_mc_status {
    my ($self) = @_;

    $self->ipmitool("mc guid");
    $self->ipmitool("mc info");
    $self->ipmitool("mc selftest");
}

1;

# vim: set sw=4 et:
