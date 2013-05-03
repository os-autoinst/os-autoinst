use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	ensure_installed("inkscape");
	x11_start_program("inkscape");
	$self->check_screen;
	sendkey "alt-f4"; # Exit
}

1;
