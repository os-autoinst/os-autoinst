use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
	sendautotype "$password\t"; # root PW
	sendautotype "$password\t";
	$self->take_screenshot;
        sendkeyw "alt-n";
        sleep 2;
        sendkeyw "alt-y"; # confirm weak PW
}

1;
