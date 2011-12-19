use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	waitstillimage(7,20); # boot up
	$self->take_screenshot; sleep 1;
	sendkey "ret"; # lang
	sendkey "ret"; # country
	sendkey "ret"; # keymap
}

1;
