package NET_inst_mirror;
use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return !$ENV{SUSEISO} || $ENV{SUSEISO}=~m/-NET-/;
}

sub run()
{
}

sub checklist()
{
	# return hashref:
	return {qw(
		6238258f9e9b27ab6999ef18a99b3670 OK
		09e9ad21be9c7bfb145a94a54731b5a8 OK
		40e0744ef785403befac39f2792e72e1 OK
		0667b01be02a7b8c4fcf335e260f1d13 OK
		04ee9bd8dcb1316874939f7b63d792c0 fail
		e7981cac5576dcd22aacebe08901956c fail
	)}
}

1;
