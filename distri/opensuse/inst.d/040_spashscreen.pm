use strict;
use base "basetest";
use bmwqemu;

sub is_applicable
{
	return !$ENV{NICEVIDEO};
}

sub run()
{
	# TODO: what is this all about?
	return;
	my $self=shift;
	# time to load kernel+initrd
	waitforneedle("inst-splashscreen", 12);
	sendkey "esc";
}

1;
