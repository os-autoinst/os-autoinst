use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "kde";
}

sub run()
{
	my $self=shift;
	x11_start_program("systemsettings");
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 2;
}

sub checklist()
{
	# return hashref:
	return {qw(
		e965fa85fc856444f5ca74f5d09f3a1e OK
		5c67770e34efaa16eec64fb2fb908051 OK
		7af21a44b3e7ee2119968334dbda25ba OK
		c517f9a7eeaabaef0b6d6fe9010a271b OK
	)}
}

1;
