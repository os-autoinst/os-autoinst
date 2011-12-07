use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	sendkey "9"; # exit
	sendkeyw "ret"; # ok
	$self->take_screenshot;
	sleep 1;
	sendkey "ret"; # close info box
}

1;
