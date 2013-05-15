use base "basetest";
use bmwqemu;

sub is_applicable
{
	return !$ENV{NICEVIDEO};
}

sub run()
{
	my $self=shift;
	mouse_hide(1);
	x11_start_program("xterm");
	sleep 2;
	sendautotype("cd\n"); sleep 1; # go to $HOME (for KDE)
	sendkey "ctrl-l"; # clear
	for(1..13) { sendkey "ret" }
	sendautotype("echo If you can see this text xterm is working.\n");
	sleep 2;
	$self->check_screen;
	sendkey "alt-f4"; sleep 2;
}

1;
