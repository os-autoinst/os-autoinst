use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return ($ENV{DESKTOP} eq "gnome");
}

sub run()
{
	my $self=shift;
	script_run("killall gnome-screensaver");
}

1;
