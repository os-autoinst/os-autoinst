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
	script_run('netstat');
	script_run("ps ax > /dev/$serialdev");
	sendkey "ctrl-c";
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
