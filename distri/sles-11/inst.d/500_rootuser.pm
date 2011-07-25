use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
	waitinststage("config-rootpw",90);
        mousemove_raw(31000, 31000); # move mouse off screen again
	sendautotype "$password\t"; # root PW
	sendautotype "$password";
	$self->take_screenshot;
        sendkeyw "alt-n";
        sendkeyw "alt-y"; # confirm weak PW
}

1;
