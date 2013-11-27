use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return 0 if $ENV{NICEVIDEO};
	return !($ENV{KDE} && $ENV{LIVECD});
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
