use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} =~ m/gnome|kde|xfce|lxde/;
}

sub run()
{
	my $self=shift;
	if($ENV{DESKTOP} eq "lxde") {
		x11_start_program("lxpanelctl menu"); # or Super_L or Windows key
	} elsif($ENV{DESKTOP} eq "xfce") {
		mouse_set(0,0);
		sleep 1;
		sendkey "ctrl-esc";	# open menu
		sleep 1;
		sendkey "up";		# go into Applications submenu
	} else {
		sendkey "alt-f1"; # open main menu
	}
	sleep 2;
	sleep 10 if $ENV{NICEVIDEO};
	$self->take_screenshot;
	sendkey "esc"; 
	waitidle;
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
