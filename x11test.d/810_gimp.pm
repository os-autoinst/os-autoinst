use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	ensure_installed("gimp");
	x11_start_program("gimp");
	$self->take_screenshot;
	sendkey "alt-f4"; # Exit
}

1;
