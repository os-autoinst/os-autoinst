use base "basetest";
use bmwqemu;
sub run()
{
	my $self=shift;
	script_sudo("zypper -n removerepo 2") if($ENV{DVD}); # remove repo on ejected DVD
	script_run('zypper lr -d');
	script_sudo("zypper -n in screen rsync gvim");
	waitidle 60;
	script_run('echo $?');
	$self->take_screenshot;
	sendkey "ctrl-l"; # clear screen to see that second update does not do any more
	script_sudo("rpm -e gvim");
	script_run("rpm -q gvim");
}

sub checklist()
{
	# return hashref:
	return {qw(
		c791dbef555ddc3b9bcc11fc42fcea74 OK
		34a442bdb544f972768a48202154d9ac OK
		bf434c1b28f4b9ee004506f0faefeb38 fail
	)}
}

1;
