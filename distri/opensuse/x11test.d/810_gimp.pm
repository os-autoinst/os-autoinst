use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return 0 if $ENV{NICEVIDEO};
	if ($ENV{KDE} && $ENV{LIVECD}) {
		return 0;
	} else {
		return 1;
	}
}

sub run()
{
	my $self=shift;
	ensure_installed("gimp");
	x11_start_program("gimp");
	$self->check_screen;
	sendkey "alt-f4"; # Exit
}

1;
