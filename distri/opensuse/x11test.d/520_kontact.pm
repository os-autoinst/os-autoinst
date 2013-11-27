use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "kde";
}

sub run()
{
	my $self=shift;
	# start akonadi server avoid self-test running when launch kontact
	x11_start_program("akonadictl start");
	waitidle 3;
	# Workaround: sometimes the account assistant behind of mainwindow or tips window
	# To disable it run at first time start
	x11_start_program("echo \"[General]\" >> ~/.kde4/share/config/kmail2rc");
	x11_start_program("echo \"first-start=false\" >> ~/.kde4/share/config/kmail2rc");
	sleep 2;
	x11_start_program("kontact");
	# waitforneedle("kontact-assistant", 20);
	waitforneedle("test-kontact-1", 20); # tips window or assistant
	sendkey "alt-f4";
	waitforneedle("kontact-window", 3);
	sendkey "alt-f4";
}

1;
