use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "gnome";
}

sub run()
{
	my $self=shift;
	waitidle;
	sendkey "ctrl-alt-delete"; # reboot
	sleep 2;
	sendkey "down"; # reboot
	sleep 2;
	sendkey "ret"; # confirm 
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
