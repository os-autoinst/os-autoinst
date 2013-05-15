use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} =~ m/lxde|minimalx|textmode/;
}

sub run()
{
	my $self=shift;
	qemusend "system_powerdown"; # shutdown
	waitidle;
	$self->check_screen;
	#sendkey "ctrl-alt-f1"; # work-around for LXDE bug 619769 ; not needed in Factory anymore
	waitinststage("splashscreen");
}


1;
