use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return !$ENV{NICEVIDEO};
}

sub run()
{
	my $self=shift;
	ensure_installed("gimp");
	x11_start_program("gimp");
	$self->take_screenshot;
	sendkey "alt-f4"; # Exit
}

1;
