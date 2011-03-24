use base "basetest";
use strict;
use bmwqemu;

sub sendkeyw($) {sendkey(shift); waitidle;}

sub run()
{ my $self=shift;
        sendkey "alt-n";
        sleep 9; waitidle; # test internet con
	$self->take_screenshot;
        sendkey "alt-n";
        sleep 9; waitidle;
        # success
	$self->take_screenshot;
        sendkeyw "alt-n";
        # Online Update / novell customer center
        sendkey "alt-c"; # configure later
	$self->take_screenshot;
        sendkeyw "alt-n";
}

1;
