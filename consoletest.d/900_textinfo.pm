use base "basetest";
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
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
