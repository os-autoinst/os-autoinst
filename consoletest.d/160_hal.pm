use base "basetest";
use bmwqemu;
# for https://bugzilla.novell.com/show_bug.cgi?id=613898
# fixed in Build0679 and later
# TODO: revisit after 11.3 when hal is no more needed for KDE
sub run()
{
	my $self=shift;
	local $bmwqemu::timesidleneeded=4;
	script_sudo("zypper -n -q in hal");
	waitidle(60);
	$self->take_screenshot;
	sendkey("ctrl-l"); # clear screen
	script_sudo("/etc/init.d/haldaemon status");
	sleep 3;
	$self->take_screenshot;
	sendkey("ctrl-l"); # clear screen
	script_sudo("/sbin/insserv haldaemon");
}

sub checklist()
{
	# return hashref:
	return {qw(
		ca8d076bb34204f8cf11661f6a557a8b fail
		744a3572aa9f6d5e32c976d94d85abb1 fail
		58c29a498cdaa394a7972384b0c249f3 fail
		5bf4c8009eb2ee1fb181f477f45b2c09 OK
		dfee7b89a784ec027777a51e89e9d16b OK
		474fd876bd28ec3543f02367f4b70475 OK
	)}
}

1;
