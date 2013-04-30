use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	# speed up main install video
	local $ENV{SCREENSHOTINTERVAL}=5;
	waitinststage("debian-grubinstall", 3600);
	$self->take_screenshot; sleep 1;
	sendkey "ret"; # install grub into MBR
}

1;
