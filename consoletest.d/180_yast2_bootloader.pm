use base "basetest";
use bmwqemu;
# test yast2 bootloader functionality
# https://bugzilla.novell.com/show_bug.cgi?id=610454


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
	)}
}

1;
