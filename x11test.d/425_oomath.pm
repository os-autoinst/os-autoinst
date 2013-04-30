use base "basetest";
use bmwqemu;
# test for bug https://bugs.freedesktop.org/show_bug.cgi?id=42301

sub is_applicable()
{
	return 0 if $ENV{NICEVIDEO};
	return $ENV{DESKTOP}=~/kde|gnome/ && !$ENV{LIVECD};
}

sub run()
{
	my $self=shift;
	x11_start_program("oomath");
	sendautotype "E %PHI = H %PHI\nnewline\n1 = 1";
	sleep 3;
	# test broken undo
	sendkey "shift-left";
	sendkey "2";
	sendkey "ctrl-z"; # undo produces "12" instead of "1"
	sleep 3;
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 2;
	$self->take_screenshot;
	sendkey "alt-d"; sleep 2; # Discard
}

1;
