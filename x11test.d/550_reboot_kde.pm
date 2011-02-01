use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return (($ENV{DESKTOP} eq "kde") and !$ENV{LIVETEST});
}

sub run()
{
	my $self=shift;
	waitidle;
	sendkey "ctrl-alt-delete"; # reboot
	waitidle(15);
	sendautotype "\t\t";
	sleep 1;
	$self->take_screenshot;
	sendautotype "\n";
}

sub checklist()
{
	# return hashref:
	return {qw(
		7a92ffcf15a7928d2510af0b55e48132 OK
		69773b7d7a0862d526003fd54470531d OK
	)}
}

1;
