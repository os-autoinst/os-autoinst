use base "basetest";
use bmwqemu;


sub run()
{ my $self=shift;
	sendautotype "pacman -Sy\n";
	waitstillimage;
	sendautotype "pacman -S extra/alsa-utils && echo SUCCESS\n";
	sendautotype "Y\n";
	waitstillimage;
	waitidle;
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
