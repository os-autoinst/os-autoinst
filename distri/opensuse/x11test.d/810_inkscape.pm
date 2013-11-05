use base "basetest";
use bmwqemu;

sub is_applicable()
{
	if ($ENV{GNOME} && $ENV{LIVECD}) {
		return 0;
	} else {
		return 1;
	}
}

sub run()
{
	my $self=shift;
	ensure_installed("inkscape");
	x11_start_program("inkscape");
	$self->check_screen;
	sendkey "alt-f4"; # Exit
}

1;
