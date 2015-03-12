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

sub ipmi_cmdline() {
    my ($self) = @_;

    return ('ipmitool', '-H', $bmwqemu::vars{'IPMI_HOSTNAME'},'-U', $bmwqemu::vars{'IPMI_USER'},'-P', $bmwqemu::vars{'IPMI_PASSWORD'});
}

sub ipmitool($) {
    my ($self, $cmd) = @_;

    my @cmd = $self->ipmi_cmdline();
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

sub init_charmap() {
    my ($self) = @_;

    $self->SUPER::init_charmap();
    for my $c ( "A" .. "Z" ) {
        $self->{charmap}->{$c} = "shift-\L$c";
    }
}

sub relogin_vnc() {
    my ($self) = @_;

    if ($self->{'vnc'}) {
        #$self->{'select'}->remove($self->{'vnc'}->socket);
        close($self->{'vnc'}->socket);
        sleep(1);
    }
    $self->{'vnc'}  = backend::VNC->new(
        {
            hostname => $bmwqemu::vars{'IPMI_HOSTNAME'},
            port => 5900,
            username => $bmwqemu::vars{'IPMI_USER'},
            password => $bmwqemu::vars{'IPMI_PASSWORD'},
            ikvm => 1,
            # FIXME: not needed?
            # update_request_throttle_seconds => 2,
        }
    );
    eval { $self->{'vnc'}->login; };
    if ($@) {
        $self->close_pipes();
        die $@;
    }

    $self->capture_screenshot();
}

sub do_start_vm() {
    my ($self) = @_;

    # remove backend.crashed
    $self->unlink_crash_file;
    $self->restart_host;
    $self->relogin_vnc;
    $self->start_serial_grab;
    return {};
}

sub do_stop_vm() {
    my ($self) = @_;

    $self->ipmitool("chassis power off");
    $self->stop_serial_grab();
}

sub do_savevm($) {
    my ( $self, $args ) = @_;
    print "do_savevm ignored\n";
    return {};
}

sub do_loadvm($) {
    my ( $self, $args ) = @_;
    die "if you need loadvm, you're screwed with IPMI";
}

# serial grab

sub start_serial_grab() {
    my $self = shift;
    my $pid = fork();
    if ( $pid == 0 ) {
        my @cmd = $self->ipmi_cmdline();
        push(@cmd, ("-I", "lanplus", "sol", "activate"));
        #unshift(@cmd, ("setsid", "-w"));
        print join(" ", @cmd);

        open( my $serial, '>', $bmwqemu::serialfile ) || die "can't open $bmwqemu::serialfile";
        open(STDOUT, ">&", $serial) || die "can't dup stdout: $!";
        open(STDERR, ">&", $serial) || die "can't dup stderr: $!";
        open( my $zero, '<', '/dev/zero');
        open(STDIN, ">&", $zero);
        exec("script", "-efqc", "@cmd");
        die "exec failed $!";
    }
    else {
        $self->{'serialpid'} = $pid;
    }
}

sub stop_serial_grab($) {
    my $self = shift;
    return unless $self->{'serialpid'};
    system("pkill", "-P", $self->{'serialpid'});
    kill("TERM", $self->{'serialpid'});
    waitpid($self->{'serialpid'}, 0);
}

# serial grab end

1;

# vim: set sw=4 et:
