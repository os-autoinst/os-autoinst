use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "xfce";
}

sub run()
{
	my $self=shift;
	for(1..5) {
		sendkey "alt-f4"; # opens log out popup after all windows closed
	}
	waitidle;
	sendautotype "\t\t"; # select shutdown
	sleep 1;
	$self->check_screen;
	sendautotype "\n";
	waitinststage("splashscreen");
}

1;
