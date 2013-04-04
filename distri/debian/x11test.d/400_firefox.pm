use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	x11_start_program("firefox");
	if($ENV{UPGRADE}) { sendkey("alt-d");waitidle; } # dont check for updated plugins
	$self->take_screenshot;
	sendkey "alt-h"; sleep 2;	# Help
	sendkey "a"; sleep 2;		# About
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 2;	# close About
	sendkey "alt-f4"; sleep 2;
	sendkey "ret"; # confirm "save&quit"
}

1;
