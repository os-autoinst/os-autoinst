use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "gnome";
}

sub run()
{
	my $self=shift;
	sendkey "ctrl-alt-delete"; # shutdown
	waitidle;
	$self->take_screenshot;
	sendkey "ret"; # confirm shutdown
	if(!$ENV{GNOME2}) {
		sleep 3;
		$self->take_screenshot;
		sendkey "ctrl-alt-f1";
		sleep 3;
		qemusend "system_powerdown"; # shutdown
	}
	waitinststage("splashscreen");
}

1;
