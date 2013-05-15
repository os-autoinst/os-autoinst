use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return (($ENV{DESKTOP} eq "kde") and (!$ENV{LIVETEST} || $ENV{USBBOOT}));
}

sub run()
{
	my $self=shift;
	waitidle;
	sendkey "ctrl-alt-delete"; # reboot
	waitidle(15);
	sendautotype "\t\t";
	sleep 1;
	$self->check_screen;
	sendautotype "\n";
}

1;
