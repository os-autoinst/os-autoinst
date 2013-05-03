use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "gnome";
}

sub run()
{
	my $self=shift;
	x11_start_program("nautilus");
	$self->check_screen;
	sendkey "alt-f4"; sleep 2;
}

1;
