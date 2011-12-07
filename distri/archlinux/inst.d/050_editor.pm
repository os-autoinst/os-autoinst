use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	sendkey "2"; # set editor
	sleep 1;
	sendkey "ret"; # ok
	sleep 1;
	sendkey "v"; # vi
	sleep 1;
	$self->take_screenshot;
	sleep 1;
	sendkey "ret"; # ok
}

1;
