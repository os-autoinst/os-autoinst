#!/usr/bin/perl -w
package backend::s390x;

use base ('backend::vnc_backend');

use strict;
use warnings;
use English;

use Data::Dumper qw(Dumper);
use Carp qw(confess cluck carp croak);

use feature qw/say/;

use backend::s390x::s3270;

use backend::VNC;

# this is evil, so evil:
# \%bmwqemu::vars;

# FIXME: what is this needed for?
sub new {
    my $class = shift;
    my $self = bless( { class => $class }, $class );
    return $self;
}

sub setup_3270_console() {
    my $self = shift;

    my $vars = \%bmwqemu::vars;

    confess "ZVMHOST unset in vars.json" unless exists $vars->{ZVM_HOST};
    confess "ZVM_GUEST unset in vars.json" unless exists $vars->{ZVM_GUEST};
    confess "ZVM_PASSWORD unset in vars.json" unless exists $vars->{ZVM_PASSWORD};

    $self->{vars} = $vars;
    $self->{s3270} = new backend::s390x::s3270(
        {
            ## TODO make s3270 depend on some DEBUG flag or interactive
            ## flag. hm. maybe $DISPLAY?

            ## Or start in local Xvnc session or Xnest session, and do screen
            ## grabs from there...

            ## s3270=>[qw(s3270)]; # non-interactive
            s3270	=> [qw(x3270 -script -trace -set screenTrace -charset us -xrm x3270.visualBell:true)],
            zVM_host	=> $vars->{ZVM_HOST},
            guest_user	=> $vars->{ZVM_GUEST},
            guest_login => $vars->{ZVM_PASSWORD},
        }
    );


}
###################################################################
# vnc specific stuff

sub connect_vnc() {
    my ($self) = @_;

    if ($self->{'vnc'}) {
        $self->{'select'}->remove($self->{'vnc'}->socket);
        close($self->{'vnc'}->socket);
        sleep(1);
    }
    $self->{'vnc'}  = backend::VNC->new(
        {
            hostname => $self->{vars}{PARMFILE}{Hostname},
            port => 5901,
            password => $self->{vars}{DISPLAY}{PASSWORD},
            ikvm => 0
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


# For now, we run the testcase from here until we have a vnc connection going.
# TODO: move the test case to the test cases.
require backend::s390x::get_to_yast;

###################################################################
sub do_start_vm() {
    my $self = shift;

    $self->unlink_crash_file();

    $self->setup_3270_console();

    my $s3270 = $self->{s3270};

    my $r;


    $r = $s3270->start();

    $r = $s3270->connect_and_login()
      unless ($self->{vars}{DEBUG_VNC} eq "try vncviewer");

    my $test = new backend::s390x::get_to_yast($s3270, $self->{vars});

    $r = $test->backend::s390x::get_to_yast::run()
      unless ($self->{vars}{DEBUG_VNC} eq "try vncviewer");

    ###################################################################
    # now we are ready do connect to vnc and to start the vnc backend...
    eval {
        if ($self->{vars}{DEBUG_VNC} eq "setup vnc") {
            my $r = $s3270->cp_disconnect();
            cluck $r;
        }
        else {
            $self->connect_vnc();
        }
    };

    # while developing: cluck.  in real life:  confess!
    # confess $@ if $@;
    cluck $@if $@;

    ## also for development only:  just keep going...
    #while (1) { sleep 50; }

    return 1;

}

sub do_stop_vm() {
    my ($self) = @_;
    if ($self->{vars}{DEBUG_VNC} eq "no") {
	$self->{s3270}->cp_logoff_disconnect()
    }
    else {
	$self->{s3270}->cp_disconnect()
    };
}

sub do_savevm() {
    notimplemented;
}

sub do_loadvm() {
    notimplemented;
}

1;
