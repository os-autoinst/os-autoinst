use base "basetest";
use bmwqemu;
sub run()
{
	my $self=shift;
	script_sudo("zypper -n in screen rsync gvim");
	waitidle 60;
	script_run('echo $?');
	$self->take_screenshot;
	sendkey "ctrl-l"; # clear screen to see that second update does not do any more
	script_sudo("rpm -e screen");
	script_run("rpm -q screen");
}

sub checklist()
{
	# return hashref:
	return {qw(
		c791dbef555ddc3b9bcc11fc42fcea74 OK
	)}
}

1;
