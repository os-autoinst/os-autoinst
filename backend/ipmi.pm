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
use Data::Dump qw/pp/;
use POSIX qw/strftime :sys_wait_h/;
use JSON;
require Carp;
use Fcntl;
use bmwqemu qw(fileContent diag save_vars diag);
use backend::VNC;

sub new {
    my $class = shift;
    my $self = bless( { class => $class }, $class );
    return $self;
}

use Time::HiRes qw(gettimeofday);

sub do_start_vm() {
    my ($self) = @_;

    # remove backend.crashed
    $self->unlink_crash_file();

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

    # make sure it's on
    system('ipmitool', '-H', $bmwqemu::vars{'IPMI_HOSTNAME'},'-U', $bmwqemu::vars{'IPMI_USER'},'-P', $bmwqemu::vars{'IPMI_PASSWORD'},'chassis', 'power', 'on');
    sleep(8);

    # now give it a warm reboot
    system('ipmitool', '-H', $bmwqemu::vars{'IPMI_HOSTNAME'},'-U', $bmwqemu::vars{'IPMI_USER'},'-P', $bmwqemu::vars{'IPMI_PASSWORD'},'chassis', 'power', 'reset');

    $self->{'select'}->add($self->{'vnc'}->socket);
    $self->{'vnc'}->send_update_request;
}

sub do_stop_vm() {
    my ($self) = @_;

    system('ipmitool', '-H', $bmwqemu::vars{'IPMI_HOSTNAME'},'-U', $bmwqemu::vars{'IPMI_USER'},'-P', $bmwqemu::vars{'IPMI_PASSWORD'},'chassis', 'power', 'off');
}

1;

# vim: set sw=4 et:
