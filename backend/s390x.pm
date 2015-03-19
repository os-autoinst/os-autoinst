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

use testapi qw(get_var check_var);

sub new {
    my $class = shift;
    my $self = bless( { class => $class }, $class );
    return $self;
}

sub setup_3270_console() {
    my $self = shift;

    confess "ZVMHOST unset in vars.json" unless get_var("ZVM_HOST");
    confess "ZVM_GUEST unset in vars.json" unless get_var("ZVM_GUEST");
    confess "ZVM_PASSWORD unset in vars.json" unless get_var("ZVM_PASSWORD");

    $self->{s3270} = new backend::s390x::s3270(
        {
            ## TODO make s3270 depend on some DEBUG flag or interactive
            ## flag. hm. maybe $DISPLAY?

            ## Or start in local Xvnc session or Xnest session, and do screen
            ## grabs from there...

            ## s3270=>[qw(s3270 ...)]; # non-interactive
            s3270	=> [qw(x3270 -script -trace -set screenTrace -charset us -xrm x3270.visualBell:true), '-xrm', 'x3270.traceDir: .'],

            zVM_host	=> get_var("ZVM_HOST"),
            guest_user	=> get_var("ZVM_GUEST"),
            guest_login => get_var("ZVM_PASSWORD"),
        }
    );


}
###################################################################
# vnc specific stuff

sub connect_vnc() {
    my ($self) = shift;
    if ($self->{'vnc'}) {
        #$self->{'select'}->remove($self->{'vnc'}->socket);
        close($self->{'vnc'}->socket);
        sleep(1);
    }
    $self->{'vnc'}  = backend::VNC->new(
        {
            hostname => get_var("PARMFILE")->{Hostname},
            port => 5901,
            password => get_var("DISPLAY")->{PASSWORD},
            ikvm => 0
        }
    );
    eval { $self->{'vnc'}->login; };
    if ($@) {
        $self->close_pipes();
        die $@;
    }

    $self->capture_screenshot();

}


###################################################################
sub do_start_vm() {
    my $self = shift;

    $self->unlink_crash_file();

    $self->setup_3270_console();

    my $r;

    $r = $self->{s3270}->start();

    return 1;

}

sub do_stop_vm() {
    my ($self) = @_;
    if (exists get_var("DEBUG")->{"keep zVM guest"}) {
        $self->{s3270}->cp_disconnect();
    }
    else {
        $self->{s3270}->cp_logoff_disconnect();
    }
}

sub do_savevm() {
    notimplemented;
}

sub do_loadvm() {
    notimplemented;
}


1;
