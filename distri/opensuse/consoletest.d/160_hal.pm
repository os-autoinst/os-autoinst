use base "basetest";
use bmwqemu;
# for https://bugzilla.novell.com/show_bug.cgi?id=613898
# fixed in Build0679 and later
# 2011-02 hal is hardly needed anymore

sub is_applicable()
{
	return 0;
}

sub run()
{
	my $self=shift;
	local $bmwqemu::timesidleneeded=4;
	script_sudo("zypper -n -q in hal");
	waitidle(60);
	$self->check_screen;
	sendkey("ctrl-l"); # clear screen
	script_sudo("/etc/init.d/haldaemon status");
	sleep 3;
	$self->check_screen;
	sendkey("ctrl-l"); # clear screen
	script_sudo("/sbin/insserv haldaemon");
}

1;
