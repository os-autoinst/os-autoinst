use base "basetest";
use strict;
use bmwqemu;

# have various useful general info included in videos
sub run()
{
	my $self=shift;
	script_run('uname -a');
#	$self->take_screenshot;
	script_run('df');
	script_run('free');
	script_run('rpm -qa kernel-*');
	script_run('grep DISPLAYMANAGER= /etc/sysconfig/displaymanager');
	script_run('grep DEFAULT /etc/sysconfig/windowmanager');
	script_run("ps ax > /dev/$serialdev");
	script_run("rpm -qa > /dev/$serialdev");
	sendkey "ctrl-c";
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
