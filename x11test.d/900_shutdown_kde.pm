use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "kde";
}

sub run()
{
	my $self=shift;
	sendkey "ctrl-alt-delete"; # shutdown
	waitidle;
	sendautotype "\t";
	sleep 1;
	$self->take_screenshot;
	sendautotype "\n";
	waitinststage("splashscreen", 40);
}

1;
