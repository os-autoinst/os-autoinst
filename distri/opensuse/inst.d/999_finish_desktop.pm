use base "basetest";
use bmwqemu;

sub run()
{
	my $self = shift;

	waitforneedle("desktop-at-first-boot", 60);
}

1;
