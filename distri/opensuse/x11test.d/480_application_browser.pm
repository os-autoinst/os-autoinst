use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "gnome" && $ENV{GNOME2};
}

sub run()
{
	my $self=shift;
	x11_start_program("application-browser");
	$self->check_screen;
	sendkey "alt-f4"; 
	waitidle;
}

1;
