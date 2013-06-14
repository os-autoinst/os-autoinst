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
	sendkey "ctrl-l"; # redraw in case kernel painted on us
	sleep 3;
	$self->check_screen;
	sendkey "alt-o"; # OK => Close # might just close warning on livecd
	sleep 2;
	sendkey "alt-o"; # OK => Close
	waitidle;
	$self->take_screenshot;
	sendkey "ctrl-l";
	script_run('echo $?');
	waitforneedle("exited-bootloader", 2);
	script_run('rpm -q hwinfo');
	$self->take_screenshot;
}

1;
