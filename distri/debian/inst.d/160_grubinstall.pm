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

sub checklist()
{
	return {qw(
		8391a358f3ab59ff96c4db7910441d15 OK
	)}
}

1;
