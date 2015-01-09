#!/usr/bin/perl -w

package backend::ipmi;
use strict;
use base ('backend::vnc_backend');
use threads;
use threads::shared;
require File::Temp;
use File::Temp ();
use Time::HiRes qw(sleep gettimeofday);
use IO::Select;
use IO::Socket::UNIX qw( SOCK_STREAM );
use IO::Handle;
use Data::Dumper;
use POSIX qw/strftime :sys_wait_h/;
use JSON;
require Carp;
use Fcntl;
use bmwqemu qw(fileContent diag save_vars diag);
use backend::VNC;
use IPC::Run ();

sub new {
    my $class = shift;
    my $self = bless( { class => $class }, $class );
    return $self;
}

use Time::HiRes qw(gettimeofday);

sub ipmitool($) {
    my ($self, $cmd) = @_;

    my @cmd = ('ipmitool', '-H', $bmwqemu::vars{'IPMI_HOSTNAME'},'-U', $bmwqemu::vars{'IPMI_USER'},'-P', $bmwqemu::vars{'IPMI_PASSWORD'});
    push(@cmd, split(/ /, $cmd));

    my ($stdin, $stdout, $stderr, $ret);
    $ret = IPC::Run::run(\@cmd, \$stdin, \$stdout, \$stderr);
    chomp $stdout;
    chomp $stderr;

    die join(' ', @cmd) . ": $stderr" unless ($ret);
    print "IPMI: $stdout\n";
    return $stdout;
}

sub restart_host() {
    my ($self) = @_;

    $self->ipmitool("chassis power off");
    while (1) {
        my $ret = $self->ipmitool("chassis power status");
        last if $ret =~ m/is off/;
        $self->ipmitool("chassis power off");
        sleep(2);
    }

    $self->ipmitool("chassis power on");
    while (1) {
        my $ret = $self->ipmitool("chassis power status");
        last if $ret =~ m/is on/;
        $self->ipmitool("chassis power on");
        sleep(2);
    }
}

sub do_start_vm() {
    my ($self) = @_;

    # remove backend.crashed
    $self->unlink_crash_file();

    $self->restart_host;

    $self->{'vnc'}  = backend::VNC->new(
        {
            hostname => $bmwqemu::vars{'IPMI_HOSTNAME'},
            port => 5900,
            username => $bmwqemu::vars{'IPMI_USER'},
            password => $bmwqemu::vars{'IPMI_PASSWORD'},
            ikvm => 1
        }
    );
    eval { $self->{'vnc'}->login; };
    if ($@) {
        $self->close_pipes();
        die $@;
    }

    $self->{'select'}->add($self->{'vnc'}->socket);
    $self->{'vnc'}->send_update_request;
}

sub do_stop_vm() {
    my ($self) = @_;

    $self->ipmitool("chassis power off");
}

1;

# vim: set sw=4 et:
