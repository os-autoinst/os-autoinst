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
	wait_for_needle("kontact-assistant", 20);
	sendkey "alt-f4"; 
	wait_for_needle("test-kontact-1", 3); # tips window
	sendkey "alt-f4";
	wait_for_needle("kontact-window", 3);
	sendkey "alt-f4";
}

1;
