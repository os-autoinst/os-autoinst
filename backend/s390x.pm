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
    $self->{s3270} = new backend::s390x::s3270 ({
	    ## s3270=>[qw(s3270)]; # non-interactive
	    s3270	=> [qw(x3270 -script -trace -set screenTrace -charset us)],
	    zVM_host	=> $vars->{ZVM_HOST},
	    guest_user	=> $vars->{ZVM_GUEST},
	    guest_login => $vars->{ZVM_PASSWORD},
	});


}

###################################################################
# linuxrc helpers

sub linuxrc_menu() {
    my ($self, $menu_title, $menu_entry) = @_;
    # get the menu (ends with /^>/)
    my $r = $self->{s3270}->expect_3270(output_delim => qr/^> /);
    ### say Dumper $r;

    # newline separate list of strings when interpolating...
    local $LIST_SEPARATOR = "\n";

    if (! grep /^$menu_title/, @$r) {
	confess "menu does not match expected menu title ${menu_title}\n @${r}";
    }

    my @match_entry = grep /\) $menu_entry/, @$r;

    if (!@match_entry) {
	confess "menu does not contain expected menu entry ${menu_entry}:\n@${r}";
    }

    my ($match_id) = $match_entry[0] =~ /(\d+)\)/;

    my $sequence = ["Clear", "String($match_id)", "ENTER"];

    $self->{s3270}->sequence_3270(@$sequence);
};

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

    my $test = new backend::s390x::get_to_yast();

    $r = $test->backend::s390x::get_to_yast::run();

    ###################################################################
    # now we are ready do connect to vnc and to start the vnc backend...

    while (1) { sleep 50; }

}

1;
