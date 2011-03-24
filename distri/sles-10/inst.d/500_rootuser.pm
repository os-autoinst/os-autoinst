use base "basetest";
use strict;
use bmwqemu;

sub sendkeyw($) {sendkey(shift); waitidle;}

sub run()
{ my $self=shift;

        mousemove_raw(31000, 31000); # move mouse off screen again
	sendautotype "$password\t"; # root PW
	sendautotype "$password";
	$self->take_screenshot;
        sendkeyw "alt-n";
}

1;
