use base "basetest";
use bmwqemu;
# test yast2 bootloader functionality
# https://bugzilla.novell.com/show_bug.cgi?id=610454

sub is_applicable()
{
	return !$ENV{LIVETEST};
}

sub run()
{
	my $self=shift;
	script_sudo("/sbin/yast2 bootloader");
	sleep 3;
	$self->take_screenshot;
	sendkey "alt-o"; # OK => Close # might just close warning on livecd
	sleep 2;
	sendkey "alt-o"; # OK => Close
	waitidle;
	$self->take_screenshot;
	sendkey "ctrl-l";
	script_run('echo $?');
	$self->take_screenshot;
	script_run('rpm -q hwinfo');
}

sub checklist()
{
	# return hashref:
	return {qw(
		1e58b9fb6cd585dfc84d1aa82e1429d7 fail
		3b66e185a5cb6dbaffeb87aeb0eed1ed OK
		b10b2e47efa46758ef11b0a926152923 OK
		fefbf722e76e2462ee73092fa0f4f93b OK
		c286567d8e58a1aeba6d286dfaf2e17c OK
		e7069ee7d1b3cdf801eaa5d1e092dd0e OK
	)}
}

1;
