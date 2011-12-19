use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	ensure_installed("inkscape");
	x11_start_program("inkscape");
	$self->take_screenshot;
	sendkey "alt-f4"; # Exit
}

1;
