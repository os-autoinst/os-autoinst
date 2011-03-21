use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} =~ m/gnome|kde|xfce|lxde/;
}

sub run()
{
	my $self=shift;
	sendkey "alt-f1"; # open main menu
	sleep 2;
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
