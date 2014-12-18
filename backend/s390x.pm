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

sub linuxrc_prompt () {
    my ($self, $prompt, %arg) = @_;

    $arg{value}   //= '';
    $arg{timeout} //= 1;

    my $r = $self->{s3270}->expect_3270(output_delim => qr/(?:\[.*?\])?> /, timeout => $arg{timeout});

    ### say Dumper $r;

    # two lines or more
    # [previous repsonse]
    # PROMPT
    # [more PROMPT]
    # [\[EXPECTED_RESPONSE\]]>

    # newline separate list of strings when interpolating...
    local $LIST_SEPARATOR = "\n";

    if (! grep /^$prompt/, @$r[0..(@$r-1)] ) {
	confess
	    "prompt does not match expected prompt (${prompt}) :\n".
	    "@$r";
    }

    my $sequence = ["Clear", "String($arg{value})", "ENTER"];
    push @$sequence, "ENTER" if $arg{value} eq '';

    $self->{s3270}->sequence_3270(@$sequence);

};


sub ftpboot_menu () {
    my ($self, $menu_entry) = @_;
    # helper vars
    my ($r, $s, $cursor_row, $row);

    # choose server

    $r = $self->{s3270}->send_3270("Home");
    # Why can't I just call this function?  why do I need & ??
    $s = &backend::s390x::s3270::nice_3270_status($r->{terminal_status});

    $cursor_row = $s->{cursor_row};

    $r = $self->{s3270}->expect_3270(clear_buffer => 1, flush_lines => undef, buffer_ready => qr/PF3=QUIT/);
    ### say Dumper @$r;

    while ( ($row, my $content) = each(@$r)) {
    	if ($content =~ $menu_entry) {
    	    last;
    	}
    };

    my $sequence = ["Home", ("Down") x ($row-$cursor_row), "ENTER", "Wait(InputField)"];
    ## say "\$sequence=@$sequence";

    $self->{s3270}->sequence_3270(@$sequence);

    return $r;
    say $r;
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

    my $test = new backend::s390x::get_to_yast();

    $r = $test->backend::s390x::get_to_yast::run();

    ###################################################################
    # now we are ready do connect to vnc and to start the vnc backend...

    while (1) { sleep 50; }

}

1;
