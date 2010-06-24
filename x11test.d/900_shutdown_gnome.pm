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
	sleep 2;
	$self->take_screenshot;
	sendkey "ret"; # confirm shutdown
	waitinststage("splashscreen");
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
