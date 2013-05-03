use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "gnome";
}

sub run()
{
	my $self=shift;
	x11_start_program("evolution");
	if($ENV{UPGRADE}) { sendkey("alt-f4");waitidle; } # close mail format change notifier
	$self->check_screen;sleep 1;
	sendkey "ctrl-q"; # really quit (alt-f4 just backgrounds)
	sendkey "alt-f4"; 
	waitidle;
}

1;
