use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "gnome" && !$ENV{LIVECD};
}

sub run()
{
	my $self=shift;
	ensure_installed("thunderbird");
	x11_start_program("thunderbird");
	$self->check_screen;
	sendkeyw "alt-f4";	# close wizzard
	sendkeyw "alt-f4";	# close prog
}

1;
