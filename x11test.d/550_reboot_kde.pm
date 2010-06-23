use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "kde";
}

sub run()
{
	my $self=shift;
	waitidle;
	sendkey "ctrl-alt-delete"; # reboot
	sleep 4;
	sendautotype "\t\t";
	sleep 1;
	$self->take_screenshot;
	sendautotype "\n";
	waitinststage "grub", 200; # wait until reboot

}

sub checklist()
{
	# return hashref:
	return {qw(
		7a92ffcf15a7928d2510af0b55e48132 OK
	)}
}

1;
