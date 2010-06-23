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
	sleep 4;
	sendautotype "\t";
	sleep 1;
	$self->take_screenshot;
	sendautotype "\n";
	waitinststage("splashscreen");
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
