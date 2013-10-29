use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "kde";
}

sub run()
{
	my $self=shift;
	x11_start_program("kontact");
	waitforneedle("kontact-assistant", 20);
	sendkey "alt-f4"; 
	waitforneedle("test-kontact-1", 3); # tips window
	sendkey "alt-f4";
	waitforneedle("kontact-window", 3);
	sendkey "alt-f4";
}

1;
