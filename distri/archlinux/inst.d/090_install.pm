use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	sendkey "6"; # install
	sendkey "ret"; # ok
	sleep 1;
	sendkey "ret"; # close info box
	
	# installing packages

	local $ENV{SCREENSHOTINTERVAL}=5; # fast-forward
	$self->take_screenshot;
	sleep 1;

	waitstillimage(60,3600); # wait for install end

	$self->take_screenshot;
	sleep 1;
	sendkey "ret"; # close info box
	local $ENV{SCREENSHOTINTERVAL}=0.5; # just to be sure...
}

1;
