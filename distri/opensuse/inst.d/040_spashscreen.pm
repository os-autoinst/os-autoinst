use strict;
use base "basetest";
use bmwqemu;

# TODO: what is this all about?

sub is_applicable
{
	#return !$ENV{NICEVIDEO};
	return 0; # FIXME
}

sub run()
{
	my $self=shift;
	# time to load kernel+initrd
	waitforneedle("inst-splashscreen", 12);
	sendkey "esc";
}

1;
