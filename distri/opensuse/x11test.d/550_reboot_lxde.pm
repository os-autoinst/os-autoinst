use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "lxde";
}

sub run()
{
	my $self=shift;
	waitidle;
	#sendkey "ctrl-alt-delete"; # does open task manager instead of reboot
	x11_start_program("xterm");
	script_sudo "/sbin/reboot",0;
}

1;
