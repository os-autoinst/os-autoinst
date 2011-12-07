use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	sendkey "3"; # clock
	sendkey "ret"; # ok
	sleep 2;
	sendkey "ret"; # timezone ok
	sleep 2;
	sendkey "e"; # europe
	sleep 1;
	sendkey "ret"; # ok
	sleep 2;
	sendkey "b";
	sleep 1;
	sendkey "b"; # berlin
	sleep 1;
	$self->take_screenshot;
	sleep 1;
	sendkey "ret"; # ok
	sleep 2;
	sendkey "3"; # back
	sendkey "ret"; # ok
}

1;
