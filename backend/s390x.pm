#!/usr/bin/perl -w
package backend::s390x;
use base ('backend::baseclass');

use strict;
use warnings;
use English;

use Data::Dumper qw(Dumper);
use Carp qw(confess cluck carp croak);

use feature qw/say/;

use backend::s390x::s3270;

# this is evil, so evil:
# \%bmwqemu::vars;

sub init() {
    my $self = shift;

    my $vars = \%bmwqemu::vars;

    confess "ZVMHOST unset in vars.json" unless exists $vars->{ZVM_HOST};
    confess "ZVM_GUEST unset in vars.json" unless exists $vars->{ZVM_GUEST};
    confess "ZVM_PASSWORD unset in vars.json" unless exists $vars->{ZVM_PASSWORD};

    # TODO ftp/nfs/hhtp/https
    # TODO dasd/iSCSI/SCSI
    # TODO osa/hsi/ctc


    ## TODO make s3270=> depend on some DEBUG flag or interactive
    ## flag. hm. maybe $DISPLAY?

    $self->{vars} = $vars;
    $self->{s3270} = new backend::s390x::s3270(
        {
            ## s3270=>[qw(s3270)]; # non-interactive
            s3270	=> [qw(x3270 -script -trace -set screenTrace -charset us -xrm x3270.visualBell:true)],
            zVM_host	=> $vars->{ZVM_HOST},
            guest_user	=> $vars->{ZVM_GUEST},
            guest_login => $vars->{ZVM_PASSWORD},
        }
    );


}

# For now, we run the testcase from here until we have a vnc connection going.
# TODO: move the test case to the test cases.
require backend::s390x::get_to_yast;

###################################################################
sub do_start_vm() {
    my $self = shift;

    my $s3270 = $self->{s3270};

    my $r;


    $r = $s3270->start();

    $r = $s3270->login();

    my $test = new backend::s390x::get_to_yast($s3270, $self->{vars});

    $r = $test->backend::s390x::get_to_yast::run();

    ###################################################################
    # now we are ready do connect to vnc and to start the vnc backend...

    while (1) { sleep 50; }

}

1;
