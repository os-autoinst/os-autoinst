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

    die "$stderr" unless ($ret);
    print "IPMI: $stdout\n";
    return $stdout;
}

sub do_start_vm() {
    my ($self) = @_;

    # remove backend.crashed
    $self->unlink_crash_file();
    
    $self->ipmitool("mc reset cold");
    # now we need to wait for the unit to go away
    for my $i (1..10) {
	eval { $self->ipmitool("chassis power status") };
	last if ($@); # error is good in this case :)
	sleep(1);
    }

    # now we need to wait for it to come back
    while (1) {
	eval { $self->ipmitool("chassis power status") };
	last unless ($@);
	sleep(1);
    }

    $self->ipmitool("chassis power off");
    while (1) {
	my $ret = $self->ipmitool("chassis power status");
	last if $ret =~ m/off/;
	$self->ipmitool("chassis power off");
	sleep(1);
    }

    $self->ipmitool("chassis power on");
    while (1) {
	my $ret = $self->ipmitool("chassis power status");
	last if $ret =~ m/on/;
	$self->ipmitool("chassis power on");
	sleep(1);
    }

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
