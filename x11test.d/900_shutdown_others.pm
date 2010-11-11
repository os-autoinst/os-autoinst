use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} =~ m/lxde|xfce|minimalx|textmode/;
}

sub run()
{
	my $self=shift;
	qemusend "system_powerdown"; # shutdown
	waitidle;
	$self->take_screenshot;
	#sendkey "ctrl-alt-f1"; # work-around for LXDE bug 619769 ; not needed in Factory anymore
	waitinststage("splashscreen");
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
