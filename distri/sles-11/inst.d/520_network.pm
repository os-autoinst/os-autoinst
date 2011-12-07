use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
	waitstillimage(20,60);
        mousemove_raw(31000, 31000); # move mouse off screen again
	$self->take_screenshot;
        sendkeyw "alt-n";
	sleep 10;
	waitstillimage(20,60);
}

1;
