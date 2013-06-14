# should be no longer needed as consoletest_finish tests for screensaver

use base "basetest";
use bmwqemu;

sub is_applicable()
{
#	return ($ENV{DESKTOP} eq "gnome");
	return 0;
}

sub run()
{
	my $self=shift;
	script_run("killall gnome-screensaver");
	$self->check_screen;
}

1;
